#Requires -Version 5.1
<#
.SYNOPSIS
    Laptop-Diagnose & Reparatur – findet Fehler, Speicherfresser und Leistungsbremsen, prüft den Akku
    und hält Software, Windows und Treiber aktuell.

.DESCRIPTION
    Alle Prüfungen sind rein lesend. Änderungen am System (Reparaturen, Updates, Bereinigungen)
    werden ausschließlich nach ausdrücklicher Bestätigung ausgeführt. Vor Reparaturen wird auf
    Wunsch ein Systemwiederherstellungspunkt angelegt. Jeder Lauf wird protokolliert und kann als
    HTML-Bericht gespeichert werden.

.PARAMETER Modus
    Menue (Standard), Komplett, Fehler, Sicherheit, Speicher, Leistung, Herunterfahren, Akku, Netzwerk, Software, Windows,
    Werkzeuge, Verlauf, Aenderungen, Wartung, Update

.PARAMETER NurPruefen
    Nur Diagnose und Bericht – es werden keine Reparaturen oder Updates angeboten.

.PARAMETER BerichtOrdner
    Zielordner für Berichte und Protokolle (Standard: Dokumente\LaptopDiagnose).

.PARAMETER Unbeaufsichtigt
    Für die geplante Wartung: Komplett-Diagnose ohne Rückfragen und ohne Änderungen, speichert Bericht und Verlauf
    und meldet kritische Probleme per Windows-Benachrichtigung.

.PARAMETER Pdf
    Bericht zusätzlich als PDF speichern (über Microsoft Edge).

.EXAMPLE
    .\LaptopDiagnose.ps1
    .\LaptopDiagnose.ps1 -Modus Komplett
    .\LaptopDiagnose.ps1 -Modus Komplett -NurPruefen
    .\LaptopDiagnose.ps1 -Modus Komplett -Unbeaufsichtigt

.NOTES
    Copyright 2026 by Eder Tom
#>
[CmdletBinding()]
param(
    [ValidateSet('Menue', 'Komplett', 'Fehler', 'Sicherheit', 'Speicher', 'Leistung', 'Herunterfahren', 'Akku', 'Netzwerk', 'Software', 'Windows',
        'Werkzeuge', 'Verlauf', 'Aenderungen', 'Wartung', 'Update')]
    [string]$Modus = 'Menue',
    [switch]$NurPruefen,
    [string]$BerichtOrdner = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'LaptopDiagnose'),
    [switch]$Unbeaufsichtigt,
    [switch]$Pdf
)

if ($Unbeaufsichtigt) { $NurPruefen = $true }

$Script:ToolVersion = '2.2.0'
$Script:InstallDir = $PSScriptRoot
$Script:ChangeCounter = 0
$Script:SoftwareUpdateCache = $null
$Script:WindowsUpdateFailed = $false
$Script:Findings = New-Object System.Collections.Generic.List[object]
$Script:ActionLog = New-Object System.Collections.Generic.List[object]
$Script:SystemInfo = $null
$Script:RebootNeeded = $false
$Script:SeverityOrder = @{ 'Kritisch' = 0; 'Warnung' = 1; 'Info' = 2; 'OK' = 3 }
$Script:Categories = [ordered]@{
    'Fehler'     = 'Fehler & Systemzustand'
    'Sicherheit' = 'Sicherheit'
    'Speicher'   = 'Speicherfresser'
    'Leistung'   = 'Leistungsbremsen'
    'Herunterfahren' = 'Herunterfahren & Neustart'
    'Akku'       = 'Akku'
    'Netzwerk'   = 'Netzwerk & WLAN'
    'Software'   = 'Software-Updates'
    'Windows'    = 'Windows- & Treiber-Updates'
    'Werkzeuge'  = 'Reparatur-Werkzeuge'
}

# Prozesse, die niemals zum Beenden angeboten werden
$Script:ProtectedProcesses = @(
    'Idle', 'System', 'Registry', 'smss', 'csrss', 'wininit', 'winlogon', 'services', 'lsass', 'lsaiso',
    'svchost', 'dwm', 'explorer', 'Memory Compression', 'MsMpEng', 'NisSrv', 'fontdrvhost', 'sihost',
    'audiodg', 'spoolsv', 'SecurityHealthService', 'ctfmon', 'conhost', 'powershell', 'pwsh',
    'WindowsTerminal', 'OpenConsole', 'MpDefenderCoreService', 'SearchIndexer', 'TrustedInstaller', 'wuauclt'
)

#region ---------- Hilfsfunktionen ----------

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Format-Bytes {
    param([double]$Bytes)
    if ($Bytes -lt 0) { $Bytes = 0 }
    $units = 'B', 'KB', 'MB', 'GB', 'TB'
    $i = 0
    while ($Bytes -ge 1024 -and $i -lt $units.Count - 1) { $Bytes /= 1024; $i++ }
    if ($i -eq 0) { return ('{0} {1}' -f [math]::Round($Bytes), $units[$i]) }
    return ('{0:N1} {1}' -f $Bytes, $units[$i])
}

function Write-Title {
    param([string]$Text)
    $line = '═' * 74
    Write-Host ''
    Write-Host "  $line" -ForegroundColor DarkCyan
    Write-Host "   $Text" -ForegroundColor Cyan
    Write-Host "  $line" -ForegroundColor DarkCyan
}

function Write-Step {
    param([string]$Text)
    Write-Host "   › $Text ..." -ForegroundColor DarkGray
}

function Get-SeverityColor {
    param([string]$Severity)
    switch ($Severity) {
        'Kritisch' { 'Red' }
        'Warnung'  { 'Yellow' }
        'Info'     { 'Cyan' }
        default    { 'Green' }
    }
}

function Write-Finding {
    param($Finding)
    $color = Get-SeverityColor $Finding.Severity
    $badge = ('[{0}]' -f $Finding.Severity).PadRight(11)
    Write-Host "   $badge" -ForegroundColor $color -NoNewline
    Write-Host " $($Finding.Title)"
    if ($Finding.Detail) { Write-Host "              $($Finding.Detail)" -ForegroundColor Gray }
    foreach ($item in ($Finding.Items | Select-Object -First 10)) {
        Write-Host "                • $item" -ForegroundColor DarkGray
    }
    foreach ($c in @($Finding.Chart)) {
        Write-Host ('                • {0,-34} {1,12}' -f $c.Label, $c.Text) -ForegroundColor DarkGray
    }
    if (@($Finding.Items).Count -gt 10) {
        Write-Host "                … und $(@($Finding.Items).Count - 10) weitere (siehe Bericht)" -ForegroundColor DarkGray
    }
    if ($Finding.FixLabel -and -not $Finding.Fixed) {
        Write-Host "              ↳ Behebbar: $($Finding.FixLabel)" -ForegroundColor DarkGreen
    }
}

function Read-YesNo {
    param([string]$Question, [bool]$Default = $true)
    $hint = if ($Default) { '[J/n]' } else { '[j/N]' }
    while ($true) {
        $answer = Read-Host "   $Question $hint"
        if ([string]::IsNullOrWhiteSpace($answer)) { return $Default }
        switch -Regex ($answer.Trim()) {
            '^(j|ja|y|yes)$' { return $true }
            '^(n|nein|no)$'  { return $false }
        }
    }
}

function Read-Selection {
    <# Liefert Indizes (0-basiert) aus einer Eingabe wie "1,3,5-7". #>
    param([string]$InputText, [int]$Count)
    $result = New-Object System.Collections.Generic.List[int]
    foreach ($part in ($InputText -split '[,;\s]+')) {
        if ($part -match '^(\d+)-(\d+)$') {
            $a = [int]$Matches[1]; $b = [int]$Matches[2]
            if ($a -gt $b) { $t = $a; $a = $b; $b = $t }
            for ($n = $a; $n -le $b; $n++) { if ($n -ge 1 -and $n -le $Count -and -not $result.Contains($n - 1)) { $result.Add($n - 1) } }
        } elseif ($part -match '^\d+$') {
            $n = [int]$part
            if ($n -ge 1 -and $n -le $Count -and -not $result.Contains($n - 1)) { $result.Add($n - 1) }
        }
    }
    return , $result.ToArray()
}

function Add-Finding {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][ValidateSet('Kritisch', 'Warnung', 'Info', 'OK')][string]$Severity,
        [Parameter(Mandatory)][string]$Title,
        [string]$Detail,
        [string[]]$Items,
        [string]$FixLabel,
        [scriptblock]$Fix,
        $FixData,
        [switch]$RequiresReboot,
        [string[]]$SelectLabels,
        [switch]$SelectAllByDefault,
        [object[]]$Chart,
        [switch]$Silent
    )
    $finding = [pscustomobject]@{
        Category       = $Category
        Severity       = $Severity
        Title          = $Title
        Detail         = $Detail
        Items          = @($Items | Where-Object { $_ })
        FixLabel       = $FixLabel
        Fix            = $Fix
        FixData        = $FixData
        RequiresReboot = [bool]$RequiresReboot
        SelectLabels   = $SelectLabels
        SelectAll      = [bool]$SelectAllByDefault
        Chart          = @($Chart | Where-Object { $_ })
        Selection      = $null
        Fixed          = $false
        FixResult      = $null
        Time           = Get-Date
    }
    $Script:Findings.Add($finding)
    if (-not $Silent) { Write-Finding $finding }
    return
}

function Clear-CategoryFindings {
    param([string]$Category)
    $keep = @($Script:Findings | Where-Object { $_.Category -ne $Category })
    $Script:Findings.Clear()
    foreach ($f in $keep) { $Script:Findings.Add($f) }
}

function Invoke-Check {
    <# Führt eine Einzelprüfung aus; Fehler in einer Prüfung brechen die Diagnose nicht ab. #>
    param([string]$Category, [string]$Name, [scriptblock]$Check)
    Write-Step $Name
    try { & $Check }
    catch {
        Add-Finding -Category $Category -Severity Info -Title "Prüfung »$Name« konnte nicht vollständig ausgeführt werden" -Detail $_.Exception.Message
    }
}

function Get-FolderSize {
    param([string]$Path, [int]$OlderThanHours = 0)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return [double]0 }
    $limit = (Get-Date).AddHours(-$OlderThanHours)
    $sum = [double]0
    Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $limit } |
        ForEach-Object { $sum += $_.Length }
    return $sum
}

function Remove-FolderContent {
    <# Löscht Dateien (optional nur ältere) und anschließend leere Unterordner. Gesperrte Dateien werden übersprungen. #>
    param([string]$Path, [int]$OlderThanHours = 0)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return [double]0 }
    $limit = (Get-Date).AddHours(-$OlderThanHours)
    $freed = [double]0
    Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $limit } |
        ForEach-Object {
            $len = $_.Length
            try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop; $freed += $len } catch { }
        }
    Get-ChildItem -LiteralPath $Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
        Sort-Object { $_.FullName.Length } -Descending |
        ForEach-Object {
            if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    return $freed
}

function Invoke-Native {
    <# Startet ein Konsolenprogramm sichtbar im aktuellen Fenster und liefert den Exitcode. #>
    param([string]$FilePath, [string]$Arguments)
    $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
    return $p.ExitCode
}

function Test-PendingReboot {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($k in $keys) { if (Test-Path $k) { return $true } }
    return $false
}

function Stop-ProcessGroup {
    param($Data)
    $procs = @(Get-Process -Name $Data.Name -ErrorAction SilentlyContinue | Where-Object { $_.Id -ne $PID })
    if (-not $procs) { return "»$($Data.Name)« läuft nicht mehr." }
    $procs | Stop-Process -Force -ErrorAction Stop
    return "$($procs.Count) Instanz(en) von »$($Data.Name)« beendet."
}

#endregion

# Erweiterungsmodule laden (Sicherheit, Netzwerk, Analyse, Werkzeuge, Verlauf, Änderungen, Wartung)
foreach ($moduleFile in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'Module') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object Name) {
    . $moduleFile.FullName
}

#region ---------- Systemübersicht ----------

function Get-SystemOverview {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $bios = Get-CimInstance Win32_BIOS
    $gpu = @(Get-CimInstance Win32_VideoController | ForEach-Object { $_.Name }) -join ', '
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $uptime = (Get-Date) - $os.LastBootUpTime
    $build = [int]$os.BuildNumber
    $displayVersion = if ($cv.DisplayVersion) { $cv.DisplayVersion } else { $cv.ReleaseId }
    $caption = $os.Caption -replace '^Microsoft\s+', ''
    if ($build -ge 22000) { $caption = $caption -replace 'Windows 10', 'Windows 11' }

    $disks = @()
    try {
        $disks = @(Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
                '{0} ({1}, {2})' -f $_.FriendlyName, $_.MediaType, (Format-Bytes $_.Size)
            })
    } catch { }

    $Script:SystemInfo = [ordered]@{
        'Computer'         = $env:COMPUTERNAME
        'Hersteller'       = $cs.Manufacturer
        'Modell'           = $cs.Model
        'Seriennummer'     = $bios.SerialNumber
        'Betriebssystem'   = "$caption $displayVersion (Build $build.$($cv.UBR))"
        'Prozessor'        = $cpu.Name.Trim()
        'Kerne / Threads'  = "$($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors)"
        'Arbeitsspeicher'  = Format-Bytes $cs.TotalPhysicalMemory
        'Grafik'           = $gpu
        'Datenträger'      = ($disks -join '; ')
        'BIOS/UEFI'        = '{0} ({1:dd.MM.yyyy})' -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate
        'Laufzeit seit Start' = '{0} Tage, {1} Std., {2} Min.' -f $uptime.Days, $uptime.Hours, $uptime.Minutes
        'Diagnose am'      = (Get-Date).ToString('dd.MM.yyyy HH:mm')
    }
    return $Script:SystemInfo
}

