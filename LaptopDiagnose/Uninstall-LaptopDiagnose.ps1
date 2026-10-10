#Requires -Version 5.1
<#
.SYNOPSIS
    Entfernt PC Repair Pro (Programmdateien, Verknüpfungen, geplante Wartung).
    Berichte und Verlauf (Standard: Dokumente\LaptopDiagnose) bleiben auf Wunsch erhalten.

.NOTES
    Copyright 2026 by Eder Tom
#>
[CmdletBinding()]
param([switch]$Still, [switch]$BerichteLoeschen)

Add-Type -AssemblyName PresentationFramework
$installDir = $PSScriptRoot
$uninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\EderTom.LaptopDiagnose'
$appData = Join-Path $env:LOCALAPPDATA 'LaptopDiagnose'
$reports = Join-Path (Join-Path $env:USERPROFILE 'Documents') 'LaptopDiagnose'
try {
    $cfg = Join-Path $appData 'Berichtordner.json'
    if (Test-Path -LiteralPath $cfg) { $j = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8 | ConvertFrom-Json; if ($j.Ordner) { $reports = [string]$j.Ordner } }
} catch { }

if (-not $Still) {
    $r = [System.Windows.MessageBox]::Show("PC Repair Pro jetzt deinstallieren?`n`nOrdner: $installDir", 'Deinstallation', 'YesNo', 'Question')
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

foreach ($folder in [Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop')) {
    foreach ($name in 'PC Repair Pro.lnk', 'Laptop-Diagnose.lnk') { Remove-Item -LiteralPath (Join-Path $folder $name) -Force -ErrorAction SilentlyContinue }
}
Remove-Item -Path $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
if ($BerichteLoeschen) {
    Remove-Item -LiteralPath $reports -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $appData -Recurse -Force -ErrorAction SilentlyContinue
}

# Programmordner löschen (PowerShell hält das laufende Skript nicht gesperrt)
Set-Location -Path $env:TEMP
if ($installDir -like (Join-Path $env:LOCALAPPDATA 'Programs\*')) {
    Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue
}

$msg = 'PC Repair Pro wurde deinstalliert.'
if (-not $BerichteLoeschen -and (Test-Path -LiteralPath $reports)) { $msg += "`n`nBerichte und Verlauf bleiben erhalten:`n$reports" }
if ($notes) { $msg += "`n`n" + ($notes -join "`n") }
if (-not $Still) { $null = [System.Windows.MessageBox]::Show($msg, 'Deinstallation', 'OK', 'Information') } else { Write-Host $msg }
