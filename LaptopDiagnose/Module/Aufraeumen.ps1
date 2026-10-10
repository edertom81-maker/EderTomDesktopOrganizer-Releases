<#
    Downloads aufräumen (alte Installationsdateien, große Dateien, Duplikate – Löschen nur in den Papierkorb)
    und Vorher/Nachher-Vergleich nach Reparaturen.
    Teil von LaptopDiagnose – Copyright 2026 by Eder Tom
#>

#region ---------- Downloads aufräumen ----------

$Script:InstallerExtensions = @('.exe', '.msi', '.msix', '.msixbundle', '.appx', '.appxbundle', '.iso', '.img', '.zip', '.7z', '.rar', '.cab')

function Get-DownloadsFolder {
    # Tatsächlicher Downloads-Ordner (kann verschoben sein), sonst %USERPROFILE%\Downloads
    try {
        $p = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' -ErrorAction Stop).'{374DE290-123F-4565-9164-39C4925E467B}'
        if ($p) { $p = [Environment]::ExpandEnvironmentVariables($p); if (Test-Path -LiteralPath $p) { return $p } }
    } catch { }
    return (Join-Path $env:USERPROFILE 'Downloads')
}

function Get-DownloadCleanupCandidates {
    <#
        Liefert Aufräumvorschläge aus dem Downloads-Ordner:
        - Installationsdateien und Archive, die älter als $InstallerDays Tage sind
        - sehr große Dateien (ab $BigFileMB MB), die seit $BigFileDays Tagen nicht geändert wurden
        - doppelte Dateien (gleicher Inhalt) – die älteste Kopie bleibt erhalten
        Nur in der Cloud liegende Dateien (OneDrive) werden nicht berücksichtigt.
    #>
    param([string]$Folder = (Get-DownloadsFolder), [int]$InstallerDays = 30, [int]$BigFileMB = 500, [int]$BigFileDays = 90)
    if (-not (Test-Path -LiteralPath $Folder)) { return @() }
    $now = Get-Date
    $files = @(Get-ChildItem -LiteralPath $Folder -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { -not ([int]$_.Attributes -band ([int][IO.FileAttributes]::Offline -bor 0x400000 -bor 0x40000)) -and $_.Name -ne 'desktop.ini' })
    $result = [ordered]@{}

    # Duplikate: erst nach Größe gruppieren, nur dann Prüfsummen bilden
    foreach ($g in $files | Where-Object { $_.Length -ge 1MB } | Group-Object Length | Where-Object { $_.Count -gt 1 }) {
        $hashed = foreach ($f in $g.Group) {
            try { [pscustomobject]@{ File = $f; Hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction Stop).Hash } } catch { }
        }
        foreach ($h in @($hashed) | Group-Object Hash | Where-Object { $_.Count -gt 1 }) {
            $sorted = @($h.Group | Sort-Object { $_.File.CreationTime })
            $original = $sorted[0].File
            foreach ($dup in $sorted | Select-Object -Skip 1) {
                $result[$dup.File.FullName] = [pscustomobject]@{ Path = $dup.File.FullName; Name = $dup.File.Name; Size = [double]$dup.File.Length; Reason = "Duplikat von »$($original.Name)«"; Date = $dup.File.LastWriteTime }
            }
        }
    }
    foreach ($f in $files) {
        if ($result.Contains($f.FullName)) { continue }
        $age = ($now - $f.LastWriteTime).TotalDays
        if ($Script:InstallerExtensions -contains $f.Extension.ToLowerInvariant() -and $age -ge $InstallerDays) {
            $kind = if ($f.Extension -match '^\.(zip|7z|rar|cab)$') { 'Archiv' } elseif ($f.Extension -match '^\.(iso|img)$') { 'Datenträgerabbild' } else { 'Installationsdatei' }
            $result[$f.FullName] = [pscustomobject]@{ Path = $f.FullName; Name = $f.Name; Size = [double]$f.Length; Reason = "$kind, $([math]::Floor($age)) Tage alt"; Date = $f.LastWriteTime }
        } elseif ($f.Length -ge $BigFileMB * 1MB -and $age -ge $BigFileDays) {
            $result[$f.FullName] = [pscustomobject]@{ Path = $f.FullName; Name = $f.Name; Size = [double]$f.Length; Reason = "Große Datei, seit $([math]::Floor($age)) Tagen unverändert"; Date = $f.LastWriteTime }
        }
    }
    return @($result.Values | Sort-Object Size -Descending)
}

