#Requires -Version 5.1
<#
.SYNOPSIS
    Signiert alle PowerShell-Dateien von PC Repair Pro mit einem Code-Signing-Zertifikat und prüft das Ergebnis.

.DESCRIPTION
    Signierte Skripte werden von Virenscannern deutlich seltener beanstandet, zeigen den Herausgeber an
    und ermöglichen die Signaturprüfung beim Programm-Update.

    Unterstützte Zertifikate:
      - Gekauftes Zertifikat auf USB-Token oder im Zertifikatspeicher (seit 2023 der Normalfall):
        Token-Treiber installieren, Token einstecken, dann mit -Thumbprint signieren. Der Token fragt nach der PIN.
      - Cloud-Signatur (z. B. Azure Artifact Signing / Trusted Signing): mit -SignTool, -Dlib und -DlibMetadata.
      - PFX-Datei (z. B. ältere oder selbst ausgestellte Zertifikate): mit -PfxPath.
      - Ohne Angabe: erstes gültiges Code-Signing-Zertifikat aus dem Zertifikatspeicher.

    Nach dem Signieren wird jede Datei geprüft (gültig, unverändert, überall dasselbe Zertifikat, Zeitstempel).
    Anleitung: Entwicklung\Code-Signatur.md

.EXAMPLE
    .\Sign-LaptopDiagnose.ps1 -Thumbprint 0123ABCD...
    .\Sign-LaptopDiagnose.ps1 -PfxPath C:\Zertifikate\EderTom.pfx
    .\Sign-LaptopDiagnose.ps1 -SignTool -Dlib C:\Signing\Azure.CodeSigning.Dlib.dll -DlibMetadata C:\Signing\metadata.json
    .\Sign-LaptopDiagnose.ps1 -NurPruefen

.NOTES
    Copyright 2026 by Eder Tom
#>
[CmdletBinding()]
param(
    [string]$Thumbprint,
    [string]$PfxPath,
    [switch]$SignTool,
    [string]$SignToolPath,
    [string]$Dlib,
    [string]$DlibMetadata,
    [string[]]$TimestampServer = @('http://timestamp.digicert.com', 'http://timestamp.sectigo.com', 'http://timestamp.globalsign.com/tsa/r6advanced1'),
    [switch]$NurPruefen,
    [string]$Ordner = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'

function Get-SigningCertificate {
    if ($PfxPath) {
        $pfxPassword = Read-Host 'Passwort der PFX-Datei' -AsSecureString
        return New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($PfxPath, $pfxPassword)
    }
    $stores = 'Cert:\CurrentUser\My', 'Cert:\LocalMachine\My'
    foreach ($s in $stores) {
        $certs = @(Get-ChildItem -Path $s -CodeSigningCert -ErrorAction SilentlyContinue | Where-Object { $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date) })
        if ($Thumbprint) { $certs = @($certs | Where-Object { $_.Thumbprint -eq $Thumbprint.Replace(' ', '').ToUpperInvariant() }) }
        if ($certs) { return ($certs | Sort-Object NotAfter -Descending | Select-Object -First 1) }
    }
    throw 'Kein gültiges Code-Signing-Zertifikat mit privatem Schlüssel gefunden. Bei einem USB-Token: Token einstecken und dessen Treiber/Client installieren.'
}

function Test-PublicTrust {
    <# Vertraut Windows der Zertifikatskette (gekauftes Zertifikat) oder ist es selbst ausgestellt? #>
    param($Cert)
    $chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
    $chain.ChainPolicy.RevocationMode = 'NoCheck'
    return $chain.Build($Cert)
}

function Find-SignTool {
    if ($SignToolPath) { return $SignToolPath }
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $kits = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    $found = Get-ChildItem -LiteralPath $kits -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '\\x64\\' } | Sort-Object FullName -Descending | Select-Object -First 1
    if ($found) { return $found.FullName }
    throw 'signtool.exe nicht gefunden. Windows SDK (»Signing Tools for Desktop Apps«) installieren oder -SignToolPath angeben.'
}

$files = @(Get-ChildItem -LiteralPath $Ordner -Recurse -File -Include '*.ps1' | Where-Object { $_.FullName -notmatch '\\dist\\' })

