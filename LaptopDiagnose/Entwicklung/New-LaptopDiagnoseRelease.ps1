#Requires -Version 5.1
<#
.SYNOPSIS
    Erstellt das Release-Paket von LaptopDiagnose für den Update-Kanal (GitHub-Release).

.DESCRIPTION
    Erzeugt dist\LaptopDiagnose-<Version>.zip samt Prüfsumme und legt das Paket mit dem Update-Manifest
    update\update.json in den Update-Kanal. Optional werden die Skripte vorher signiert (-Signieren).
    Anschließend die Änderungen committen und in den Hauptzweig (main) übernehmen – installierte Programme
    finden das Update dann über »Einstellungen › Programm-Updates«.

.EXAMPLE
    .\New-LaptopDiagnoseRelease.ps1
    .\New-LaptopDiagnoseRelease.ps1 -Signieren -Thumbprint 0123ABCD... -Notizen 'Neue Herunterfahren-Diagnose'

.NOTES
    Copyright 2026 by Eder Tom
#>
[CmdletBinding()]
param(
    [switch]$Signieren,
    [string]$Thumbprint,
    [string]$PfxPath,
    [switch]$SignTool,
    [string]$Dlib,
    [string]$DlibMetadata,
    [string]$Notizen = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$engine = Get-Content -LiteralPath (Join-Path $root 'LaptopDiagnose.ps1') -Raw
if ($engine -notmatch "ToolVersion = '([\d\.]+)'") { throw 'Version nicht gefunden.' }
$version = $Matches[1]

if ($Signieren) {
    $signArgs = @{}
    if ($Thumbprint) { $signArgs.Thumbprint = $Thumbprint }
    if ($PfxPath) { $signArgs.PfxPath = $PfxPath }
    if ($SignTool) { $signArgs.SignTool = $true }
    if ($Dlib) { $signArgs.Dlib = $Dlib; $signArgs.DlibMetadata = $DlibMetadata }
    & (Join-Path $PSScriptRoot 'Sign-LaptopDiagnose.ps1') @signArgs
}

$dist = Join-Path $root 'dist'
$staging = Join-Path $dist "LaptopDiagnose-$version"
if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force }
$null = New-Item -ItemType Directory -Path $staging -Force

$include = @('LaptopDiagnose.ps1', 'LaptopDiagnoseGUI.ps1', 'Start-LaptopDiagnose.cmd', 'Start-LaptopDiagnose-Konsole.cmd',
    'Install-LaptopDiagnose.ps1', 'Install-LaptopDiagnose.cmd', 'Uninstall-LaptopDiagnose.ps1', 'LaptopDiagnose.ico', 'Logo.png', 'README.md')
foreach ($f in $include) { Copy-Item -LiteralPath (Join-Path $root $f) -Destination $staging }
Copy-Item -LiteralPath (Join-Path $root 'Module') -Destination $staging -Recurse

$zip = Join-Path $dist "LaptopDiagnose-$version.zip"
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip
Remove-Item -LiteralPath $staging -Recurse -Force

$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText("$zip.sha256", "$hash  LaptopDiagnose-$version.zip`n")

# Update-Kanal: nur das aktuelle Paket und das Manifest im Ordner »update«
$channel = Join-Path $root 'update'
if (-not (Test-Path -LiteralPath $channel)) { $null = New-Item -ItemType Directory -Path $channel -Force }
Get-ChildItem -LiteralPath $channel -Filter 'LaptopDiagnose-*.zip' | Remove-Item -Force
Copy-Item -LiteralPath $zip -Destination $channel
$manifest = [ordered]@{
    version         = $version
    datei           = "LaptopDiagnose-$version.zip"
    sha256          = $hash
    notizen         = $Notizen
    veroeffentlicht = (Get-Date).ToString('yyyy-MM-dd')
}
[IO.File]::WriteAllText((Join-Path $channel 'update.json'), ($manifest | ConvertTo-Json), (New-Object System.Text.UTF8Encoding $false))

$unsigned = @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' | Where-Object { $_.FullName -notmatch '\\(dist|Entwicklung)\\' -and (Get-AuthenticodeSignature $_.FullName).Status -ne 'Valid' })
Write-Host ''
Write-Host "Release-Paket erstellt:" -ForegroundColor Cyan
Write-Host "  $zip"
Write-Host "  $zip.sha256  ($hash)"
if ($unsigned) { Write-Host "Hinweis: $($unsigned.Count) Skript(e) sind nicht signiert. Für Updates mit Signaturprüfung -Signieren verwenden." -ForegroundColor Yellow }
Write-Host ''
Write-Host 'Nächste Schritte:' -ForegroundColor Cyan
Write-Host "  1. Den Ordner LaptopDiagnose\update (update.json + LaptopDiagnose-$version.zip) committen."
Write-Host '  2. Die Änderungen in den Hauptzweig »main« übernehmen (Push bzw. Pull Request zusammenführen).'
Write-Host '  3. Installierte Programme finden das Update unter »Einstellungen › Programm-Updates«.'
Write-Host '  (Alternativ weiterhin möglich: GitHub-Release mit Tag laptopdiagnose-v<Version> und ZIP + .sha256 als Anhang.)'
