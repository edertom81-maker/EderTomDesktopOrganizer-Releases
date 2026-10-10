<#
    Berichtordner: Speicherort festlegen, einmaliger Umzug aus dem (oft OneDrive-)Dokumente-Ordner, alte Berichte aufräumen.
    Wird auch direkt von der Oberfläche geladen, darf daher nur Funktionen ohne Abhängigkeiten enthalten.
    Teil von LaptopDiagnose – Copyright 2026 by Eder Tom
#>

$Script:AppDataDir = Join-Path $env:LOCALAPPDATA 'LaptopDiagnose'
$Script:FolderConfigPath = Join-Path $Script:AppDataDir 'Berichtordner.json'
# Dateigruppen, die beim Aufräumen berücksichtigt werden (je Gruppe bleiben die neuesten N Zeitstempel erhalten)
$Script:ReportPrefixes = @('Diagnosebericht_', 'Akkubericht_', 'WLAN-Bericht_', 'Standby-Analyse_', 'Energiebericht_', 'Geraeteuebersicht_')

function Get-DefaultReportFolder {
    <# Lokaler Dokumente-Ordner – auch wenn Windows »Dokumente« nach OneDrive umgeleitet hat. #>
    $profileDir = $env:USERPROFILE
    if (-not $profileDir) { $profileDir = [Environment]::GetFolderPath('UserProfile') }
    Join-Path (Join-Path $profileDir 'Documents') 'LaptopDiagnose'
}

function Get-LegacyReportFolder {
    <# Speicherort bis Version 2.3: der (ggf. nach OneDrive umgeleitete) Dokumente-Ordner. #>
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { return '' }
    Join-Path $docs 'LaptopDiagnose'
}

function Get-ReportFolder {
    try {
        if (Test-Path -LiteralPath $Script:FolderConfigPath) {
            $j = [IO.File]::ReadAllText($Script:FolderConfigPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($j.Ordner) { return [string]$j.Ordner }
        }
    } catch { }
    return Get-DefaultReportFolder
}

function Save-ReportFolderSetting {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Script:AppDataDir)) { $null = New-Item -ItemType Directory -Path $Script:AppDataDir -Force }
    $json = [pscustomobject]@{ Ordner = $Path; Geaendert = (Get-Date).ToString('s') } | ConvertTo-Json
    [IO.File]::WriteAllText($Script:FolderConfigPath, $json, (New-Object System.Text.UTF8Encoding $false))
}

