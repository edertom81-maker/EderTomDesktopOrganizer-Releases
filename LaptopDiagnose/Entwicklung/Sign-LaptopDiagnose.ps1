#Requires -Version 5.1
<#
.SYNOPSIS
    Signiert alle PowerShell-Dateien von LaptopDiagnose mit einem Code-Signing-Zertifikat.

.DESCRIPTION
    Signierte Skripte werden von Virenscannern deutlich seltener beanstandet, zeigen den Herausgeber an
    und ermöglichen die Signaturprüfung beim Programm-Update. Das Zertifikat wird aus dem Zertifikatspeicher
    (Fingerabdruck oder erstes Code-Signing-Zertifikat) oder aus einer PFX-Datei geladen.

.EXAMPLE
    .\Sign-LaptopDiagnose.ps1
    .\Sign-LaptopDiagnose.ps1 -Thumbprint 0123ABCD...
    .\Sign-LaptopDiagnose.ps1 -PfxPath C:\Zertifikate\EderTom.pfx

.NOTES
    Copyright 2026 by Eder Tom
#>
[CmdletBinding()]
param(
    [string]$Thumbprint,
    [string]$PfxPath,
    [string]$TimestampServer = 'http://timestamp.digicert.com',
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
    throw 'Kein gültiges Code-Signing-Zertifikat mit privatem Schlüssel gefunden.'
}

$cert = Get-SigningCertificate
Write-Host "Zertifikat: $($cert.Subject)  (gültig bis $($cert.NotAfter.ToString('dd.MM.yyyy')), $($cert.Thumbprint))" -ForegroundColor Cyan

$files = Get-ChildItem -LiteralPath $Ordner -Recurse -File -Include '*.ps1' | Where-Object { $_.FullName -notmatch '\\dist\\' }
foreach ($f in $files) {
    $r = Set-AuthenticodeSignature -FilePath $f.FullName -Certificate $cert -TimestampServer $TimestampServer -HashAlgorithm SHA256
    $color = if ($r.Status -eq 'Valid') { 'Green' } else { 'Yellow' }
    Write-Host ('  {0,-12} {1}' -f $r.Status, $f.FullName.Substring($Ordner.Length + 1)) -ForegroundColor $color
}
Write-Host 'Fertig. Hinweis: Nach jeder Änderung an einer Datei muss sie neu signiert werden.' -ForegroundColor Cyan