function Remove-ToRecycleBin {
    <# Verschiebt Dateien in den Papierkorb (wiederherstellbar). #>
    param($Entries)
    Add-Type -AssemblyName Microsoft.VisualBasic
    $ok = 0; $freed = [double]0; $failed = @()
    foreach ($e in @($Entries)) {
        try {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($e.Path, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
            $ok++; $freed += $e.Size
        } catch { $failed += $e.Name }
    }
    $msg = "$ok Datei(en) mit $(Format-Bytes $freed) in den Papierkorb verschoben."
    if ($failed) { $msg += " Nicht möglich (in Benutzung?): $($failed -join ', ')." }
    $msg += ' Endgültig frei wird der Platz nach dem Leeren des Papierkorbs.'
    Register-Change -Beschreibung "Downloads aufgeräumt: $ok Datei(en), $(Format-Bytes $freed)" -Typ 'Protokoll' -NichtUmkehrbar `
        -Ergebnis 'Die Dateien liegen im Papierkorb und lassen sich dort wiederherstellen.'
    return $msg
}

function Add-DownloadCleanupFindings {
    param([string]$Category)
    $folder = Get-DownloadsFolder
    $candidates = @(Get-DownloadCleanupCandidates -Folder $folder)
    $total = Get-FolderSize -Path $folder
    if (-not $candidates) {
        if ($total -ge 5GB) { Add-Finding $Category Info "Downloads-Ordner belegt $(Format-Bytes $total)" -Detail 'Keine offensichtlich überflüssigen Dateien gefunden (alte Installationsdateien, Duplikate, große alte Dateien).' }
        return
    }
    $sum = [double](($candidates | Measure-Object Size -Sum).Sum)
    $dups = @($candidates | Where-Object { $_.Reason -like 'Duplikat*' }).Count
    $labels = @($candidates | ForEach-Object { '{0,10}  {1}  –  {2}' -f (Format-Bytes $_.Size), $_.Name, $_.Reason })
    $sev = if ($sum -ge 5GB) { 'Warnung' } else { 'Info' }
    $detail = "Der Downloads-Ordner belegt $(Format-Bytes $total). Vorgeschlagen werden alte Installationsdateien und Archive (älter als 30 Tage), große seit 90 Tagen unveränderte Dateien"
    $detail += if ($dups) { " und $dups doppelte Datei(en)." } else { '.' }
    $detail += ' Gelöscht wird nur, was Sie im nächsten Schritt ankreuzen – und zwar in den Papierkorb.'
    Add-Finding $Category $sev "Downloads aufräumen: $(Format-Bytes $sum) in $($candidates.Count) Datei(en) freigebbar" -Detail $detail `
        -Items ($labels | Select-Object -First 40) -FixLabel 'Ausgewählte Downloads in den Papierkorb verschieben' -FixData $candidates `
        -SelectLabels $labels -Fix {
        param($d, $pre)
        if (-not $pre) {
            # Konsole: Auswahl abfragen
            $all = @($d)
            for ($i = 0; $i -lt $all.Count; $i++) { Write-Host ('    {0,3}) {1,10}  {2}  – {3}' -f ($i + 1), (Format-Bytes $all[$i].Size), $all[$i].Name, $all[$i].Reason) }
            $sel = Read-Host '   In den Papierkorb: [A] alle, Nummern (z. B. 1,3,5-7) oder leer = keine'
            $d = if ($sel -match '^\s*(a|alle)\s*$') { $all } else { @((Read-Selection $sel $all.Count) | ForEach-Object { $all[$_] }) }
            if (-not $d) { return 'Nichts ausgewählt – keine Datei gelöscht.' }
        }
        Remove-ToRecycleBin $d
    }
}

#endregion

#region ---------- Vorher/Nachher-Vergleich ----------

function Get-QuickState {
    <# Schnell messbare Kennzahlen für den Vergleich vor und nach Reparaturen. #>
    $state = [ordered]@{ Zeit = Get-Date }
    try {
        $sys = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$env:SystemDrive'" -ErrorAction Stop
        $state.FreierSpeicher = [double]$sys.FreeSpace
    } catch { }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $state.RAM = [math]::Round((1 - [double]$os.FreePhysicalMemory / [double]$os.TotalVisibleMemorySize) * 100)
    } catch { }
    try { $state.Autostart = @(Get-AutostartEntries | Where-Object { $_.Enabled }).Count } catch { }
    $open = @($Script:Findings | Where-Object { -not $_.Fixed })
    $state.Kritisch = @($open | Where-Object { $_.Severity -eq 'Kritisch' }).Count
    $state.Warnung = @($open | Where-Object { $_.Severity -eq 'Warnung' }).Count
    try { $state.Gesundheit = (Get-HealthScore).Score } catch { }
    return [pscustomobject]$state
}

function Compare-QuickState {
    <# Liefert lesbare Zeilen »vorher → nachher«; unveränderte Speicher-/RAM-Werte werden weggelassen. #>
    param($Before, $After)
    $lines = New-Object System.Collections.Generic.List[string]
    if ($null -ne $Before.Gesundheit -and $null -ne $After.Gesundheit) {
        $lines.Add(('Gesundheitswert:            {0} → {1}' -f $Before.Gesundheit, $After.Gesundheit))
    }
    $lines.Add(('Kritische Punkte offen:     {0} → {1}' -f $Before.Kritisch, $After.Kritisch))
    $lines.Add(('Warnungen offen:            {0} → {1}' -f $Before.Warnung, $After.Warnung))
    if ($null -ne $Before.FreierSpeicher -and $null -ne $After.FreierSpeicher) {
        $diff = $After.FreierSpeicher - $Before.FreierSpeicher
        if ([math]::Abs($diff) -ge 50MB) {
            $sign = if ($diff -ge 0) { '+' } else { '−' }
            $lines.Add(('Freier Speicher {0}:         {1} → {2} ({3}{4})' -f $env:SystemDrive, (Format-Bytes $Before.FreierSpeicher), (Format-Bytes $After.FreierSpeicher), $sign, (Format-Bytes ([math]::Abs($diff)))))
        }
    }
    if ($null -ne $Before.Autostart -and $null -ne $After.Autostart -and $Before.Autostart -ne $After.Autostart) {
        $lines.Add(('Autostart-Programme aktiv:  {0} → {1}' -f $Before.Autostart, $After.Autostart))
    }
    if ($null -ne $Before.RAM -and $null -ne $After.RAM -and [math]::Abs($Before.RAM - $After.RAM) -ge 3) {
        $lines.Add(('Arbeitsspeicher belegt:     {0} % → {1} %' -f $Before.RAM, $After.RAM))
    }
    return $lines.ToArray()
}

#endregion