function Test-OneDrivePath {
    param([string]$Path)
    foreach ($root in @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial) | Where-Object { $_ }) {
        if ($Path.TrimEnd('\') + '\' -like ($root.TrimEnd('\') + '\*')) { return $true }
    }
    return $false
}

function Move-ReportFolderContent {
    <#
        Verschiebt Berichte, Verlauf, Änderungsprotokoll und Einstellungen in einen anderen Ordner.
        Bereits vorhandene Dateien im Ziel werden nicht überschrieben. Liefert die Anzahl verschobener und fehlgeschlagener Dateien.
    #>
    param([Parameter(Mandatory)][string]$From, [Parameter(Mandatory)][string]$To)
    $moved = 0; $failed = 0; $skipped = 0
    if (-not (Test-Path -LiteralPath $From)) { return [pscustomobject]@{ Moved = 0; Failed = 0; Skipped = 0 } }
    $src = (Get-Item -LiteralPath $From).FullName.TrimEnd('\')
    if (-not (Test-Path -LiteralPath $To)) { $null = New-Item -ItemType Directory -Path $To -Force }
    foreach ($file in Get-ChildItem -LiteralPath $src -Recurse -File -Force -ErrorAction SilentlyContinue) {
        $rel = $file.FullName.Substring($src.Length + 1)
        $dst = Join-Path $To $rel
        if (Test-Path -LiteralPath $dst) { $skipped++; continue }
        try {
            $dir = Split-Path -Parent $dst
            if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
            Move-Item -LiteralPath $file.FullName -Destination $dst -ErrorAction Stop
            $moved++
        } catch { $failed++ }
    }
    # Leere Ordner im alten Speicherort entfernen
    Get-ChildItem -LiteralPath $src -Recurse -Directory -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending | ForEach-Object {
        if (-not (Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    }
    if (-not (Get-ChildItem -LiteralPath $src -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) { Remove-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue }
    return [pscustomobject]@{ Moved = $moved; Failed = $failed; Skipped = $skipped }
}

function Update-MaintenanceTaskFolder {
    <# Ältere Versionen haben den Berichtordner fest in die geplante Wartung eingetragen; ab 2.4 ermittelt sie ihn selbst. #>
    try {
        if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return }
        $task = Get-ScheduledTask -TaskPath '\EderTom\' -TaskName 'LaptopDiagnose Wartung' -ErrorAction SilentlyContinue
        if (-not $task) { return }
        $action = @($task.Actions)[0]
        if ($action.Arguments -notmatch '-BerichtOrdner') { return }
        $action.Arguments = ($action.Arguments -replace '\s+-BerichtOrdner\s+("[^"]*"|\S+)', '')
        $null = Set-ScheduledTask -TaskPath '\EderTom\' -TaskName 'LaptopDiagnose Wartung' -Action $action -ErrorAction Stop
    } catch { }
}

function Initialize-ReportFolder {
    <#
        Einmalig beim ersten Start ab Version 2.4: Speicherort festlegen und vorhandene Daten aus dem bisherigen
        Ordner übernehmen. Liefert $null, wenn nichts zu tun war, sonst eine kurze Meldung.
    #>
    if (Test-Path -LiteralPath $Script:FolderConfigPath) { return $null }
    $new = Get-DefaultReportFolder
    $old = Get-LegacyReportFolder
    $message = $null
    if ($old -and $old.TrimEnd('\') -ne $new.TrimEnd('\') -and (Test-Path -LiteralPath $old)) {
        $r = Move-ReportFolderContent -From $old -To $new
        $message = "Berichtordner auf den lokalen Ordner umgestellt: $new ($($r.Moved) Datei(en) aus $old übernommen"
        if ($r.Failed) { $message += ", $($r.Failed) konnten nicht verschoben werden und bleiben am alten Ort" }
        $message += ')'
    }
    try { Save-ReportFolderSetting -Path $new } catch { }
    Update-MaintenanceTaskFolder
    return $message
}

function Resolve-ReportFolder {
    <#
        Ermittelt den zu verwendenden Berichtordner. Ältere Versionen übergeben beim Neustart nach einem Update
        bzw. in der geplanten Wartung noch den alten Ordner fest – dieser wird ignoriert, damit der Umzug greift.
    #>
    param([string]$Requested)
    if ($Requested -and $Requested.TrimEnd('\') -ne "$(Get-LegacyReportFolder)".TrimEnd('\')) {
        return [pscustomobject]@{ Folder = $Requested; Message = $null }
    }
    $msg = Initialize-ReportFolder
    return [pscustomobject]@{ Folder = (Get-ReportFolder); Message = $msg }
}

function Remove-OldReports {
    <# Behält je Berichtsart die neuesten $Keep Berichte (0 = alle behalten). Verlauf und Änderungsprotokoll bleiben unberührt. #>
    param([string]$Folder = $BerichtOrdner, [int]$Keep = 30)
    if ($Keep -le 0 -or -not (Test-Path -LiteralPath $Folder)) { return 0 }
    $removed = 0
    $files = @(Get-ChildItem -LiteralPath $Folder -File -ErrorAction SilentlyContinue)
    foreach ($prefix in $Script:ReportPrefixes) {
        $groups = $files | Where-Object { $_.Name.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) } |
            Group-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) } | Sort-Object Name -Descending
        foreach ($g in @($groups) | Select-Object -Skip $Keep) {
            foreach ($f in $g.Group) {
                try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; $removed++ } catch { }
            }
        }
    }
    return $removed
}
