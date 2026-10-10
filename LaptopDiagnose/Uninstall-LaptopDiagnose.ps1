#Requires -Version 5.1
<#
.SYNOPSIS
    Entfernt Laptop-Diagnose & Reparatur (Programmdateien, Verknüpfungen, geplante Wartung).
    Berichte und Verlauf im Ordner Dokumente\LaptopDiagnose bleiben auf Wunsch erhalten.

.NOTES
    Copyright 2026 by Eder Tom
#>
[CmdletBinding()]
param([switch]$Still, [switch]$BerichteLoeschen)

Add-Type -AssemblyName PresentationFramework
$installDir = $PSScriptRoot
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\EderTom.LaptopDiagnose'
$reports = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'LaptopDiagnose'

if (-not $Still) {
    $r = [System.Windows.MessageBox]::Show("Laptop-Diagnose & Reparatur jetzt deinstallieren?`n`nOrdner: $installDir", 'Deinstallation', 'YesNo', 'Question')
    if ("$r" -ne 'Yes') { return }
    if (Test-Path -LiteralPath $reports) {
        $r = [System.Windows.MessageBox]::Show("Sollen auch alle Berichte, der Verlauf und das Änderungsprotokoll gelöscht werden?`n`n$reports`n`n»Nein« behält diese Daten.", 'Deinstallation', 'YesNo', 'Question')
        $BerichteLoeschen = "$r" -eq 'Yes'
    }
}

$notes = @()
# Geplante Wartung entfernen (benötigt ggf. Administratorrechte)
try {
    $task = Get-ScheduledTask -TaskPath '\EderTom\' -TaskName 'LaptopDiagnose Wartung' -ErrorAction SilentlyContinue
    if ($task) { Unregister-ScheduledTask -TaskPath '\EderTom\' -TaskName 'LaptopDiagnose Wartung' -Confirm:$false -ErrorAction Stop }
} catch { $notes += 'Die geplante Wartung konnte ohne Administratorrechte nicht entfernt werden (Aufgabenplanung › EderTom).' }

foreach ($lnk in (Join-Path ([Environment]::GetFolderPath('Programs')) 'Laptop-Diagnose.lnk'), (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Laptop-Diagnose.lnk')) {
    Remove-Item -LiteralPath $lnk -Force -ErrorAction SilentlyContinue
}
Remove-Item -Path $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
if ($BerichteLoeschen) { Remove-Item -LiteralPath $reports -Recurse -Force -ErrorAction SilentlyContinue }

# Programmordner löschen (PowerShell hält das laufende Skript nicht gesperrt)
Set-Location -Path $env:TEMP
if ($installDir -like (Join-Path $env:LOCALAPPDATA 'Programs\*')) {
    Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue
}

$msg = 'Laptop-Diagnose & Reparatur wurde deinstalliert.'
if (-not $BerichteLoeschen -and (Test-Path -LiteralPath $reports)) { $msg += "`n`nBerichte und Verlauf bleiben erhalten:`n$reports" }
if ($notes) { $msg += "`n`n" + ($notes -join "`n") }
if (-not $Still) { $null = [System.Windows.MessageBox]::Show($msg, 'Deinstallation', 'OK', 'Information') } else { Write-Host $msg }
