#Requires -Version 5.1
<#
.SYNOPSIS
    Installiert Laptop-Diagnose & Reparatur für den aktuellen Benutzer.

.DESCRIPTION
    Kopiert das Programm nach %LOCALAPPDATA%\Programs\LaptopDiagnose, legt einen Startmenü-Eintrag
    (und auf Wunsch eine Desktop-Verknüpfung) an und trägt das Programm unter »Installierte Apps« ein,
    damit es dort deinstalliert werden kann. Für die Installation sind keine Administratorrechte nötig.

.PARAMETER Desktop
    Desktop-Verknüpfung ohne Rückfrage anlegen.

.PARAMETER Still
    Keine Rückfragen (für Verteilung per Skript).

.NOTES
    Copyright 2026 by Eder Tom
#>
[CmdletBinding()]
param([switch]$Desktop, [switch]$Still)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$source = $PSScriptRoot
$target = Join-Path $env:LOCALAPPDATA 'Programs\LaptopDiagnose'
$version = if ((Get-Content -LiteralPath (Join-Path $source 'LaptopDiagnose.ps1') -Raw) -match "ToolVersion = '([\d\.]+)'") { $Matches[1] } else { '0.0.0' }
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\EderTom.LaptopDiagnose'

Write-Host ''
Write-Host "   Laptop-Diagnose & Reparatur $version – Installation" -ForegroundColor Cyan
Write-Host "   Zielordner: $target" -ForegroundColor Gray
Write-Host ''

if ($source.TrimEnd('\') -eq $target.TrimEnd('\')) { throw 'Das Programm ist bereits an diesem Ort installiert.' }

# Dateien kopieren
if (-not (Test-Path -LiteralPath $target)) { $null = New-Item -ItemType Directory -Path $target -Force }
$files = @('LaptopDiagnose.ps1', 'LaptopDiagnoseGUI.ps1', 'Start-LaptopDiagnose.cmd', 'Start-LaptopDiagnose-Konsole.cmd',
    'Uninstall-LaptopDiagnose.ps1', 'LaptopDiagnose.ico', 'README.md')
foreach ($f in $files) {
    $p = Join-Path $source $f
    if (-not (Test-Path -LiteralPath $p)) { continue }
    try { Copy-Item -LiteralPath $p -Destination $target -Force -ErrorAction Stop }
    catch {
        if ($f -like '*.ps1') { throw "$f konnte nicht kopiert werden. Bitte die Laptop-Diagnose schließen und die Installation erneut starten." }
        Write-Host "   ! $f ist in Benutzung und wurde nicht ersetzt." -ForegroundColor Yellow
    }
}
$moduleTarget = Join-Path $target 'Module'
if (Test-Path -LiteralPath $moduleTarget) { Remove-Item -LiteralPath $moduleTarget -Recurse -Force }
Copy-Item -LiteralPath (Join-Path $source 'Module') -Destination $target -Recurse -Force
Get-ChildItem -LiteralPath $target -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
Write-Host '   ✔ Programmdateien kopiert' -ForegroundColor Green

# Verknüpfungen
$shell = New-Object -ComObject WScript.Shell
$gui = Join-Path $target 'LaptopDiagnoseGUI.ps1'
$icon = Join-Path $target 'LaptopDiagnose.ico'
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
function New-AppShortcut {
    param([string]$Path)
    $lnk = $shell.CreateShortcut($Path)
    $lnk.TargetPath = $psExe
    $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Minimized -File `"$gui`""
    $lnk.WorkingDirectory = $target
    $lnk.IconLocation = "$icon,0"
    $lnk.Description = 'Laptop-Diagnose & Reparatur – Fehler finden, Leistung verbessern, Updates installieren'
    $lnk.WindowStyle = 7
    $lnk.Save()
}
$startMenu = Join-Path ([Environment]::GetFolderPath('Programs')) 'Laptop-Diagnose.lnk'
New-AppShortcut -Path $startMenu
Write-Host '   ✔ Startmenü-Eintrag »Laptop-Diagnose« angelegt' -ForegroundColor Green

$wantDesktop = $Desktop
if (-not $Desktop -and -not $Still) {
    $a = Read-Host '   Verknüpfung auf dem Desktop anlegen? [J/n]'
    $wantDesktop = [string]::IsNullOrWhiteSpace($a) -or $a -match '^\s*(j|ja|y)'
}
if ($wantDesktop) {
    New-AppShortcut -Path (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Laptop-Diagnose.lnk')
    Write-Host '   ✔ Desktop-Verknüpfung angelegt' -ForegroundColor Green
}

# Eintrag unter »Installierte Apps«
if (-not (Test-Path $uninstallKey)) { $null = New-Item -Path $uninstallKey -Force }
$size = [int](((Get-ChildItem -LiteralPath $target -Recurse -File | Measure-Object Length -Sum).Sum) / 1KB)
$values = @{
    DisplayName     = 'Laptop-Diagnose & Reparatur'
    DisplayVersion  = $version
    Publisher       = 'Eder Tom'
    DisplayIcon     = $icon
    InstallLocation = $target
    UninstallString = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $target 'Uninstall-LaptopDiagnose.ps1')`""
    InstallDate     = (Get-Date).ToString('yyyyMMdd')
}
foreach ($k in $values.Keys) { Set-ItemProperty -Path $uninstallKey -Name $k -Value $values[$k] }
Set-ItemProperty -Path $uninstallKey -Name NoModify -Value 1 -Type DWord
Set-ItemProperty -Path $uninstallKey -Name NoRepair -Value 1 -Type DWord
Set-ItemProperty -Path $uninstallKey -Name EstimatedSize -Value $size -Type DWord
Write-Host '   ✔ Unter »Einstellungen › Apps › Installierte Apps« eingetragen' -ForegroundColor Green

Write-Host ''
Write-Host '   Installation abgeschlossen. Start über das Startmenü: »Laptop-Diagnose«.' -ForegroundColor Cyan
if (-not $Still) {
    $a = Read-Host '   Jetzt starten? [J/n]'
    if ([string]::IsNullOrWhiteSpace($a) -or $a -match '^\s*(j|ja|y)') {
        Start-Process -FilePath $psExe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Minimized', '-File', "`"$gui`"")
    }
}