function Show-SystemOverview {
    Write-Title 'Systemübersicht'
    $info = Get-SystemOverview
    foreach ($k in $info.Keys) {
        Write-Host ('   {0,-22}' -f $k) -ForegroundColor DarkGray -NoNewline
        Write-Host $info[$k]
    }
}

#endregion

#region ---------- 1) Fehlersuche ----------

function Invoke-ErrorScan {
    $cat = 'Fehler'
    Clear-CategoryFindings $cat
    Write-Title 'Fehlersuche & Systemzustand'

    Invoke-Check $cat 'Windows-Version und Support-Status' {
        $os = Get-CimInstance Win32_OperatingSystem
        $build = [int]$os.BuildNumber
        $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).EditionID
        if ($build -lt 22000) {
            Add-Finding $cat Warnung 'Windows 10 erhält seit 14.10.2025 keine regulären Sicherheitsupdates mehr' `
                -Detail 'Empfehlung: Upgrade auf Windows 11 (sofern die Hardware es unterstützt) oder ESU-Programm nutzen.'
        } elseif ($build -lt 26100 -and $edition -notmatch 'Enterprise|Education') {
            Add-Finding $cat Warnung "Diese Windows-11-Version (Build $build) wird für $edition nicht mehr unterstützt" `
                -Detail 'Empfehlung: Funktionsupdate (24H2 oder neuer) über Windows Update installieren.'
        } else {
            Add-Finding $cat OK "Windows-Version wird unterstützt (Build $build)"
        }
    }

    Invoke-Check $cat 'Ereignisprotokolle der letzten 7 Tage' {
        $since = (Get-Date).AddDays(-7)
        $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; Level = 1, 2; StartTime = $since } -MaxEvents 5000 -ErrorAction SilentlyContinue)

        $power = @($events | Where-Object { $_.Id -eq 41 -and $_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' })
        if ($power) {
            Add-Finding $cat Warnung "$($power.Count) unerwartete(s) Herunterfahren / Absturz ohne sauberes Beenden" `
                -Detail 'Mögliche Ursachen: Akku leer, Überhitzung, Netzteil, Einfrieren des Systems.' `
                -Items ($power | Select-Object -First 5 | ForEach-Object { '{0:dd.MM.yyyy HH:mm}' -f $_.TimeCreated })
        }
        $whea = @($events | Where-Object { $_.ProviderName -eq 'Microsoft-Windows-WHEA-Logger' })
        if ($whea) {
            Add-Finding $cat Kritisch "$($whea.Count) Hardwarefehler (WHEA) gemeldet" `
                -Detail 'Hinweis auf Probleme mit CPU, RAM, PCIe-Geräten oder Überhitzung. Ggf. BIOS-Update und Speichertest durchführen.'
        }
        $diskErr = @($events | Where-Object { ($_.ProviderName -in 'disk', 'Disk' -and $_.Id -in 7, 11, 51, 153) -or ($_.ProviderName -eq 'Ntfs' -and $_.Id -in 55, 98) })
        if ($diskErr) {
            Add-Finding $cat Kritisch "$($diskErr.Count) Datenträger-/Dateisystemfehler protokolliert" `
                -Detail 'Wichtig: Daten jetzt sichern! Anschließend Dateisystemprüfung durchführen.' `
                -FixLabel 'Dateisystem des Systemlaufwerks prüfen und reparieren' `
                -Fix { param($d) Repair-SystemVolume } -RequiresReboot
        }

        $crashes = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; Id = 1000; StartTime = $since } -MaxEvents 500 -ErrorAction SilentlyContinue)
        Set-Metric 'Programmabstuerze' $crashes.Count
        if ($crashes) {
            $byApp = $crashes | Group-Object { $_.Properties[0].Value } | Sort-Object Count -Descending
            $sev = if ($crashes.Count -ge 10) { 'Warnung' } else { 'Info' }
            Add-Finding $cat $sev "$($crashes.Count) Programmabstürze in den letzten 7 Tagen" `
                -Detail 'Häufig abstürzende Programme ggf. aktualisieren (Bereich »Software-Updates«) oder neu installieren.' `
                -Items ($byApp | Select-Object -First 8 | ForEach-Object { '{0} – {1}×' -f $_.Name, $_.Count })
        }

        $errors = @($events | Where-Object { $_.Level -le 2 })
        Set-Metric 'Ereignisfehler' $errors.Count
        if ($errors.Count -gt 0) {
            $top = $errors | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 8
            $items = foreach ($g in $top) {
                $msg = (($g.Group[0].Message -split "`r?`n")[0])
                if ($msg -and $msg.Length -gt 90) { $msg = $msg.Substring(0, 90) + '…' }
                '{0}× {1} (ID {2}): {3}' -f $g.Count, $g.Group[0].ProviderName, $g.Group[0].Id, $msg
            }
            $sev = if ($errors.Count -gt 100) { 'Warnung' } else { 'Info' }
            Add-Finding $cat $sev "$($errors.Count) Fehlereinträge im Ereignisprotokoll (7 Tage)" -Detail 'Häufigste Quellen:' -Items $items
        } else {
            Add-Finding $cat OK 'Keine Fehler im Ereignisprotokoll der letzten 7 Tage'
        }
    }

    Invoke-Check $cat 'Bluescreens und Absturzursachen (30 Tage)' { Add-BugcheckFindings -Category $cat }
    Invoke-Check $cat 'Ergebnis des letzten Arbeitsspeicher-Tests' { Add-MemoryTestFinding -Category $cat }

    Invoke-Check $cat 'Geräte-Manager auf Problemgeräte' {
        $bad = @(Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 0 -and $_.ConfigManagerErrorCode -ne 22 })
        if ($bad) {
            $codes = @{ 1 = 'nicht korrekt konfiguriert'; 10 = 'kann nicht gestartet werden'; 28 = 'kein Treiber installiert'; 31 = 'Treiber kann nicht geladen werden'; 43 = 'Gerät hat Fehler gemeldet'; 45 = 'nicht angeschlossen' }
            $items = $bad | ForEach-Object {
                $txt = if ($codes.ContainsKey([int]$_.ConfigManagerErrorCode)) { $codes[[int]$_.ConfigManagerErrorCode] } else { 'Fehlercode ' + $_.ConfigManagerErrorCode }
                '{0} – {1}' -f $(if ($_.Name) { $_.Name } else { $_.DeviceID }), $txt
            }
            $relevant = @($bad | Where-Object { $_.ConfigManagerErrorCode -ne 45 })
            $sev = if ($relevant) { 'Warnung' } else { 'Info' }
            Add-Finding $cat $sev "$($bad.Count) Gerät(e) mit Problemen im Geräte-Manager" -Items $items `
                -FixLabel 'Hardware neu erkennen lassen (danach Bereich »Windows & Treiber« prüfen)' `
                -Fix { param($d) $null = & pnputil.exe /scan-devices 2>&1; 'Geräteerkennung neu durchgeführt.' }
        } else {
            Add-Finding $cat OK 'Alle Geräte funktionieren ordnungsgemäß'
        }
    }

    Invoke-Check $cat 'Automatisch startende Dienste' {
        $ignore = 'gupdate|edgeupdate|GoogleUpdater|MozillaMaintenance|sppsvc|RemoteRegistry|MapsBroker|WbioSrvc|TrustedInstaller|tiledatamodelsvc|ShellHWDetection|BITS|wuauserv|UsoSvc|WaaSMedicSvc|DoSvc|CDPSvc|clr_optimization|stisvc|SysMain|Intel.*Update|Dell.*Update|OneDrive.*Update'
        $services = @(Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" | Where-Object {
                $_.Name -notmatch "^($ignore)" -and
                $_.Name -notmatch '_[0-9a-f]{4,}$' -and
                -not (Test-Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($_.Name)\TriggerInfo") -and
                ($_.ExitCode -ne 0 -or -not $_.DelayedAutoStart)
            })
        if ($services) {
            Add-Finding $cat Warnung "$($services.Count) automatisch startende(r) Dienst(e) läuft nicht" `
                -Items ($services | ForEach-Object { '{0} ({1}) – Exitcode {2}' -f $_.DisplayName, $_.Name, $_.ExitCode }) `
                -FixLabel 'Gestoppte Dienste starten' -FixData @($services | ForEach-Object { $_.Name }) `
                -Fix {
                param($d)
                $ok = 0; $failed = @()
                foreach ($n in $d) { try { Start-Service -Name $n -ErrorAction Stop; $ok++ } catch { $failed += $n } }
                $msg = "$ok Dienst(e) gestartet."
                if ($failed) { $msg += ' Nicht startbar: ' + ($failed -join ', ') }
                $msg
            }
        } else {
            Add-Finding $cat OK 'Alle wichtigen automatischen Dienste laufen'
        }
    }

    Invoke-Check $cat 'Integrität des Windows-Systemabbilds (DISM)' {
        $health = Repair-WindowsImage -Online -CheckHealth -ErrorAction Stop
        if ($health.ImageHealthState -eq 'Healthy') {
            Add-Finding $cat OK 'Windows-Systemabbild ist intakt' -Detail 'Eine vollständige Prüfung mit SFC ist unter »Reparatur-Werkzeuge« möglich.'
        } else {
            Add-Finding $cat Kritisch "Windows-Systemabbild ist beschädigt ($($health.ImageHealthState))" `
                -Detail 'Beschädigte Systemdateien verursachen Abstürze und fehlerhafte Updates.' `
                -FixLabel 'Systemabbild (DISM) und Systemdateien (SFC) reparieren' -Fix { param($d) Repair-SystemFiles } -RequiresReboot
        }
    }

    Invoke-Check $cat 'Gesundheit der Datenträger (SMART)' {
        $disks = @(Get-PhysicalDisk -ErrorAction Stop)
        foreach ($disk in $disks) {
            $rel = $null
            try { $rel = $disk | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
            $info = @()
            if ($rel) {
                if ($null -ne $rel.Wear) { $info += "Verschleiß: $($rel.Wear) %" }
                if ($rel.Temperature) { $info += "Temperatur: $($rel.Temperature) °C" }
                if ($rel.PowerOnHours) { $info += "Betriebsstunden: $($rel.PowerOnHours)" }
                if ($rel.ReadErrorsUncorrected) { $info += "Nicht korrigierbare Lesefehler: $($rel.ReadErrorsUncorrected)" }
            }
            $name = '{0} ({1}, {2})' -f $disk.FriendlyName, $disk.MediaType, (Format-Bytes $disk.Size)
            if ($disk.HealthStatus -ne 'Healthy' -or ($rel -and $rel.ReadErrorsUncorrected -gt 0)) {
                Add-Finding $cat Kritisch "Datenträger meldet Probleme: $name" `
                    -Detail "Status: $($disk.HealthStatus) / $($disk.OperationalStatus). SOFORT Daten sichern und Austausch planen!" -Items $info
            } elseif ($rel -and $rel.Wear -ge 80) {
                Add-Finding $cat Warnung "SSD stark verschlissen ($($rel.Wear) %): $name" -Detail 'Austausch zeitnah einplanen, Backups prüfen.' -Items $info
            } elseif ($rel -and $rel.Temperature -ge 70) {
                Add-Finding $cat Warnung "Datenträger sehr warm ($($rel.Temperature) °C): $name" -Detail 'Kühlung / Lüftung prüfen.' -Items $info
            } else {
                Add-Finding $cat OK "Datenträger gesund: $name" -Items $info
            }
        }
    }

    Invoke-Check $cat 'Dateisystem des Systemlaufwerks' {
        $drive = $env:SystemDrive
        $dirty = (& fsutil.exe dirty query $drive 2>&1 | Out-String)
        if ($dirty -match '(?i)\bNOT\b|NICHT') {
            Add-Finding $cat OK "Dateisystem auf $drive ist nicht als fehlerhaft markiert"
        } elseif ($LASTEXITCODE -eq 0) {
            Add-Finding $cat Warnung "Dateisystem auf $drive ist als fehlerhaft (»dirty«) markiert" `
                -FixLabel 'Dateisystem prüfen und reparieren' -Fix { param($d) Repair-SystemVolume } -RequiresReboot
        }
    }

    Invoke-Check $cat 'Ausstehender Neustart' {
        if (Test-PendingReboot) {
            Add-Finding $cat Warnung 'Windows wartet auf einen Neustart' -Detail 'Updates oder Reparaturen werden erst nach einem Neustart abgeschlossen.'
            $Script:RebootNeeded = $true
        } else {
            Add-Finding $cat OK 'Kein Neustart ausstehend'
        }
    }

}

function Repair-SystemFiles {
    Write-Host '   DISM: Systemabbild wird repariert (dies kann einige Minuten dauern) ...' -ForegroundColor Gray
    $dism = Invoke-Native 'dism.exe' '/Online /Cleanup-Image /RestoreHealth'
    Write-Host '   SFC: Systemdateien werden geprüft ...' -ForegroundColor Gray
    $sfc = Invoke-Native 'sfc.exe' '/scannow'
    $Script:RebootNeeded = $true
    "DISM-Exitcode $dism, SFC-Exitcode $sfc. Details: %windir%\Logs\CBS\CBS.log"
}

function Repair-SystemVolume {
    $letter = $env:SystemDrive.TrimEnd(':')
    $scan = Repair-Volume -DriveLetter $letter -Scan -ErrorAction Stop
    if ("$scan" -eq 'NoErrorsFound') { return 'Online-Prüfung: keine Fehler gefunden.' }
    $null = Repair-Volume -DriveLetter $letter -SpotFix -ErrorAction SilentlyContinue
    $Script:RebootNeeded = $true
    "Prüfergebnis: $scan. Reparatur wurde eingeleitet und wird ggf. beim nächsten Neustart abgeschlossen."
}

#endregion

#region ---------- 2) Speicherfresser ----------

function Get-JunkLocations {
    $list = @(
        @{ Name = 'Temporäre Dateien (Benutzer)'; Path = $env:TEMP; Hours = 24 }
        @{ Name = 'Temporäre Dateien (Windows)'; Path = (Join-Path $env:windir 'Temp'); Hours = 24 }
        @{ Name = 'Windows-Update-Downloadcache'; Path = (Join-Path $env:windir 'SoftwareDistribution\Download'); Hours = 0; StopWU = $true }
        @{ Name = 'Übermittlungsoptimierung-Cache'; Path = (Join-Path $env:windir 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'); Hours = 0 }
        @{ Name = 'Absturzabbilder älter als 30 Tage'; Path = (Join-Path $env:windir 'Minidump'); Hours = 720 }
        @{ Name = 'Absturzabbilder (Programme)'; Path = (Join-Path $env:LOCALAPPDATA 'CrashDumps'); Hours = 0 }
        @{ Name = 'Windows-Fehlerberichte'; Path = (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'); Hours = 0 }
        @{ Name = 'Windows-Fehlerberichte (Warteschlange)'; Path = (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'); Hours = 0 }
        @{ Name = 'Miniaturansicht-Cache'; Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer'); Hours = 0; Filter = 'thumbcache_*.db' }
    )
    $memDump = Join-Path $env:windir 'MEMORY.DMP'
    if (Test-Path -LiteralPath $memDump) { $list += @{ Name = 'Großes Speicherabbild (MEMORY.DMP)'; File = $memDump } }
    return $list
}

function Measure-Junk {
    $result = @()
    foreach ($loc in Get-JunkLocations) {
        $size = [double]0
        if ($loc.File) {
            $size = (Get-Item -LiteralPath $loc.File -Force -ErrorAction SilentlyContinue).Length
        } elseif ($loc.Filter) {
            Get-ChildItem -LiteralPath $loc.Path -Filter $loc.Filter -Force -File -ErrorAction SilentlyContinue | ForEach-Object { $size += $_.Length }
        } else {
            $size = Get-FolderSize -Path $loc.Path -OlderThanHours $loc.Hours
        }
        if ($size -gt 0) { $result += [pscustomobject]@{ Location = $loc; Size = [double]$size } }
    }
    # Papierkorb aller Laufwerke
    $rb = [double]0
    Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | ForEach-Object {
        $rb += Get-FolderSize -Path (Join-Path $_.DeviceID '$Recycle.Bin')
    }
    if ($rb -gt 0) { $result += [pscustomobject]@{ Location = @{ Name = 'Papierkorb'; RecycleBin = $true }; Size = $rb } }
    return $result
}

function Clear-Junk {
    param($Entries)
    $freed = [double]0
    foreach ($e in $Entries) {
        $loc = $e.Location
        Write-Host "     – $($loc.Name)" -ForegroundColor DarkGray
        if ($loc.RecycleBin) {
            try { Clear-RecycleBin -Force -ErrorAction Stop; $freed += $e.Size } catch { }
        } elseif ($loc.File) {
            try { Remove-Item -LiteralPath $loc.File -Force -ErrorAction Stop; $freed += $e.Size } catch { }
        } elseif ($loc.Filter) {
            Get-ChildItem -LiteralPath $loc.Path -Filter $loc.Filter -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
                $len = $_.Length
                try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop; $freed += $len } catch { }
            }
        } elseif ($loc.StopWU) {
            Stop-Service -Name wuauserv, bits -Force -ErrorAction SilentlyContinue
            $freed += Remove-FolderContent -Path $loc.Path -OlderThanHours $loc.Hours
            Start-Service -Name bits, wuauserv -ErrorAction SilentlyContinue
        } else {
            $freed += Remove-FolderContent -Path $loc.Path -OlderThanHours $loc.Hours
        }
    }
    return "$(Format-Bytes $freed) freigegeben."
}

function Invoke-MemoryScan {
    $cat = 'Speicher'
    Clear-CategoryFindings $cat
    Write-Title 'Speicherfresser'

    Invoke-Check $cat 'Arbeitsspeicher-Auslastung' {
        $os = Get-CimInstance Win32_OperatingSystem
        $total = [double]$os.TotalVisibleMemorySize * 1KB
        $free = [double]$os.FreePhysicalMemory * 1KB
        $usedPct = [math]::Round((1 - $free / $total) * 100)
        $commitPct = [math]::Round((1 - [double]$os.FreeVirtualMemory / [double]$os.TotalVirtualMemorySize) * 100)
        $detail = "Belegt: $(Format-Bytes ($total - $free)) von $(Format-Bytes $total) ($usedPct %), Zusagelast: $commitPct %"
        Set-Metric 'RAMAuslastung' $usedPct
        if ($usedPct -ge 90) {
            Add-Finding $cat Kritisch "Arbeitsspeicher nahezu voll ($usedPct %)" -Detail $detail
        } elseif ($usedPct -ge 80) {
            Add-Finding $cat Warnung "Arbeitsspeicher stark ausgelastet ($usedPct %)" -Detail $detail
        } else {
            Add-Finding $cat OK "Arbeitsspeicher-Auslastung normal ($usedPct %)" -Detail $detail
        }
        if ($total -lt 7.5GB) {
            Add-Finding $cat Info "Nur $(Format-Bytes $total) Arbeitsspeicher verbaut" -Detail 'Für flüssiges Arbeiten mit Windows 11 werden mindestens 8–16 GB empfohlen (Aufrüstung prüfen).'
        }
    }

    Invoke-Check $cat 'Prozesse mit hohem Speicherverbrauch' {
        $totalRam = [double](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
        $groups = Get-Process | Group-Object ProcessName | ForEach-Object {
            [pscustomobject]@{
                Name    = $_.Name
                Count   = $_.Count
                Memory  = [double](($_.Group | Measure-Object WorkingSet64 -Sum).Sum)
                Private = [double](($_.Group | Measure-Object PrivateMemorySize64 -Sum).Sum)
                Title   = ($_.Group | Where-Object { $_.MainWindowTitle } | Select-Object -First 1).MainWindowTitle
            }
        } | Sort-Object Memory -Descending

        $top = $groups | Select-Object -First 10
        Add-Finding $cat Info 'Die 10 größten Speicherverbraucher' -Items ($top | ForEach-Object {
                '{0,-28} {1,10}  ({2} Prozess{3})' -f $_.Name, (Format-Bytes $_.Memory), $_.Count, $(if ($_.Count -gt 1) { 'e' } else { '' })
            })

        $threshold = [math]::Max(1.5GB, $totalRam * 0.2)
        foreach ($g in $groups | Where-Object { $_.Memory -ge $threshold -and $Script:ProtectedProcesses -notcontains $_.Name }) {
            $pct = [math]::Round($g.Memory / $totalRam * 100)
            Add-Finding $cat Warnung "»$($g.Name)« belegt $(Format-Bytes $g.Memory) ($pct % des RAM)" `
                -Detail 'Achtung: Beim Beenden gehen ungespeicherte Daten dieses Programms verloren.' `
                -FixLabel "»$($g.Name)« beenden ($($g.Count) Instanz/en)" -FixData @{ Name = $g.Name } `
                -Fix { param($d) Stop-ProcessGroup $d }
        }
    }

    Invoke-Check $cat 'Freier Speicherplatz auf den Laufwerken' {
        foreach ($v in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
            if (-not $v.Size) { continue }
            $pct = [math]::Round([double]$v.FreeSpace / [double]$v.Size * 100)
            $txt = "$($v.DeviceID) – $(Format-Bytes $v.FreeSpace) frei von $(Format-Bytes $v.Size) ($pct %)"
            if ($v.DeviceID -eq $env:SystemDrive) { Set-Metric 'FreierSpeicher' ([double]$v.FreeSpace / 1GB) }
            if ($pct -lt 5 -or $v.FreeSpace -lt 5GB) {
                Add-Finding $cat Kritisch "Laufwerk fast voll: $txt" -Detail 'Windows wird langsam und Updates schlagen fehl. Datenmüll entfernen und große Dateien auslagern.'
            } elseif ($pct -lt 15) {
                Add-Finding $cat Warnung "Wenig Speicherplatz: $txt"
            } else {
                Add-Finding $cat OK "Ausreichend Speicherplatz: $txt"
            }
        }
    }

    Invoke-Check $cat 'Datenmüll (Temp, Caches, Absturzabbilder, Papierkorb)' {
        $junk = @(Measure-Junk)
        $sum = [double](($junk | Measure-Object Size -Sum).Sum)
        Set-Metric 'Datenmuell' ($sum / 1GB)
        $items = $junk | Sort-Object Size -Descending | ForEach-Object { '{0,-40} {1,10}' -f $_.Location.Name, (Format-Bytes $_.Size) }
        if ($sum -ge 200MB) {
            $sev = if ($sum -ge 1GB) { 'Warnung' } else { 'Info' }
            Add-Finding $cat $sev "$(Format-Bytes $sum) Datenmüll gefunden" -Items $items `
                -FixLabel "Datenmüll entfernen (ca. $(Format-Bytes $sum))" -FixData $junk -Fix { param($d) Clear-Junk $d }
        } else {
            Add-Finding $cat OK "Kaum Datenmüll vorhanden ($(Format-Bytes $sum))"
        }
    }

    Invoke-Check $cat 'Reste alter Windows-Installationen und Updates' {
        $old = Join-Path $env:SystemDrive 'Windows.old'
        if (Test-Path -LiteralPath $old) {
            $size = Get-FolderSize -Path $old
            Add-Finding $cat Warnung "Alte Windows-Installation (Windows.old) belegt $(Format-Bytes $size)" `
                -Detail 'Nach dem Entfernen ist kein Zurücksetzen auf die vorherige Windows-Version mehr möglich.' `
                -FixLabel 'Windows.old und Update-Reste mit der Datenträgerbereinigung entfernen' `
                -Fix { param($d) Invoke-CleanMgr @('Previous Installations', 'Update Cleanup', 'Windows Upgrade Log Files', 'Temporary Setup Files') }
        }
    }

    Invoke-Check $cat 'Speicherbelegung analysieren (kann 1–2 Minuten dauern)' { Add-StorageBreakdownFindings -Category $cat }

    Invoke-Check $cat 'Große Dateien in den Benutzerordnern' {
        $folders = 'Downloads', 'Desktop', 'Documents', 'Videos', 'Pictures' | ForEach-Object { Join-Path $env:USERPROFILE $_ }
        $big = foreach ($f in $folders) {
            if (Test-Path -LiteralPath $f) {
                Get-ChildItem -LiteralPath $f -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Length -ge 1GB -and -not ($_.Attributes -band [IO.FileAttributes]::Offline) -and -not ([int]$_.Attributes -band 0x400000) }
            }
        }
        $big = @($big | Sort-Object Length -Descending | Select-Object -First 15)
        if ($big) {
            Add-Finding $cat Info "$($big.Count) große Datei(en) über 1 GB in den Benutzerordnern" `
                -Detail 'Nicht mehr benötigte Dateien manuell löschen oder auf externe Speicher auslagern.' `
                -Items ($big | ForEach-Object { '{0,10}  {1}' -f (Format-Bytes $_.Length), $_.FullName.Replace($env:USERPROFILE, '%USERPROFILE%') })
        }
        $dl = Join-Path $env:USERPROFILE 'Downloads'
        $dlSize = Get-FolderSize -Path $dl
        if ($dlSize -ge 5GB) {
            Add-Finding $cat Info "Downloads-Ordner belegt $(Format-Bytes $dlSize)" -Detail 'Alte Installationsdateien und Archive können meist gelöscht werden.'
        }
    }
}