if (-not $NurPruefen) {
    if ($SignTool) {
        $tool = Find-SignTool
        Write-Host "Signiere mit $tool" -ForegroundColor Cyan
        foreach ($f in $files) {
            $stArgs = @('sign', '/v', '/fd', 'SHA256', '/tr', $TimestampServer[0], '/td', 'SHA256')
            if ($Dlib) { $stArgs += @('/dlib', $Dlib, '/dmdf', $DlibMetadata) }
            elseif ($Thumbprint) { $stArgs += @('/sha1', $Thumbprint.Replace(' ', '')) }
            else { $stArgs += '/a' }
            $stArgs += $f.FullName
            $out = & $tool @stArgs 2>&1
            if ($LASTEXITCODE -ne 0) { $out | Write-Host; throw "Signieren fehlgeschlagen: $($f.Name)" }
            Write-Host ('  signiert    {0}' -f $f.FullName.Substring($Ordner.Length + 1)) -ForegroundColor Green
        }
    } else {
        $cert = Get-SigningCertificate
        $trusted = Test-PublicTrust $cert
        Write-Host "Zertifikat: $($cert.Subject)  (gültig bis $($cert.NotAfter.ToString('dd.MM.yyyy')), $($cert.Thumbprint))" -ForegroundColor Cyan
        Write-Host $(if ($trusted) { '  Öffentlich vertrauenswürdig (gekauftes Zertifikat).' } else { '  Selbst ausgestellt bzw. nicht vertrauenswürdig – Virenscanner und SmartScreen erkennen es nicht als Herausgeber an.' }) -ForegroundColor $(if ($trusted) { 'Green' } else { 'Yellow' })
        foreach ($f in $files) {
            $r = $null
            foreach ($ts in $TimestampServer) {
                try { $r = Set-AuthenticodeSignature -FilePath $f.FullName -Certificate $cert -TimestampServer $ts -HashAlgorithm SHA256; if ($r.Status -eq 'Valid' -or $r.TimeStamperCertificate) { break } } catch { $r = $null }
            }
            if (-not $r) { throw "Signieren fehlgeschlagen: $($f.Name)" }
            $color = if ($r.Status -eq 'Valid') { 'Green' } else { 'Yellow' }
            Write-Host ('  {0,-12} {1}' -f $r.Status, $f.FullName.Substring($Ordner.Length + 1)) -ForegroundColor $color
        }
    }
}

# Prüfung: alle Dateien signiert, unverändert, mit demselben Zertifikat und mit Zeitstempel
Write-Host 'Prüfe Signaturen …' -ForegroundColor Cyan
$problems = @(); $thumbs = @{}
foreach ($f in $files) {
    $sig = Get-AuthenticodeSignature -FilePath $f.FullName
    $rel = $f.FullName.Substring($Ordner.Length + 1)
    if (-not $sig.SignerCertificate) { $problems += "nicht signiert: $rel"; continue }
    if ("$($sig.Status)" -eq 'HashMismatch') { $problems += "nach dem Signieren verändert: $rel"; continue }
    $thumbs[$sig.SignerCertificate.Thumbprint] = $sig.SignerCertificate.Subject
    if (-not $sig.TimeStamperCertificate) { $problems += "ohne Zeitstempel (Signatur läuft mit dem Zertifikat ab): $rel" }
}
if ($thumbs.Count -gt 1) { $problems += "verschiedene Zertifikate: $(($thumbs.GetEnumerator() | ForEach-Object { "$($_.Value) ($($_.Key))" }) -join '; ')" }
if ($problems) {
    $problems | ForEach-Object { Write-Host "  ✖ $_" -ForegroundColor Red }
    throw "$($problems.Count) Problem(e) bei den Signaturen."
}
Write-Host "  ✔ $($files.Count) Dateien gültig signiert$(if ($thumbs.Count) { " von $(@($thumbs.Values)[0])" })." -ForegroundColor Green
Write-Host 'Hinweis: Nach jeder Änderung an einer Datei muss sie neu signiert werden.' -ForegroundColor Cyan