function Invoke-CleanMgr {
    param([string[]]$Handlers)
    $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    foreach ($h in $Handlers) {
        if (Test-Path "$base\$h") { Set-ItemProperty -Path "$base\$h" -Name 'StateFlags0777' -Value 2 -Type DWord -ErrorAction SilentlyContinue }
    }
    Write-Host '   Datenträgerbereinigung läuft (Fenster kann im Hintergrund erscheinen) ...' -ForegroundColor Gray
    $before = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'").FreeSpace
    Start-Process -FilePath cleanmgr.exe -ArgumentList '/sagerun:777' -Wait
    foreach ($h in $Handlers) { Remove-ItemProperty -Path "$base\$h" -Name 'StateFlags0777' -ErrorAction SilentlyContinue }
    $after = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'").FreeSpace
    "Datenträgerbereinigung abgeschlossen, $(Format-Bytes ([double]$after - [double]$before)) freigegeben."
}

#endregion

#region ---------- 3) Leistungsbremsen ----------

function Get-AutostartEntries {
    $approvedBase = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $sources = @(
        @{ Root = 'HKCU:'; Key = 'Software\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKCU:\$approvedBase\Run"; Scope = 'Benutzer' }
        @{ Root = 'HKLM:'; Key = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$approvedBase\Run"; Scope = 'Alle Benutzer' }
        @{ Root = 'HKLM:'; Key = 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$approvedBase\Run32"; Scope = 'Alle Benutzer (32 Bit)' }
    )
    $entries = @()
    foreach ($s in $sources) {
        $path = "$($s.Root)\$($s.Key)"
        if (-not (Test-Path $path)) { continue }
        $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
        foreach ($p in $props.PSObject.Properties | Where-Object { $_.Name -notin 'PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider' }) {
            $entries += [pscustomobject]@{ Name = $p.Name; Command = "$($p.Value)"; Approved = $s.Approved; Scope = $s.Scope }
        }
    }
    $folders = @(
        @{ Path = [Environment]::GetFolderPath('Startup'); Approved = "HKCU:\$approvedBase\StartupFolder"; Scope = 'Autostart-Ordner (Benutzer)' }
        @{ Path = [Environment]::GetFolderPath('CommonStartup'); Approved = "HKLM:\$approvedBase\StartupFolder"; Scope = 'Autostart-Ordner (Alle)' }
    )
    foreach ($f in $folders) {
        if (-not $f.Path -or -not (Test-Path -LiteralPath $f.Path)) { continue }
        Get-ChildItem -LiteralPath $f.Path -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' } | ForEach-Object {
            $entries += [pscustomobject]@{ Name = $_.Name; Command = $_.FullName; Approved = $f.Approved; Scope = $f.Scope }
        }
    }
    foreach ($e in $entries) {
        $state = $null
        try { $state = (Get-ItemProperty -Path $e.Approved -Name $e.Name -ErrorAction Stop).($e.Name) } catch { }
        $disabled = ($state -is [byte[]] -and $state.Length -gt 0 -and ($state[0] -band 1) -eq 1)
        $e | Add-Member -NotePropertyName Enabled -NotePropertyValue (-not $disabled)
    }
    return $entries
}

function Disable-AutostartEntries {
    <# Deaktiviert Autostarts wie der Task-Manager (umkehrbar über Task-Manager › Autostart). #>
    param($Entries)
    Write-Host ''
    Write-Host '   Aktive Autostart-Einträge:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $Entries.Count; $i++) {
        Write-Host ('    {0,3}) {1}' -f ($i + 1), $Entries[$i].Name) -NoNewline
        Write-Host ("  [$($Entries[$i].Scope)]") -ForegroundColor DarkGray
    }
    Write-Host '   Hinweis: Virenschutz, Touchpad-, Audio- und Grafiktreiber-Tools sollten aktiv bleiben.' -ForegroundColor DarkYellow
    $sel = Read-Host '   Nummern der zu deaktivierenden Einträge (z. B. 1,3,5-7 – leer = keine)'
    $idx = Read-Selection $sel $Entries.Count
    if (-not $idx.Count) { return 'Keine Autostarts geändert.' }
    Set-AutostartDisabled @($idx | ForEach-Object { $Entries[$_] })
}

function Set-AutostartDisabled {
    param($Entries)
    $done = @()
    $undo = @()
    foreach ($e in $Entries) {
        if (-not (Test-Path $e.Approved)) { $null = New-Item -Path $e.Approved -Force }
        $prev = $null
        try { $prev = (Get-ItemProperty -Path $e.Approved -Name $e.Name -ErrorAction Stop).($e.Name) } catch { }
        $bytes = [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes((Get-Date).ToFileTime()))
        Set-ItemProperty -Path $e.Approved -Name $e.Name -Value $bytes -Type Binary
        $done += $e.Name
        $undo += @{ Approved = $e.Approved; Name = $e.Name; Previous = $(if ($prev -is [byte[]]) { [Convert]::ToBase64String($prev) }) }
    }
    if ($done) { Register-Change -Beschreibung "Autostart deaktiviert: $($done -join ', ')" -Typ 'Autostart' -Daten @{ Eintraege = $undo } }
    "Deaktiviert: $($done -join ', '). Rückgängig über »Änderungen« oder im Task-Manager › Autostart."
}

function Invoke-PerformanceScan {
    $cat = 'Leistung'
    Clear-CategoryFindings $cat
    Write-Title 'Leistungsbremsen'

    Invoke-Check $cat 'Prozessorauslastung (5 Sekunden Messung)' {
        $samples = @()
        $procSamples = @{}
        for ($i = 0; $i -lt 5; $i++) {
            $samples += [double](Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'").PercentProcessorTime
            Get-CimInstance Win32_PerfFormattedData_PerfProc_Process | Where-Object { $_.Name -notin '_Total', 'Idle' } | ForEach-Object {
                $n = $_.Name -replace '#\d+$', ''
                if (-not $procSamples.ContainsKey($n)) { $procSamples[$n] = 0.0 }
                $procSamples[$n] += [double]$_.PercentProcessorTime
            }
            Start-Sleep -Milliseconds 800
        }
        $cores = [Environment]::ProcessorCount
        $avg = [math]::Round(($samples | Measure-Object -Average).Average)
        Set-Metric 'CPULast' $avg
        $top = $procSamples.GetEnumerator() | ForEach-Object {
            [pscustomobject]@{ Name = $_.Key; Cpu = [math]::Round($_.Value / 5 / $cores, 1) }
        } | Sort-Object Cpu -Descending | Select-Object -First 5
        $items = $top | Where-Object { $_.Cpu -gt 0 } | ForEach-Object { '{0,-30} {1,5} %' -f $_.Name, $_.Cpu }
        if ($avg -ge 80) {
            Add-Finding $cat Kritisch "Prozessor dauerhaft stark ausgelastet ($avg %)" -Items $items
        } elseif ($avg -ge 50) {
            Add-Finding $cat Warnung "Erhöhte Prozessorlast im Leerlauf ($avg %)" -Items $items
        } else {
            Add-Finding $cat OK "Prozessorauslastung normal ($avg %)" -Items $items
        }
        foreach ($p in $top | Where-Object { $_.Cpu -ge 25 -and $Script:ProtectedProcesses -notcontains $_.Name }) {
            Add-Finding $cat Warnung "»$($p.Name)« verursacht $($p.Cpu) % Prozessorlast" `
                -Detail 'Achtung: Beim Beenden gehen ungespeicherte Daten dieses Programms verloren.' `
                -FixLabel "»$($p.Name)« beenden" -FixData @{ Name = $p.Name } -Fix { param($d) Stop-ProcessGroup $d }
        }
    }

    Invoke-Check $cat 'Autostart-Programme' {
        $all = @(Get-AutostartEntries)
        $enabled = @($all | Where-Object { $_.Enabled })
        $items = $enabled | ForEach-Object { '{0}  [{1}]' -f $_.Name, $_.Scope }
        Set-Metric 'Autostarts' $enabled.Count
        if ($enabled.Count -gt 8) {
            Add-Finding $cat Warnung "$($enabled.Count) Programme starten automatisch mit Windows" `
                -Detail 'Viele Autostarts verlängern den Systemstart und belegen dauerhaft Arbeitsspeicher.' -Items $items `
                -FixLabel 'Autostart-Programme auswählen und deaktivieren' -FixData $enabled -Fix { param($d, $pre) if ($pre) { Set-AutostartDisabled $d } else { Disable-AutostartEntries $d } } `
                -SelectLabels @($enabled | ForEach-Object { '{0}  [{1}]' -f $_.Name, $_.Scope })
        } else {
            Add-Finding $cat OK "$($enabled.Count) Autostart-Programme (unkritisch)" -Items $items `
                -FixLabel $(if ($enabled.Count) { 'Autostart-Programme auswählen und deaktivieren' }) `
                -FixData $enabled -Fix $(if ($enabled.Count) { { param($d, $pre) if ($pre) { Set-AutostartDisabled $d } else { Disable-AutostartEntries $d } } }) `
                -SelectLabels @($enabled | ForEach-Object { '{0}  [{1}]' -f $_.Name, $_.Scope })
        }
    }

    Invoke-Check $cat 'Dauer des Systemstarts' {
        $ev = Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -FilterXPath '*[System[EventID=100]]' -MaxEvents 5 -ErrorAction Stop
        $times = @($ev | ForEach-Object {
                $xml = [xml]$_.ToXml()
                [double](($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' }).'#text') / 1000
            })
        if ($times) {
            $avg = [math]::Round(($times | Measure-Object -Average).Average)
            $trend = @(Get-MetricSeries -Name 'Startdauer') | Select-Object -First 1
            Set-Metric 'Startdauer' $avg
            $trendText = $null
            if ($trend -and $trend.Values.Count -ge 2) {
                $median = ($trend.Values | Sort-Object)[[math]::Floor($trend.Values.Count / 2)]
                if ($median -gt 0 -and $avg -ge $median * 1.25 -and ($avg - $median) -ge 10) {
                    $trendText = "Der Start dauert $([math]::Round($avg - $median)) Sekunden länger als üblich (bisher Ø $([math]::Round($median)) s) – evtl. durch neue Autostarts oder Updates."
                }
            }
            if ($avg -ge 90) {
                Add-Finding $cat Warnung "Langsamer Systemstart (Ø $avg Sekunden)" -Detail $(if ($trendText) { $trendText } else { 'Autostarts reduzieren und Datenträger prüfen.' })
            } elseif ($trendText) {
                Add-Finding $cat Warnung "Systemstart langsamer geworden (Ø $avg Sekunden)" -Detail $trendText
            } else {
                Add-Finding $cat OK "Systemstart in Ø $avg Sekunden"
            }
        }
        $slow = @(Get-WinEvent -LogName 'Microsoft-Windows-Diagnostics-Performance/Operational' -FilterXPath '*[System[EventID=101 or EventID=102 or EventID=103]]' -MaxEvents 50 -ErrorAction SilentlyContinue)
        if ($slow) {
            $names = $slow | ForEach-Object {
                $xml = [xml]$_.ToXml()
                ($xml.Event.EventData.Data | Where-Object { $_.Name -eq 'FriendlyName' }).'#text'
            } | Where-Object { $_ } | Group-Object | Sort-Object Count -Descending | Select-Object -First 6
            if ($names) {
                Add-Finding $cat Info 'Programme/Treiber, die den Start bremsen' -Items ($names | ForEach-Object { '{0} ({1}×)' -f $_.Name, $_.Count })
            }
        }
    }

    Invoke-Check $cat 'Energiesparplan und Prozessorleistung' {
        $active = (& powercfg.exe /getactivescheme | Out-String)
        $saver = 'a1841308-3541-4fab-bc81-f71556f20b4a'
        if ($active -match $saver) {
            Add-Finding $cat Warnung 'Energiesparplan »Energiesparmodus« drosselt die Leistung dauerhaft' `
                -FixLabel 'Energiesparplan »Ausbalanciert« aktivieren' -FixData $saver `
                -Fix {
                param($d)
                $null = & powercfg.exe /setactive 381b4222-f694-41f0-9685-ff5bb260df2e
                Register-Change -Beschreibung 'Energiesparplan »Ausbalanciert« aktiviert' -Typ 'Energieplan' -Daten @{ Previous = $d }
                'Energiesparplan »Ausbalanciert« aktiviert.'
            }
        } else {
            $name = if ($active -match '\((.+)\)') { $Matches[1] } else { 'unbekannt' }
            Add-Finding $cat OK "Energiesparplan: $name"
        }
        $q = (& powercfg.exe /query SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 2>$null | Out-String)
        $hex = @([regex]::Matches($q, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
        if ($hex.Count -ge 2) {
            $ac = [Convert]::ToInt32($hex[-2], 16)
            if ($ac -lt 100) {
                Add-Finding $cat Warnung "Maximale Prozessorleistung im Netzbetrieb auf $ac % begrenzt" `
                    -FixLabel 'Maximale Prozessorleistung im Netzbetrieb auf 100 % setzen' -FixData $ac `
                    -Fix {
                    param($d)
                    $null = & powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100
                    $null = & powercfg.exe /setactive SCHEME_CURRENT
                    Register-Change -Beschreibung "Maximale Prozessorleistung von $d % auf 100 % gesetzt" -Typ 'Prozessorleistung' -Daten @{ Previous = $d }
                    'Prozessorleistung im Netzbetrieb auf 100 % gesetzt.'
                }
            }
        }
    }

    Invoke-Check $cat 'Laufzeit seit dem letzten Neustart' {
        $uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        if ($uptime.TotalDays -ge 7) {
            Add-Finding $cat Warnung "Laptop läuft seit $([math]::Floor($uptime.TotalDays)) Tagen ohne Neustart" `
                -Detail 'Durch »Schnellstart« wird beim Herunterfahren nicht neu gestartet. Ein echter Neustart gibt Ressourcen frei.'
        } else {
            Add-Finding $cat OK "Letzter Neustart vor $([math]::Round($uptime.TotalHours)) Stunden"
        }
    }

    Invoke-Check $cat 'Systemlaufwerk (SSD/HDD, TRIM)' {
        $letter = $env:SystemDrive.TrimEnd(':')
        $part = Get-Partition -DriveLetter $letter -ErrorAction Stop
        $pd = Get-PhysicalDisk | Where-Object { $_.DeviceId -eq "$($part.DiskNumber)" } | Select-Object -First 1
        if ($pd.MediaType -eq 'HDD') {
            Add-Finding $cat Warnung 'Windows läuft auf einer herkömmlichen Festplatte (HDD)' `
                -Detail 'Der Umstieg auf eine SSD ist die wirksamste Beschleunigung für ältere Laptops.' `
                -FixLabel 'Festplatte defragmentieren (kann lange dauern)' `
                -Fix { param($d) Optimize-Volume -DriveLetter $env:SystemDrive.TrimEnd(':') -Defrag -ErrorAction Stop; 'Defragmentierung abgeschlossen.' }
        } else {
            $trim = (& fsutil.exe behavior query DisableDeleteNotify 2>$null | Out-String)
            if ($trim -match 'NTFS[^\r\n]*=\s*1') {
                Add-Finding $cat Warnung 'TRIM ist für SSDs deaktiviert' -Detail 'Ohne TRIM werden SSDs mit der Zeit langsamer.' `
                    -FixLabel 'TRIM aktivieren und SSD optimieren' `
                    -Fix {
                    param($d)
                    $null = & fsutil.exe behavior set DisableDeleteNotify 0
                    Register-Change -Beschreibung 'TRIM für SSDs aktiviert' -Typ 'TRIM' -Daten @{ Previous = 1 }
                    Optimize-Volume -DriveLetter $env:SystemDrive.TrimEnd(':') -ReTrim -ErrorAction SilentlyContinue
                    'TRIM aktiviert und ausgeführt.'
                }
            } else {
                Add-Finding $cat OK "Systemlaufwerk ist eine SSD, TRIM aktiv ($($pd.FriendlyName))"
            }
        }
    }

    Invoke-Check $cat 'Auslagerungsdatei' {
        $pf = @(Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue)
        if (-not $pf) {
            Add-Finding $cat Warnung 'Keine Auslagerungsdatei vorhanden' -Detail 'Kann zu Abstürzen bei hoher Speicherlast führen.' `
                -FixLabel 'Auslagerungsdatei automatisch von Windows verwalten lassen' `
                -Fix {
                param($d)
                Get-CimInstance Win32_ComputerSystem | Set-CimInstance -Property @{ AutomaticManagedPagefile = $true } -ErrorAction Stop
                Register-Change -Beschreibung 'Automatische Auslagerungsdatei aktiviert' -Typ 'Auslagerungsdatei' -Daten @{ Previous = $false }
                'Automatische Auslagerungsdatei aktiviert.'
            } -RequiresReboot
        } else {
            $p = $pf[0]
            if ($p.CurrentUsage -gt 0 -and $p.AllocatedBaseSize -gt 0 -and ($p.CurrentUsage / $p.AllocatedBaseSize) -gt 0.8) {
                Add-Finding $cat Warnung "Auslagerungsdatei zu $([math]::Round($p.CurrentUsage / $p.AllocatedBaseSize * 100)) % belegt" -Detail 'Deutet auf zu wenig Arbeitsspeicher hin.'
            } else {
                Add-Finding $cat OK "Auslagerungsdatei vorhanden ($($p.AllocatedBaseSize) MB)"
            }
        }
    }

    Invoke-Check $cat 'Temperatur' {
        $zones = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop)
        $temps = @($zones | ForEach-Object { [math]::Round($_.CurrentTemperature / 10 - 273.15) } | Where-Object { $_ -gt 0 -and $_ -lt 130 })
        if ($temps) {
            $max = ($temps | Measure-Object -Maximum).Maximum
            Set-Metric 'Temperatur' $max
            if ($max -ge 90) {
                Add-Finding $cat Kritisch "Sehr hohe Temperatur gemessen ($max °C)" -Detail 'Überhitzung drosselt die Leistung. Lüfter reinigen, Laptop auf harter Unterlage betreiben.'
            } elseif ($max -ge 80) {
                Add-Finding $cat Warnung "Erhöhte Temperatur ($max °C)" -Detail 'Lüftungsschlitze prüfen und reinigen.'
            } else {
                Add-Finding $cat OK "Temperatur unauffällig ($max °C)"
            }
        }
    }

    Invoke-Check $cat 'Vorinstallierte Zusatzsoftware' { Add-BloatwareFindings -Category $cat }
}

#endregion

#region ---------- 4) Akku ----------

function Invoke-BatteryScan {
    $cat = 'Akku'
    Clear-CategoryFindings $cat
    Write-Title 'Akku-Diagnose'

    $battery = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    if (-not $battery) {
        Add-Finding $cat Info 'Kein Akku gefunden (Desktop-PC oder Akku nicht erkannt)'
        return
    }

    Invoke-Check $cat 'Akkuzustand und Verschleiß' {
        $xmlPath = Join-Path $env:TEMP "battery_$PID.xml"
        $null = & powercfg.exe /batteryreport /xml /output $xmlPath 2>&1
        $parsed = $false
        if (Test-Path -LiteralPath $xmlPath) {
            $rep = New-Object System.Xml.XmlDocument
            $rep.Load($xmlPath)
            Remove-Item -LiteralPath $xmlPath -Force -ErrorAction SilentlyContinue
            foreach ($b in @($rep.BatteryReport.Batteries.Battery)) {
                $design = [double]$b.DesignCapacity
                $full = [double]$b.FullChargeCapacity
                if ($design -le 0) { continue }
                $parsed = $true
                $health = [math]::Round($full / $design * 100)
                $items = @(
                    "Hersteller/Modell: $($b.Manufacturer) $($b.Id)"
                    "Technologie: $($b.Chemistry)"
                    ('Auslegungskapazität: {0:N0} mWh' -f $design)
                    ('Aktuelle volle Kapazität: {0:N0} mWh' -f $full)
                )
                if ($b.CycleCount) { $items += "Ladezyklen: $($b.CycleCount)"; Set-Metric 'AkkuZyklen' ([double]$b.CycleCount) }
                if (-not $Script:Metrics.Contains('AkkuGesundheit')) { Set-Metric 'AkkuGesundheit' $health }
                $title = "Akku-Gesundheit: $health % der ursprünglichen Kapazität"
                if ($health -lt 60) {
                    Add-Finding $cat Kritisch $title -Detail 'Der Akku ist stark gealtert. Ein Austausch wird empfohlen.' -Items $items
                } elseif ($health -lt 80) {
                    Add-Finding $cat Warnung $title -Detail 'Spürbar verringerte Laufzeit. Austausch mittelfristig einplanen.' -Items $items
                } else {
                    Add-Finding $cat OK $title -Items $items
                }
            }
            if ($parsed) { Add-BatteryHistoryFindings -Category $cat -Report $rep }
        }
        if (-not $parsed) {
            $static = Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue | Select-Object -First 1
            $fullCap = Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($static -and $fullCap -and $static.DesignedCapacity -gt 0) {
                $health = [math]::Round($fullCap.FullChargedCapacity / $static.DesignedCapacity * 100)
                Set-Metric 'AkkuGesundheit' $health
                $sev = if ($health -lt 60) { 'Kritisch' } elseif ($health -lt 80) { 'Warnung' } else { 'OK' }
                Add-Finding $cat $sev "Akku-Gesundheit: $health % der ursprünglichen Kapazität"
            } else {
                Add-Finding $cat Info 'Akkukapazität konnte nicht ausgelesen werden'
            }
        }
    }

    Invoke-Check $cat 'Aktueller Ladezustand' {
        $statusText = @{ 1 = 'Entlädt'; 2 = 'Am Netz'; 3 = 'Voll geladen'; 4 = 'Niedrig'; 5 = 'Kritisch'; 6 = 'Lädt'; 7 = 'Lädt (hoch)'; 8 = 'Lädt (niedrig)'; 9 = 'Lädt (kritisch)'; 11 = 'Teilweise geladen' }
        foreach ($b in $battery) {
            $st = if ($statusText.ContainsKey([int]$b.BatteryStatus)) { $statusText[[int]$b.BatteryStatus] } else { "Status $($b.BatteryStatus)" }
            $detail = "Ladestand: $($b.EstimatedChargeRemaining) % – $st"
            if ($b.BatteryStatus -eq 1 -and $b.EstimatedRunTime -and $b.EstimatedRunTime -lt 71582788) {
                $detail += " – geschätzte Restlaufzeit: $([math]::Floor($b.EstimatedRunTime / 60)) Std. $($b.EstimatedRunTime % 60) Min."
            }
            $sev = if ($b.BatteryStatus -in 4, 5, 9) { 'Warnung' } else { 'Info' }
            Add-Finding $cat $sev 'Ladezustand' -Detail $detail
        }
    }

    Invoke-Check $cat 'Standby-Art und Akkuverbrauch nach Apps' { Add-StandbyFindings -Category $cat }

    Invoke-Check $cat 'Was den Energiesparmodus verhindert' {
        $req = (& powercfg.exe /requests 2>$null | Out-String)
        $lines = @($req -split "`r?`n" | Where-Object { $_ -match '^\[(PROCESS|PROZESS|SERVICE|DIENST|DRIVER|TREIBER)\]' })
        if ($lines) {
            Add-Finding $cat Info "$($lines.Count) Programm(e)/Treiber verhindern derzeit Energiesparen oder Standby" -Items ($lines | ForEach-Object { $_.Trim() })
        }
    }

    Invoke-Check $cat 'Detaillierten Akkubericht erstellen' {
        if (-not (Test-Path -LiteralPath $BerichtOrdner)) { $null = New-Item -ItemType Directory -Path $BerichtOrdner -Force }
        $html = Join-Path $BerichtOrdner ('Akkubericht_{0:yyyyMMdd_HHmm}.html' -f (Get-Date))
        $null = & powercfg.exe /batteryreport /output $html 2>&1
        if (Test-Path -LiteralPath $html) {
            Add-Finding $cat Info 'Ausführlicher Windows-Akkubericht gespeichert' -Detail $html
        }
    }
}

#endregion

#region ---------- 5) Software-Updates (WinGet) ----------

function ConvertFrom-WingetTable {
    <# Liest die Tabellenausgabe von »winget upgrade« sprachunabhängig anhand der Spaltenpositionen. #>
    param([string[]]$Lines)
    $clean = @($Lines | ForEach-Object { (("$_" -split "`r") | Select-Object -Last 1) })
    $sep = -1
    for ($i = 1; $i -lt $clean.Count; $i++) { if ($clean[$i] -match '^\s*-{10,}\s*$') { $sep = $i; break } }
    if ($sep -lt 1) { return @() }
    $header = $clean[$sep - 1]
    $starts = @([regex]::Matches($header, '(?<=^|\s)\S') | ForEach-Object { $_.Index })
    if ($starts.Count -lt 4) { return @() }
    $result = @()
    for ($i = $sep + 1; $i -lt $clean.Count; $i++) {
        $l = $clean[$i]
        if ([string]::IsNullOrWhiteSpace($l) -or $l.Length -le $starts[3]) { break }
        $get = {
            param($n)
            $s = $starts[$n]
            $e = if ($n + 1 -lt $starts.Count) { [math]::Min($starts[$n + 1], $l.Length) } else { $l.Length }
            if ($s -ge $l.Length) { return '' }
            $l.Substring($s, $e - $s).Trim()
        }
        $id = & $get 1
        if (-not $id -or $id -match '\s') { break }
        $result += [pscustomobject]@{
            Name      = (& $get 0)
            Id        = $id
            Version   = (& $get 2)
            Available = (& $get 3)
            Source    = $(if ($starts.Count -ge 5) { & $get 4 } else { '' })
        }
    }
    return $result
}

function Get-SoftwareUpdates {
    if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
        try {
            Import-Module Microsoft.WinGet.Client -ErrorAction Stop
            return @(Get-WinGetPackage -ErrorAction Stop | Where-Object { $_.IsUpdateAvailable } | ForEach-Object {
                    [pscustomobject]@{ Name = $_.Name; Id = $_.Id; Version = $_.InstalledVersion; Available = @($_.AvailableVersions)[0]; Source = $_.Source }
                })
        } catch { }
    }
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'WinGet ist nicht installiert (App-Installer aus dem Microsoft Store installieren).' }
    $prev = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        $out = & winget.exe upgrade --accept-source-agreements 2>&1 | ForEach-Object { "$_" }
    } finally { [Console]::OutputEncoding = $prev }
    return @(ConvertFrom-WingetTable $out)
}

function Install-SoftwareUpdates {
    param($Packages)
    $ok = 0; $failed = @()
    $useModule = [bool](Get-Command Update-WinGetPackage -ErrorAction SilentlyContinue)
    foreach ($p in $Packages) {
        Write-Host "   ⇣ $($p.Name) $($p.Version) → $($p.Available)" -ForegroundColor Gray
        try {
            if ($useModule) {
                $r = Update-WinGetPackage -Id $p.Id -MatchOption Equals -Mode Silent -ErrorAction Stop
                if ("$($r.Status)" -eq 'Ok') { $ok++ } else { $failed += "$($p.Name) ($($r.Status))" }
            } else {
                $code = Invoke-Native 'winget.exe' "upgrade --id `"$($p.Id)`" --exact --silent --accept-package-agreements --accept-source-agreements"
                if ($code -eq 0) { $ok++ } else { $failed += ('{0} (0x{1:X8})' -f $p.Name, $code) }
            }
        } catch { $failed += "$($p.Name) ($($_.Exception.Message))" }
    }
    $msg = "$ok von $(@($Packages).Count) Programm(en) aktualisiert."
    if ($failed) { $msg += ' Fehlgeschlagen: ' + ($failed -join '; ') }
    Register-Change -Beschreibung "Programm-Updates installiert: $((@($Packages) | ForEach-Object { $_.Name }) -join ', ')" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis $msg
    return $msg
}

function Invoke-SoftwareScan {
    param([switch]$Interactive)
    $cat = 'Software'
    Clear-CategoryFindings $cat
    Write-Title 'Software-Updates (WinGet)'
    Write-Step 'Suche nach verfügbaren Programm-Updates'
    try {
        $updates = @(Get-SoftwareUpdates)
        $Script:SoftwareUpdateCache = $updates
    } catch {
        Add-Finding $cat Warnung 'Software-Updates konnten nicht geprüft werden' -Detail $_.Exception.Message
        return
    }
    Set-Metric 'SoftwareUpdates' $updates.Count
    if (-not $updates) {
        Add-Finding $cat OK 'Alle über WinGet verwalteten Programme sind aktuell'
        return
    }
    $items = $updates | ForEach-Object { '{0}  {1} → {2}' -f $_.Name, $_.Version, $_.Available }
    Add-Finding $cat Warnung "$($updates.Count) Programm-Update(s) verfügbar" -Items $items `
        -FixLabel "Alle $($updates.Count) Programm-Updates installieren" -FixData $updates -Fix { param($d) Install-SoftwareUpdates $d } -Silent:($Interactive -and -not $NurPruefen) `
        -SelectLabels $items -SelectAllByDefault

    if ($Interactive -and -not $NurPruefen) {
        Write-Host ''
        for ($i = 0; $i -lt $updates.Count; $i++) {
            Write-Host ('    {0,3}) {1}' -f ($i + 1), $updates[$i].Name) -NoNewline
            Write-Host ("  $($updates[$i].Version) → $($updates[$i].Available)") -ForegroundColor DarkGray
        }
        $sel = Read-Host '   Installieren: [A] alle, Nummern (z. B. 1,3,5-7) oder leer = keine'
        $chosen = if ($sel -match '^\s*(a|alle)\s*$') { $updates } else { @((Read-Selection $sel $updates.Count) | ForEach-Object { $updates[$_] }) }
        if ($chosen) {
            $res = Install-SoftwareUpdates $chosen
            Write-Host "   $res" -ForegroundColor Green
            Add-ActionLog 'Software-Updates installieren' $res $true
            foreach ($f in $Script:Findings | Where-Object { $_.Category -eq $cat -and $_.Fix }) { $f.Fixed = $true; $f.FixResult = $res }
        }
    }
}

#endregion

#region ---------- 6) Windows- und Treiber-Updates ----------

function Search-WindowsUpdates {
    param([ValidateSet('Software', 'Driver')][string]$Type)
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'LaptopDiagnose'
    $searcher = $session.CreateUpdateSearcher()
    $result = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='$Type'")
    $list = @()
    for ($i = 0; $i -lt $result.Updates.Count; $i++) { $list += $result.Updates.Item($i) }
    return $list
}

function Install-WindowsUpdates {
    param($Updates)
    $session = New-Object -ComObject Microsoft.Update.Session
    $session.ClientApplicationID = 'LaptopDiagnose'
    $coll = New-Object -ComObject Microsoft.Update.UpdateColl
    foreach ($u in $Updates) {
        if (-not $u.EulaAccepted) { $u.AcceptEula() }
        $null = $coll.Add($u)
    }
    Write-Host "   Lade $($coll.Count) Update(s) herunter ..." -ForegroundColor Gray
    $dl = $session.CreateUpdateDownloader()
    $dl.Updates = $coll
    $null = $dl.Download()
    Write-Host '   Installiere ...' -ForegroundColor Gray
    $inst = $session.CreateUpdateInstaller()
    $inst.Updates = $coll
    $r = $inst.Install()
    $ok = 0; $failed = @()
    for ($i = 0; $i -lt $coll.Count; $i++) {
        $code = $r.GetUpdateResult($i).ResultCode
        if ($code -in 2, 3) { $ok++ } else { $failed += $coll.Item($i).Title }
    }
    if ($r.RebootRequired) { $Script:RebootNeeded = $true }
    $msg = "$ok von $($coll.Count) Update(s) installiert."
    if ($failed) { $msg += ' Fehlgeschlagen: ' + ($failed -join '; ') }
    if ($r.RebootRequired) { $msg += ' Neustart erforderlich.' }
    Register-Change -Beschreibung "Windows-/Treiber-Updates installiert ($($coll.Count))" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis $msg
    return $msg
}

function Get-VendorDriverTool {
    $man = (Get-CimInstance Win32_ComputerSystem).Manufacturer
    $dcu = @("$env:ProgramFiles\Dell\CommandUpdate\dcu-cli.exe", "${env:ProgramFiles(x86)}\Dell\CommandUpdate\dcu-cli.exe") | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    switch -Regex ($man) {
        'Dell' { return @{ Vendor = 'Dell'; Cli = $dcu; WingetId = 'Dell.CommandUpdate'; Tool = 'Dell Command | Update' } }
        'LENOVO' { return @{ Vendor = 'Lenovo'; WingetId = 'Lenovo.SystemUpdate'; Tool = 'Lenovo System Update / Lenovo Vantage' } }
        'HP|Hewlett' { return @{ Vendor = 'HP'; Tool = 'HP Support Assistant' } }
        'ASUS' { return @{ Vendor = 'ASUS'; Tool = 'MyASUS' } }
        'Acer' { return @{ Vendor = 'Acer'; Tool = 'Acer Care Center' } }
        'Microsoft' { return @{ Vendor = 'Microsoft'; Tool = 'Windows Update (Surface-Treiber kommen darüber)' } }
        default { return @{ Vendor = $man; Tool = $null } }
    }
}

function Invoke-WindowsUpdateScan {
    param([switch]$Interactive)
    $cat = 'Windows'
    Clear-CategoryFindings $cat
    Write-Title 'Windows- & Treiber-Updates'

    $quiet = $Interactive -and -not $NurPruefen
    $state = @{ Software = @(); Driver = @() }
    Invoke-Check $cat 'Suche nach Windows-Updates (kann einige Minuten dauern)' {
        try {
            $sw = @(Search-WindowsUpdates -Type Software)
        } catch {
            $Script:WindowsUpdateFailed = $true
            Add-Finding $cat Warnung 'Die Suche nach Windows-Updates ist fehlgeschlagen' -Detail $_.Exception.Message `
                -FixLabel 'Windows-Update-Komponenten zurücksetzen' -Fix { param($d) Repair-WindowsUpdateComponents }
            return
        }
        $state.Software = $sw
        Set-Metric 'WindowsUpdates' $sw.Count
        if ($sw) {
            $sec = @($sw | Where-Object { $_.MsrcSeverity -in 'Critical', 'Important' })
            $sev = if ($sec) { 'Kritisch' } else { 'Warnung' }
            Add-Finding $cat $sev "$($sw.Count) Windows-Update(s) verfügbar$(if ($sec) { " – davon $($sec.Count) sicherheitsrelevant" })" `
                -Items ($sw | ForEach-Object { '{0} ({1})' -f $_.Title, (Format-Bytes $_.MaxDownloadSize) }) `
                -SelectLabels @($sw | ForEach-Object { $_.Title }) -SelectAllByDefault `
                -FixLabel 'Alle Windows-Updates installieren' -FixData $sw -Fix { param($d) Install-WindowsUpdates $d } -Silent:$quiet
        } else {
            Add-Finding $cat OK 'Windows ist auf dem neuesten Stand'
        }
    }

    Invoke-Check $cat 'Suche nach Treiber-Updates über Windows Update' {
        if ($Script:WindowsUpdateFailed) { return }
        $drv = @(Search-WindowsUpdates -Type Driver)
        $state.Driver = $drv
        Set-Metric 'TreiberUpdates' $drv.Count
        if ($drv) {
            Add-Finding $cat Warnung "$($drv.Count) Treiber-Update(s) verfügbar" `
                -Items ($drv | ForEach-Object { '{0} – {1} ({2:dd.MM.yyyy})' -f $_.DriverManufacturer, $_.Title, $_.DriverVerDate }) `
                -SelectLabels @($drv | ForEach-Object { $_.Title }) -SelectAllByDefault `
                -FixLabel 'Alle Treiber-Updates installieren' -FixData $drv -Fix { param($d) Install-WindowsUpdates $d } -Silent:$quiet
        } else {
            Add-Finding $cat OK 'Keine Treiber-Updates über Windows Update ausstehend'
        }
    }

    Invoke-Check $cat 'Veraltete Treiber wichtiger Geräte' {
        $limit = (Get-Date).AddYears(-4)
        $classes = 'DISPLAY', 'NET', 'MEDIA', 'BLUETOOTH', 'HDC', 'SCSIADAPTER', 'CAMERA', 'IMAGE', 'BIOMETRIC', 'HIDCLASS'
        $old = @(Get-CimInstance Win32_PnPSignedDriver | Where-Object {
                $_.DriverDate -and $_.DriverDate -lt $limit -and $_.DeviceClass -in $classes -and $_.DriverProviderName -and $_.DriverProviderName -notmatch '^Microsoft'
            } | Sort-Object DriverDate | Select-Object -First 15)
        if ($old) {
            $tool = Get-VendorDriverTool
            $detail = 'Diese Treiber sind älter als 4 Jahre. Aktuelle Versionen gibt es beim Hersteller'
            if ($tool.Tool) { $detail += " (empfohlen: $($tool.Tool))" }
            Add-Finding $cat Info "$($old.Count) Gerätetreiber älter als 4 Jahre" -Detail "$detail." `
                -Items ($old | ForEach-Object { '{0} – {1} vom {2:dd.MM.yyyy}' -f $_.DeviceName, $_.DriverVersion, $_.DriverDate })
        } else {
            Add-Finding $cat OK 'Keine stark veralteten Treiber bei wichtigen Geräten'
        }
    }

    Invoke-Check $cat 'Treiber- und BIOS-Updates des Laptop-Herstellers' {
        $tool = Get-VendorDriverTool
        if ($tool.Cli) {
            Add-Finding $cat Info "$($tool.Tool) ist installiert – prüft auch BIOS, Firmware und Herstellertreiber" `
                -FixLabel "Hersteller-Updates mit $($tool.Tool) suchen und installieren" -FixData $tool.Cli `
                -Fix { param($d) $c = Invoke-Native $d '/applyUpdates -reboot=disable'; $Script:RebootNeeded = $true; "Dell Command | Update beendet (Exitcode $c)." }
        } elseif ($tool.WingetId -and (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
            Add-Finding $cat Info "Für $($tool.Vendor)-Laptops empfiehlt sich $($tool.Tool) für BIOS- und Firmware-Updates" `
                -FixLabel "$($tool.Tool) über WinGet installieren" -FixData $tool.WingetId `
                -Fix { param($d) $c = Invoke-Native 'winget.exe' "install --id $d --exact --silent --accept-package-agreements --accept-source-agreements"; "Installation beendet (Exitcode $c). Danach das Tool starten und Updates suchen." }
        } elseif ($tool.Tool) {
            Add-Finding $cat Info "BIOS- und Firmware-Updates für $($tool.Vendor): $($tool.Tool) verwenden"
        }
    }

    if ($Interactive -and -not $NurPruefen) {
        $all = @($state.Software) + @($state.Driver)
        if ($all.Count) {
            Write-Host ''
            for ($i = 0; $i -lt $all.Count; $i++) {
                $kind = if ($all[$i].Type -eq 2) { 'Treiber' } else { 'Windows' }
                Write-Host ('    {0,3}) [{1}] {2}' -f ($i + 1), $kind, $all[$i].Title)
            }
            $sel = Read-Host '   Installieren: [A] alle, Nummern (z. B. 1,3,5-7) oder leer = keine'
            $chosen = if ($sel -match '^\s*(a|alle)\s*$') { $all } else { @((Read-Selection $sel $all.Count) | ForEach-Object { $all[$_] }) }
            if ($chosen) {
                $res = Install-WindowsUpdates $chosen
                Write-Host "   $res" -ForegroundColor Green
                Add-ActionLog 'Windows-/Treiber-Updates installieren' $res $true
                foreach ($f in $Script:Findings | Where-Object { $_.Category -eq $cat -and $_.FixLabel -match 'Updates installieren$' }) { $f.Fixed = $true; $f.FixResult = $res }
            }
        }
        Invoke-Repairs -Category $cat
    }
}

#endregion

#region ---------- Reparatur ----------

function Add-ActionLog {
    param([string]$Action, [string]$Result, [bool]$Success)
    $Script:ActionLog.Add([pscustomobject]@{ Time = Get-Date; Action = $Action; Result = $Result; Success = $Success })
}

function New-RestorePoint {
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description 'LaptopDiagnose – vor Reparatur' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue
        Write-Host '   ✔ Wiederherstellungspunkt erstellt.' -ForegroundColor Green
        Add-ActionLog 'Wiederherstellungspunkt erstellen' 'Erstellt' $true
    } catch {
        Write-Host "   ! Wiederherstellungspunkt nicht möglich: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host '     (Windows erlaubt standardmäßig nur einen automatischen Punkt pro 24 Stunden.)' -ForegroundColor DarkGray
        Add-ActionLog 'Wiederherstellungspunkt erstellen' $_.Exception.Message $false
    }
}

function Invoke-FixList {
    <#
        Führt die Behebung der übergebenen Ergebnisse ohne Rückfragen aus (Auswahl erfolgt vorher).
        Hat ein Ergebnis eine Teilauswahl (Selection = Indizes in FixData), wird nur diese bearbeitet.
    #>
    param($Findings, [switch]$RestorePoint)
    if ($RestorePoint) { New-RestorePoint }
    foreach ($f in $Findings) {
        Write-Host ''
        Write-Host "   ▶ $($f.FixLabel)" -ForegroundColor White
        $data = $f.FixData
        $preselected = $false
        if ($null -ne $f.Selection -and $f.SelectLabels) {
            $all = @($f.FixData)
            $data = @(foreach ($i in $f.Selection) { if ($i -ge 0 -and $i -lt $all.Count) { $all[$i] } })
            $preselected = $true
            if (-not $data.Count) { Write-Host '     – übersprungen (nichts ausgewählt)' -ForegroundColor Gray; continue }
        }
        try {
            $before = $Script:ChangeCounter
            $res = & $f.Fix $data $preselected
            $res = (@($res) | Where-Object { $_ -is [string] }) -join ' '
            if (-not $res) { $res = 'Erledigt.' }
            if ($Script:ChangeCounter -eq $before) { Register-Change -Beschreibung $f.FixLabel -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis $res }
            $f.Fixed = $true
            $f.FixResult = $res
            if ($f.RequiresReboot) { $Script:RebootNeeded = $true }
            Write-Host "     ✔ $res" -ForegroundColor Green
            Add-ActionLog $f.FixLabel $res $true
        } catch {
            $f.FixResult = "Fehlgeschlagen: $($_.Exception.Message)"
            Write-Host "     ✖ $($f.FixResult)" -ForegroundColor Red
            Add-ActionLog $f.FixLabel $f.FixResult $false
        }
    }
}

function Invoke-Repairs {
    param([string]$Category)
    if ($NurPruefen) { return }
    $fixable = @($Script:Findings | Where-Object { $_.Fix -and -not $_.Fixed -and (-not $Category -or $_.Category -eq $Category) } |
            Sort-Object { $Script:SeverityOrder[$_.Severity] })
    if (-not $fixable) {
        Write-Host ''
        Write-Host '   Keine automatisch behebbaren Probleme vorhanden.' -ForegroundColor Green
        return
    }

    Write-Title 'Gefundene Probleme beheben'
    for ($i = 0; $i -lt $fixable.Count; $i++) {
        $f = $fixable[$i]
        Write-Host ('    {0,3}) ' -f ($i + 1)) -NoNewline
        Write-Host ('{0,-9}' -f $f.Severity) -ForegroundColor (Get-SeverityColor $f.Severity) -NoNewline
        Write-Host " $($f.FixLabel)" -NoNewline
        if ($f.RequiresReboot) { Write-Host '  (Neustart nötig)' -ForegroundColor DarkGray } else { Write-Host '' }
    }
    $recommended = @($fixable | Where-Object { $_.Severity -in 'Kritisch', 'Warnung' })
    Write-Host ''
    Write-Host "   [A] Alle empfohlenen ($($recommended.Count) – Kritisch & Warnung)   [Nummern] Auswahl, z. B. 1,3,5-7   [Enter] Nichts" -ForegroundColor Cyan
    $sel = Read-Host '   Ihre Auswahl'
    $chosen = if ($sel -match '^\s*(a|alle)\s*$') { $recommended } else { @((Read-Selection $sel $fixable.Count) | ForEach-Object { $fixable[$_] }) }
    if (-not $chosen) { Write-Host '   Es wurde nichts verändert.' -ForegroundColor Gray; return }

    $restore = Read-YesNo 'Vorher einen Systemwiederherstellungspunkt erstellen?' $true
    Invoke-FixList -Findings $chosen -RestorePoint:$restore

    if ($Script:RebootNeeded) {
        Write-Host ''
        Write-Host '   Einige Änderungen werden erst nach einem Neustart wirksam.' -ForegroundColor Yellow
        if (Read-YesNo 'Laptop jetzt neu starten? (Vorher alle Dateien speichern!)' $false) {
            Export-Report -Quiet
            Restart-Computer -Force
        }
    }
}

#endregion

#region ---------- Bericht ----------

function ConvertTo-SafeHtml { param([string]$Text) [System.Net.WebUtility]::HtmlEncode($Text) }

function Get-AppSettings {
    $path = Join-Path $BerichtOrdner 'Einstellungen.json'
    $defaults = [ordered]@{ Design = 'System'; Pdf = $false }
    if (Test-Path -LiteralPath $path) {
        try {
            $j = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
            foreach ($p in $j.PSObject.Properties) { $defaults[$p.Name] = $p.Value }
        } catch { }
    }
    return [pscustomobject]$defaults
}

function Convert-HtmlToPdf {
    <# Druckt eine HTML-Datei mit Microsoft Edge (bzw. Chrome) im Hintergrund als PDF. #>
    param([Parameter(Mandatory)][string]$HtmlPath)
    $browsers = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe"
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    )
    $exe = $browsers | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $exe) { throw 'Für den PDF-Export wird Microsoft Edge oder Google Chrome benötigt.' }
    $pdf = [IO.Path]::ChangeExtension($HtmlPath, '.pdf')
    $profileDir = Join-Path $env:TEMP ('LaptopDiagnosePdf_' + [guid]::NewGuid().ToString('N'))
    $browserArgs = @('--headless=new', '--disable-gpu', '--no-first-run', '--no-pdf-header-footer', "--user-data-dir=`"$profileDir`"", "--print-to-pdf=`"$pdf`"", "`"$(([Uri]$HtmlPath).AbsoluteUri)`"")
    try {
        $p = Start-Process -FilePath $exe -ArgumentList $browserArgs -WindowStyle Hidden -PassThru
        if (-not $p.WaitForExit(90000)) { try { $p.Kill() } catch { } }
    } finally {
        Remove-Item -LiteralPath $profileDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path -LiteralPath $pdf)) { throw 'Die PDF-Datei konnte nicht erstellt werden.' }
    return $pdf
}

function Export-Report {
    param([switch]$Quiet, [switch]$Open, [switch]$AsPdf)
    if (-not $Script:SystemInfo) { $null = Get-SystemOverview }
    if (-not (Test-Path -LiteralPath $BerichtOrdner)) { $null = New-Item -ItemType Directory -Path $BerichtOrdner -Force }
    $stamp = '{0:yyyyMMdd_HHmm}' -f (Get-Date)
    $htmlPath = Join-Path $BerichtOrdner "Diagnosebericht_$stamp.html"
    $jsonPath = Join-Path $BerichtOrdner "Diagnosebericht_$stamp.json"
    $e = { param($t) ConvertTo-SafeHtml $t }

    $openFindings = @($Script:Findings | Where-Object { -not $_.Fixed })
    $counts = @{}
    foreach ($s in 'Kritisch', 'Warnung', 'Info', 'OK') { $counts[$s] = @($openFindings | Where-Object { $_.Severity -eq $s }).Count }
    $score = (Get-HealthScore).Score

    $sb = New-Object System.Text.StringBuilder
    $null = $sb.Append(@"
<!DOCTYPE html>
<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Diagnosebericht $(& $e $Script:SystemInfo['Computer'])</title>
<style>
:root{--bg:#f5f7fa;--card:#fff;--text:#1d2533;--muted:#5d6b80;--line:#e3e8ef;--crit:#d92d20;--warn:#dc8a00;--info:#1570ef;--ok:#079455;--accent:#0b4f8a;--track:#e9eef5}
@media (prefers-color-scheme:dark){:root{--bg:#0f141b;--card:#18202b;--text:#e6ebf2;--muted:#94a3b8;--line:#2a3544;--accent:#5ba7ef;--track:#243041}}
@media print{:root{--bg:#fff;--card:#fff;--text:#1d2533;--muted:#5d6b80;--line:#d9dfe7;--accent:#0b4f8a;--track:#e9eef5}.card,.tile{break-inside:avoid}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 "Segoe UI",system-ui,sans-serif;-webkit-print-color-adjust:exact;print-color-adjust:exact}
.wrap{max-width:1100px;margin:0 auto;padding:24px 16px 60px}
header{display:flex;flex-wrap:wrap;gap:16px;align-items:center;justify-content:space-between;margin-bottom:20px}
h1{margin:0;font-size:26px}h2{font-size:19px;margin:32px 0 12px;color:var(--accent)}
.sub{color:var(--muted)}.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px 20px;margin-bottom:12px}
.score{font-size:42px;font-weight:700}.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px}
.tile{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px;text-align:center}.tile b{display:block;font-size:28px}
table.kv{width:100%;border-collapse:collapse}table.kv td{padding:6px 8px;border-bottom:1px solid var(--line);vertical-align:middle}table.kv td:first-child{color:var(--muted);width:240px}
.f{border-left:5px solid var(--line)}.f.Kritisch{border-left-color:var(--crit)}.f.Warnung{border-left-color:var(--warn)}.f.Info{border-left-color:var(--info)}.f.OK{border-left-color:var(--ok)}
.badge{display:inline-block;font-size:12px;font-weight:600;padding:2px 9px;border-radius:99px;color:#fff;margin-right:8px;vertical-align:middle}
.b-Kritisch{background:var(--crit)}.b-Warnung{background:var(--warn)}.b-Info{background:var(--info)}.b-OK{background:var(--ok)}
.f h3{display:inline;font-size:15px;margin:0}.f p{margin:6px 0 0;color:var(--muted)}.f ul{margin:8px 0 0;padding-left:20px;font-family:Consolas,monospace;font-size:13px;white-space:pre-wrap;word-break:break-word}
.bars{margin-top:10px}.bar{display:grid;grid-template-columns:minmax(120px,240px) 1fr 90px;gap:10px;align-items:center;font-size:13px;margin:4px 0}
.bar .bt{background:var(--track);border-radius:6px;height:12px;overflow:hidden}.bar .bt i{display:block;height:100%;background:var(--info);border-radius:6px}
.bar .bl{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.bar .bv{text-align:right;color:var(--muted);font-variant-numeric:tabular-nums}
.better{color:var(--ok)}.worse{color:var(--warn)}.same{color:var(--muted)}
.fix{margin-top:8px;font-size:13px}.fix.done{color:var(--ok)}.fix.open{color:var(--accent)}
footer{margin-top:40px;color:var(--muted);font-size:13px;text-align:center}
@media (max-width:600px){.bar{grid-template-columns:1fr 70px}.bar .bt{grid-column:1/3;grid-row:2}table.kv td:first-child{width:auto}}
</style></head><body><div class="wrap">
<header><div><h1>Laptop-Diagnosebericht</h1><div class="sub">$(& $e $Script:SystemInfo['Hersteller']) $(& $e $Script:SystemInfo['Modell']) · $(& $e $Script:SystemInfo['Diagnose am'])</div></div>
<div class="card" style="text-align:center;margin:0"><div class="sub">Gesundheitswert</div><div class="score" style="color:$(if ($score -ge 80) { 'var(--ok)' } elseif ($score -ge 50) { 'var(--warn)' } else { 'var(--crit)' })">$score</div></div></header>
<div class="tiles">
<div class="tile"><b style="color:var(--crit)">$($counts['Kritisch'])</b>Kritisch</div>
<div class="tile"><b style="color:var(--warn)">$($counts['Warnung'])</b>Warnungen</div>
<div class="tile"><b style="color:var(--info)">$($counts['Info'])</b>Hinweise</div>
<div class="tile"><b style="color:var(--ok)">$($counts['OK'])</b>In Ordnung</div>
</div>
<h2>Systemübersicht</h2><div class="card"><table class="kv">
"@)
    foreach ($k in $Script:SystemInfo.Keys) {
        $null = $sb.Append("<tr><td>$(& $e $k)</td><td>$(& $e "$($Script:SystemInfo[$k])")</td></tr>")
    }
    $null = $sb.Append('</table></div>')

    # Verlauf und Trends
    $series = @(Get-MetricSeries | Where-Object { $_.Values.Count -ge 2 })
    if ($series) {
        $null = $sb.Append('<h2>Verlauf &amp; Trends</h2><div class="card"><table class="kv">')
        foreach ($m in $series) {
            $cls = switch ($m.Trend) { 'besser' { 'better' } 'schlechter' { 'worse' } default { 'same' } }
            $color = switch ($m.Trend) { 'besser' { '#079455' } 'schlechter' { '#dc8a00' } default { '#1570ef' } }
            $svg = New-SparklineSvg -Values $m.Values -Color $color
            $null = $sb.Append("<tr><td>$(& $e $m.Label)</td><td><b>$(& $e $m.ValueText)</b></td><td>$svg</td><td class=""$cls"">$(& $e $m.TrendText)</td></tr>")
        }
        $null = $sb.Append('</table></div>')
    }

    foreach ($catKey in $Script:Categories.Keys) {
        $list = @($Script:Findings | Where-Object { $_.Category -eq $catKey } | Sort-Object { $Script:SeverityOrder[$_.Severity] })
        if (-not $list) { continue }
        $null = $sb.Append("<h2>$(& $e $Script:Categories[$catKey])</h2>")
        foreach ($f in $list) {
            $null = $sb.Append("<div class=""card f $($f.Severity)""><span class=""badge b-$($f.Severity)"">$($f.Severity)</span><h3>$(& $e $f.Title)</h3>")
            if ($f.Detail) { $null = $sb.Append("<p>$(& $e $f.Detail)</p>") }
            if ($f.Items) {
                $null = $sb.Append('<ul>')
                foreach ($it in $f.Items) { $null = $sb.Append("<li>$(& $e $it)</li>") }
                $null = $sb.Append('</ul>')
            }
            $chart = @($f.Chart)
            if ($chart) {
                $max = [double](($chart | Measure-Object Value -Maximum).Maximum)
                if ($max -le 0) { $max = 1 }
                $null = $sb.Append('<div class="bars">')
                foreach ($c in $chart) {
                    $w = [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:0.#}', [math]::Max(1, [double]$c.Value / $max * 100))
                    $null = $sb.Append("<div class=""bar""><span class=""bl"">$(& $e $c.Label)</span><span class=""bt""><i style=""width:$w%""></i></span><span class=""bv"">$(& $e $c.Text)</span></div>")
                }
                $null = $sb.Append('</div>')
            }
            if ($f.Fixed) {
                $null = $sb.Append("<div class=""fix done"">✔ Behoben: $(& $e $f.FixLabel) – $(& $e $f.FixResult)</div>")
            } elseif ($f.FixResult) {
                $null = $sb.Append("<div class=""fix"" style=""color:var(--crit)"">✖ $(& $e $f.FixLabel) – $(& $e $f.FixResult)</div>")
            } elseif ($f.FixLabel -and $f.Category -ne 'Werkzeuge') {
                $null = $sb.Append("<div class=""fix open"">↳ Behebbar mit LaptopDiagnose: $(& $e $f.FixLabel)</div>")
            }
            $null = $sb.Append('</div>')
        }
    }

    if ($Script:ActionLog.Count) {
        $null = $sb.Append('<h2>Durchgeführte Maßnahmen</h2><div class="card"><table class="kv">')
        foreach ($a in $Script:ActionLog) {
            $icon = if ($a.Success) { '✔' } else { '✖' }
            $null = $sb.Append("<tr><td>$('{0:HH:mm:ss}' -f $a.Time) $icon</td><td><b>$(& $e $a.Action)</b><br>$(& $e $a.Result)</td></tr>")
        }
        $null = $sb.Append('</table></div>')
    }
    $null = $sb.Append("<footer>Erstellt mit LaptopDiagnose $Script:ToolVersion · Copyright 2026 by Eder Tom</footer></div></body></html>")

    [IO.File]::WriteAllText($htmlPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))

    $export = [ordered]@{
        Tool            = "LaptopDiagnose $Script:ToolVersion"
        Erstellt        = (Get-Date).ToString('s')
        Gesundheitswert = $score
        System          = $Script:SystemInfo
        Metriken        = $Script:Metrics
        Findings        = @($Script:Findings | Select-Object Category, Severity, Title, Detail, Items, FixLabel, Fixed, FixResult, RequiresReboot, Time)
        Actions         = $Script:ActionLog.ToArray()
    }
    [IO.File]::WriteAllText($jsonPath, ($export | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))

    if ($AsPdf -or $Pdf -or (Get-AppSettings).Pdf) {
        try {
            $pdfPath = Convert-HtmlToPdf -HtmlPath $htmlPath
            if (-not $Quiet) { Write-Host "   PDF gespeichert: $pdfPath" -ForegroundColor Green }
        } catch {
            if (-not $Quiet) { Write-Host "   PDF nicht möglich: $($_.Exception.Message)" -ForegroundColor Yellow }
        }
    }
    if (-not $Quiet) {
        Write-Host ''
        Write-Host "   Bericht gespeichert: $htmlPath" -ForegroundColor Green
    }
    if ($Open) { Invoke-Item -LiteralPath $htmlPath }
    return $htmlPath
}

function Show-Summary {
    $counts = foreach ($s in 'Kritisch', 'Warnung', 'Info', 'OK') {
        [pscustomobject]@{ S = $s; N = @($Script:Findings | Where-Object { $_.Severity -eq $s }).Count }
    }
    Write-Title "Zusammenfassung – Gesundheitswert $((Get-HealthScore).Score)"
    Write-Host '   ' -NoNewline
    foreach ($c in $counts) {
        Write-Host (" {0}: {1} " -f $c.S, $c.N) -ForegroundColor (Get-SeverityColor $c.S) -NoNewline
        Write-Host '  ' -NoNewline
    }
    Write-Host ''
    $fixCount = @($Script:Findings | Where-Object { $_.Fix -and -not $_.Fixed -and $_.Severity -in 'Kritisch', 'Warnung' }).Count
    if ($fixCount) { Write-Host "   $fixCount Problem(e) können automatisch behoben werden." -ForegroundColor DarkGreen }
}

#endregion

#region ---------- Ablauf / Menü ----------

# Reihenfolge der Prüfungen der Komplett-Diagnose (Software vor Sicherheit, damit WinGet nur einmal läuft)
$Script:FullScanOrder = @('Invoke-ErrorScan', 'Invoke-MemoryScan', 'Invoke-PerformanceScan', 'Invoke-ShutdownScan', 'Invoke-BatteryScan', 'Invoke-NetworkScan',
    'Invoke-SoftwareScan', 'Invoke-SecurityScan', 'Invoke-WindowsUpdateScan')

function Invoke-FullDiagnosis {
    Show-SystemOverview
    foreach ($scan in $Script:FullScanOrder) { & $scan }
    $null = Save-History
    Show-Summary
    $path = Export-Report
    if (-not $NurPruefen) { Invoke-Repairs }
    if ($Script:ActionLog.Count) { $path = Export-Report }
    if (Read-YesNo 'Bericht jetzt im Browser öffnen?' $true) { Invoke-Item -LiteralPath $path }
}

function Invoke-UnattendedDiagnosis {
    <# Geplante Wartung: prüfen, speichern, bei Bedarf benachrichtigen – ohne Rückfragen und ohne Änderungen. #>
    $previous = @(Get-HistoryEntries) | Select-Object -Last 1
    try { $null = Get-SystemOverview }
    catch { $Script:SystemInfo = [ordered]@{ 'Computer' = $env:COMPUTERNAME; 'Diagnose am' = (Get-Date).ToString('dd.MM.yyyy HH:mm') } }
    foreach ($scan in $Script:FullScanOrder) { & $scan }
    $null = Save-History
    $path = Export-Report -Quiet
    $h = Get-HealthScore
    $crit = @($Script:Findings | Where-Object { $_.Severity -eq 'Kritisch' -and -not $_.Fixed })
    if ($crit) {
        $titles = ($crit | Select-Object -First 2 | ForEach-Object { $_.Title }) -join ' · '
        $null = Show-Notification -Title "Laptop-Diagnose: $($crit.Count) kritische(s) Problem(e)" -Text "$titles – Klicken, um den Bericht zu öffnen." -OpenPath $path
    } elseif ($previous -and $previous.Metriken.Warnungen -ne $null -and $h.Warnungen -ge [int]$previous.Metriken.Warnungen + 2) {
        $null = Show-Notification -Title 'Laptop-Diagnose: neue Warnungen' -Text "Gesundheitswert $($h.Score) – $($h.Warnungen) Warnungen (zuletzt $($previous.Metriken.Warnungen))." -OpenPath $path
    }
}

function Invoke-SingleModule {
    param([string]$Name)
    if (-not $Script:SystemInfo -and $Name -notin 'Verlauf', 'Aenderungen', 'Wartung', 'Update') { $null = Get-SystemOverview }
    switch ($Name) {
        'Fehler'      { Invoke-ErrorScan; Invoke-Repairs -Category 'Fehler' }
        'Sicherheit'  { Invoke-SecurityScan; Invoke-Repairs -Category 'Sicherheit' }
        'Speicher'    { Invoke-MemoryScan; Invoke-Repairs -Category 'Speicher' }
        'Leistung'    { Invoke-PerformanceScan; Invoke-Repairs -Category 'Leistung' }
        'Herunterfahren' { Invoke-ShutdownScan; Invoke-Repairs -Category 'Herunterfahren' }
        'Akku'        { Invoke-BatteryScan; Invoke-Repairs -Category 'Akku' }
        'Netzwerk'    { Invoke-NetworkScan; Invoke-Repairs -Category 'Netzwerk' }
        'Software'    { Invoke-SoftwareScan -Interactive }
        'Windows'     { Invoke-WindowsUpdateScan -Interactive }
        'Werkzeuge'   { Invoke-ToolsScan; Invoke-Repairs -Category 'Werkzeuge' }
        'Verlauf'     { Show-HistoryConsole }
        'Aenderungen' { Show-ChangeLogConsole }
        'Wartung'     { Show-MaintenanceConsole }
        'Update'      { Show-ToolUpdateConsole }
    }
}

function Invoke-FleetOverviewConsole {
    Write-Title 'Geräteübersicht'
    Write-Host '   Legen Sie die JSON-Berichte (Diagnosebericht_*.json) mehrerer Geräte in einen gemeinsamen Ordner,' -ForegroundColor Gray
    Write-Host '   z. B. auf einem USB-Stick oder in OneDrive. Unterordner werden mit durchsucht.' -ForegroundColor Gray
    $folder = Read-Host "   Ordner (leer = $BerichtOrdner)"
    if ([string]::IsNullOrWhiteSpace($folder)) { $folder = $BerichtOrdner }
    try {
        $out = Export-FleetOverview -Ordner $folder.Trim('"')
        Write-Host "   ✔ Geräteübersicht gespeichert: $out" -ForegroundColor Green
        Invoke-Item -LiteralPath $out
    } catch { Write-Host "   ✖ $($_.Exception.Message)" -ForegroundColor Red }
}

function Show-Menu {
    while ($true) {
        Clear-Host
        Write-Host ''
        Write-Host '   ╔════════════════════════════════════════════════════════════╗' -ForegroundColor DarkCyan
        Write-Host '   ║          LAPTOP-DIAGNOSE & REPARATUR  ' -ForegroundColor DarkCyan -NoNewline
        Write-Host ("v{0,-20}║" -f $Script:ToolVersion) -ForegroundColor DarkCyan
        Write-Host '   ╚════════════════════════════════════════════════════════════╝' -ForegroundColor DarkCyan
        if ($NurPruefen) { Write-Host '   Modus: NUR PRÜFEN – es werden keine Änderungen vorgenommen.' -ForegroundColor Yellow }
        Write-Host ''
        Write-Host '    1) Komplett-Diagnose (alle Prüfungen + Reparaturangebot)' -ForegroundColor White
        Write-Host '    2) Fehlersuche                  3) Sicherheit'
        Write-Host '    4) Speicherfresser              5) Leistungsbremsen'
        Write-Host '    6) Akku                         7) Netzwerk & WLAN'
        Write-Host '    8) Software-Updates             9) Windows & Treiber'
        Write-Host '    H) Herunterfahren & Neustart    W) Reparatur-Werkzeuge'
        Write-Host '    B) Gefundene Probleme beheben'
        Write-Host '    V) Verlauf & Trends             R) Änderungen rückgängig machen'
        Write-Host '    P) Geplante Wartung             G) Geräteübersicht erstellen'
        Write-Host '    S) Bericht speichern & öffnen   U) Programm-Updates'
        Write-Host '    0) Beenden'
        $found = $Script:Findings.Count
        if ($found) { Write-Host "`n   Bisher $found Prüfergebnis(se) erfasst – Gesundheitswert $((Get-HealthScore).Score)." -ForegroundColor DarkGray }
        Write-Host ''
        $c = (Read-Host '   Auswahl').Trim().ToUpperInvariant()
        switch ($c) {
            '1' { Invoke-FullDiagnosis }
            '2' { Invoke-SingleModule 'Fehler' }
            '3' { Invoke-SingleModule 'Sicherheit' }
            '4' { Invoke-SingleModule 'Speicher' }
            '5' { Invoke-SingleModule 'Leistung' }
            '6' { Invoke-SingleModule 'Akku' }
            '7' { Invoke-SingleModule 'Netzwerk' }
            '8' { Invoke-SingleModule 'Software' }
            '9' { Invoke-SingleModule 'Windows' }
            'H' { Invoke-SingleModule 'Herunterfahren' }
            'W' { Invoke-SingleModule 'Werkzeuge' }
            'B' { if ($found) { Invoke-Repairs } else { Write-Host '   Bitte zuerst eine Diagnose durchführen.' -ForegroundColor Yellow } }
            'V' { Invoke-SingleModule 'Verlauf' }
            'R' { Invoke-SingleModule 'Aenderungen' }
            'P' { Invoke-SingleModule 'Wartung' }
            'G' { Invoke-FleetOverviewConsole }
            'S' { $null = Export-Report -Open }
            'U' { Invoke-SingleModule 'Update' }
            '0' { return }
        }
        Write-Host ''
        $null = Read-Host '   Weiter mit [Enter]'
    }
}

function Start-LaptopDiagnose {
    if (-not (Test-IsAdmin) -and -not $Unbeaufsichtigt) {
        Write-Host 'Für die vollständige Diagnose und Reparatur werden Administratorrechte benötigt – starte neu mit Rechteabfrage ...' -ForegroundColor Yellow
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Modus', $Modus, '-BerichtOrdner', "`"$BerichtOrdner`"")
        if ($NurPruefen) { $argList += '-NurPruefen' }
        if ($Pdf) { $argList += '-Pdf' }
        $exe = (Get-Process -Id $PID).Path
        try {
            Start-Process -FilePath $exe -ArgumentList $argList -Verb RunAs
            return
        } catch {
            Write-Host 'Ohne Administratorrechte sind einige Prüfungen und alle Reparaturen eingeschränkt.' -ForegroundColor Yellow
        }
    }

    try { $Host.UI.RawUI.WindowTitle = $(if ($Unbeaufsichtigt) { 'Laptop-Diagnose – geplante Prüfung' } else { "Laptop-Diagnose & Reparatur $Script:ToolVersion" }) } catch { }
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
    if (-not (Test-Path -LiteralPath $BerichtOrdner)) { $null = New-Item -ItemType Directory -Path $BerichtOrdner -Force }
    $logPath = Join-Path $BerichtOrdner ('Protokoll_{0:yyyyMMdd_HHmmss}.txt' -f (Get-Date))
    try { Start-Transcript -Path $logPath -ErrorAction Stop | Out-Null } catch { }
    try {
        if ($Unbeaufsichtigt) { Invoke-UnattendedDiagnosis }
        else {
            switch ($Modus) {
                'Menue'    { Show-Menu }
                'Komplett' { Invoke-FullDiagnosis }
                default    {
                    Invoke-SingleModule $Modus
                    if ($Modus -notin 'Verlauf', 'Aenderungen', 'Wartung', 'Update') { $null = Export-Report }
                }
            }
        }
    } finally {
        try { Stop-Transcript | Out-Null } catch { }
    }
}

#endregion

# Beim Dot-Sourcing (z. B. für Tests) nur die Funktionen laden, nicht starten.
if ($MyInvocation.InvocationName -ne '.') { Start-LaptopDiagnose }
