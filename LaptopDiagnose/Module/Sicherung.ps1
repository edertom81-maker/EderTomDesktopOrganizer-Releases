<#
    Datensicherung prüfen sowie alte Sicherungen und Wiederherstellungsdaten (Wiederherstellungspunkte,
    Systemabbilder, Dateiversionsverlauf, Upgrade-Reste, alte Treiberpakete).
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

#region ---------- Datensicherung ----------

function Get-OneDriveFolderBackup {
    <# Welche Benutzerordner liegen im OneDrive (Ordnersicherung von OneDrive bzw. »Windows-Sicherung«)? #>
    $roots = @($env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial) | Where-Object { $_ } | Select-Object -Unique
    if (-not $roots) { return @() }
    $folders = [ordered]@{ 'Desktop' = [Environment]::GetFolderPath('Desktop'); 'Dokumente' = [Environment]::GetFolderPath('MyDocuments'); 'Bilder' = [Environment]::GetFolderPath('MyPictures') }
    foreach ($k in $folders.Keys) {
        $p = $folders[$k]
        if ($p -and ($roots | Where-Object { ($p.TrimEnd('\') + '\') -like ($_.TrimEnd('\') + '\*') })) { $k }
    }
}

function Get-FileHistoryInfo {
    <# Dateiversionsverlauf: eingerichtet? Ziel, letzte Aktivität (geschätzt aus den Konfigurationsdateien). #>
    $cfg = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\FileHistory\Configuration'
    if (-not (Test-Path -LiteralPath $cfg)) { return $null }
    $files = @(Get-ChildItem -LiteralPath $cfg -File -ErrorAction SilentlyContinue)
    if (-not $files) { return $null }
    $target = $null
    $xml = $files | Where-Object { $_.Name -like 'Config*.xml' } | Select-Object -First 1
    if ($xml) {
        try { $target = ([xml](Get-Content -LiteralPath $xml.FullName -Raw)).SelectSingleNode('//TargetUrl').InnerText } catch { }
    }
    $last = ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    $enabled = $true
    try { $enabled = (Get-Service -Name fhsvc -ErrorAction Stop).StartType -ne 'Disabled' } catch { }
    [pscustomobject]@{ Target = $target; Last = $last; Enabled = $enabled }
}

function Get-SystemImageBackups {
    <# Systemabbilder (Windows-Sicherung »Systemabbild erstellen«) auf allen bereiten Laufwerken. #>
    foreach ($d in [IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -in 'Fixed', 'Removable' }) {
        $root = Join-Path $d.RootDirectory.FullName 'WindowsImageBackup'
        if (-not (Test-Path -LiteralPath $root)) { continue }
        foreach ($pc in Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue) {
            foreach ($b in Get-ChildItem -LiteralPath $pc.FullName -Directory -Force -Filter 'Backup *' -ErrorAction SilentlyContinue) {
                [pscustomobject]@{ Path = $b.FullName; Name = "$($pc.Name) – $($b.Name)"; Computer = $pc.Name; Date = $b.LastWriteTime; Drive = $d.Name; IsFolder = $true; Size = [double](Get-DirectorySizeFast $b.FullName) }
            }
        }
    }
}

function Get-BackupSoftware {
    <# Installierte Sicherungsprogramme von Drittanbietern. #>
    $pattern = 'Acronis|Macrium|Veeam|AOMEI Backupper|EaseUS Todo|Paragon Backup|O&O AutoBackup|Ashampoo Backup|Duplicati|Backblaze|Carbonite|Iperius|Cobian'
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    @(Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match $pattern } | ForEach-Object { $_.DisplayName } | Select-Object -Unique)
}

function Add-BackupStatusFindings {
    param([string]$Category)
    $items = @()
    $ok = $false; $stale = $false
    $od = @(Get-OneDriveFolderBackup)
    if ($od) { $items += "OneDrive sichert: $($od -join ', ')"; $ok = $true }
    $fh = Get-FileHistoryInfo
    if ($fh) {
        $age = [math]::Floor(((Get-Date) - $fh.Last).TotalDays)
        $items += "Dateiversionsverlauf: eingerichtet$(if ($fh.Target) { " (Ziel: $($fh.Target))" }) – zuletzt aktiv vor ca. $age Tag(en)$(if (-not $fh.Enabled) { ', Dienst deaktiviert' })"
        if ($age -le 30 -and $fh.Enabled) { $ok = $true } else { $stale = $true }
    }
    $images = @(Get-SystemImageBackups)
    if ($images) {
        $newest = $images | Sort-Object Date -Descending | Select-Object -First 1
        $age = [math]::Floor(((Get-Date) - $newest.Date).TotalDays)
        $items += "Systemabbild: neuestes vom $($newest.Date.ToString('dd.MM.yyyy')) auf $($newest.Drive) ($age Tage alt)"
        if ($age -le 90) { $ok = $true } else { $stale = $true }
    }
    $sw = @(Get-BackupSoftware)
    if ($sw) { $items += "Sicherungsprogramm installiert: $($sw -join ', ') (Stand bitte dort prüfen)"; $ok = $true }

    $fixArgs = @{ FixLabel = 'Windows-Einstellungen zur Datensicherung öffnen'; Fix = { param($d) Start-Process 'ms-settings:backup'; 'Einstellungen zur Datensicherung geöffnet.' } }
    if (-not $items) {
        Add-Finding $Category Warnung 'Keine Datensicherung gefunden' -Detail 'Weder OneDrive-Ordnersicherung noch Dateiversionsverlauf, Systemabbild oder ein Sicherungsprogramm sind eingerichtet. Bei einem Festplattenschaden, Diebstahl oder Erpressungstrojaner wären Fotos und Dokumente verloren. Empfehlung: Windows-Sicherung bzw. OneDrive für Desktop, Dokumente und Bilder einschalten oder regelmäßig auf eine externe Festplatte sichern (Dateiversionsverlauf).' @fixArgs
    } elseif ($stale -and -not $ok) {
        Add-Finding $Category Warnung 'Datensicherung veraltet' -Items $items -Detail 'Die letzte Sicherung ist schon länger her. Externe Sicherungsplatte anschließen bzw. die Sicherung prüfen.' @fixArgs
    } elseif ($od -and -not $fh -and -not $images -and -not $sw) {
        Add-Finding $Category Info 'Dateien werden über OneDrive gesichert' -Items $items -Detail 'Desktop/Dokumente/Bilder liegen in OneDrive. Andere Ordner (z. B. Downloads, Videos) und das System selbst sind nicht gesichert. Achtung: Löschungen werden ebenfalls synchronisiert – gelöschte Dateien liegen nur 30 Tage im OneDrive-Papierkorb.' @fixArgs
    } else {
        Add-Finding $Category OK 'Datensicherung eingerichtet' -Items $items
    }
}

#endregion

#region ---------- Wiederherstellungspunkte ----------

function Get-RestorePointStorage {
    $letter = $env:SystemDrive
    $vol = Get-CimInstance Win32_Volume -Filter "DriveLetter='$letter'" -ErrorAction Stop
    # Zuordnung über die Volume-GUID (die Darstellung des Volume-Verweises unterscheidet sich je nach Abfrageweg)
    $guid = if ("$($vol.DeviceID)" -match '\{[0-9A-Fa-f-]+\}') { $Matches[0] } else { "$($vol.DeviceID)" }
    $storage = Get-CimInstance Win32_ShadowStorage -ErrorAction SilentlyContinue | Where-Object { "$($_.Volume)" -match [regex]::Escape($guid) } | Select-Object -First 1
    $copies = @(Get-CimInstance Win32_ShadowCopy -ErrorAction SilentlyContinue | Where-Object { $_.VolumeName -eq $vol.DeviceID } | Sort-Object InstallDate)
    [pscustomobject]@{ Drive = $letter; Used = [double]$storage.UsedSpace; Max = [double]$storage.MaxSpace; Capacity = [double]$vol.Capacity; Copies = $copies }
}

function Invoke-RestorePointActions {
    param($Actions)
    $msgs = @()
    foreach ($a in @($Actions)) {
        switch ($a.Action) {
            'DeleteOld' {
                $info = Get-RestorePointStorage
                $n = @($info.Copies).Count
                $deleted = 0
                for ($i = 1; $i -lt $n; $i++) {
                    $null = & vssadmin.exe delete shadows /for=$($info.Drive) /oldest /quiet 2>&1
                    if ($LASTEXITCODE -eq 0) { $deleted++ } else { break }
                }
                $after = Get-RestorePointStorage
                Register-Change -Beschreibung "Ältere Wiederherstellungspunkte gelöscht: $deleted" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis "$(Format-Bytes ($info.Used - $after.Used)) freigegeben, der neueste Punkt bleibt erhalten."
                $msgs += "$deleted ältere Wiederherstellungspunkt(e) gelöscht ($(Format-Bytes ($info.Used - $after.Used)) frei), der neueste bleibt erhalten."
            }
            'Limit' {
                $info = Get-RestorePointStorage
                $prevMb = [math]::Round($info.Max / 1MB)
                $null = & vssadmin.exe resize shadowstorage /for=$($info.Drive) /on=$($info.Drive) /maxsize=$($a.Percent)% 2>&1
                if ($LASTEXITCODE -ne 0) { throw "vssadmin konnte die Obergrenze nicht setzen (Exitcode $LASTEXITCODE)." }
                if ($prevMb -gt 0) {
                    Register-Change -Beschreibung "Speicher für Wiederherstellungspunkte auf $($a.Percent) % begrenzt" -Typ 'Schattenspeicher' -Daten @{ Drive = $info.Drive; PreviousMB = $prevMb }
                } else {
                    Register-Change -Beschreibung "Speicher für Wiederherstellungspunkte auf $($a.Percent) % begrenzt" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis 'Vorheriger Wert unbekannt.'
                }
                $msgs += "Obergrenze für Wiederherstellungspunkte auf $($a.Percent) % gesetzt (vorher $(Format-Bytes $info.Max))."
            }
        }
    }
    $msgs -join ' '
}

function Add-RestorePointFindings {
    param([string]$Category)
    $info = Get-RestorePointStorage
    $n = @($info.Copies).Count
    if (-not $info.Capacity) { return }
    $pctUsed = [math]::Round($info.Used / $info.Capacity * 100, 1)
    $pctMax = if ($info.Max -gt 0 -and $info.Max -lt [double]::MaxValue / 2) { [math]::Round($info.Max / $info.Capacity * 100) } else { 100 }
    $items = @("Belegt: $(Format-Bytes $info.Used) ($pctUsed % von $($info.Drive))", "Obergrenze: $(if ($pctMax -ge 100) { 'unbegrenzt' } else { "$(Format-Bytes $info.Max) ($pctMax %)" })", "Anzahl Punkte: $n")
    $items += @($info.Copies | Select-Object -Last 10 | ForEach-Object { '  {0:dd.MM.yyyy HH:mm}' -f $_.InstallDate })
    if ($info.Used -lt 5GB -and $pctMax -le 10) {
        Add-Finding $Category OK "Wiederherstellungspunkte: $(Format-Bytes $info.Used) ($n Punkt(e))" -Items $items
        return
    }
    $actions = @(); $labels = @()
    if ($n -gt 1) { $actions += [pscustomobject]@{ Action = 'DeleteOld' }; $labels += "Ältere Wiederherstellungspunkte löschen ($($n - 1) Stück) – der neueste bleibt erhalten (nicht umkehrbar)" }
    if ($pctMax -gt 8) { $actions += [pscustomobject]@{ Action = 'Limit'; Percent = 5 }; $labels += "Obergrenze auf 5 % von $($info.Drive) setzen (ca. $(Format-Bytes ($info.Capacity * 0.05))) – rückgängig über »Änderungen«" }
    $sev = if ($info.Used -ge 20GB -or $pctUsed -ge 10) { 'Warnung' } else { 'Info' }
    $fixArgs = @{}
    if ($actions) {
        $fixArgs = @{ FixLabel = 'Wiederherstellungspunkte aufräumen bzw. begrenzen'; FixData = $actions; SelectLabels = $labels; Fix = {
                param($d, $pre)
                if (-not $pre) {
                    $all = @($d)
                    for ($i = 0; $i -lt $all.Count; $i++) { Write-Host ('    {0}) {1}' -f ($i + 1), $(if ($all[$i].Action -eq 'DeleteOld') { 'Ältere Wiederherstellungspunkte löschen (neuester bleibt)' } else { "Obergrenze auf $($all[$i].Percent) % setzen" })) }
                    $sel = Read-Host '   Auswahl: Nummern oder leer = nichts'
                    $d = @((Read-Selection $sel $all.Count) | ForEach-Object { $all[$_] })
                    if (-not $d) { return 'Nichts ausgewählt.' }
                }
                Invoke-RestorePointActions $d
            }
        }
    }
    Add-Finding $Category $sev "Wiederherstellungspunkte belegen $(Format-Bytes $info.Used) ($n Punkt(e))" -Items $items @fixArgs `
        -Detail 'Wiederherstellungspunkte sind nützlich, um nach einer fehlerhaften Änderung zurückzukehren. Meist reichen die letzten Punkte und eine Obergrenze von 5 % des Laufwerks. Windows löscht bei Erreichen der Grenze automatisch die ältesten.'
}

#endregion

#region ---------- Systemabbilder, Dateiversionsverlauf, Upgrade-Reste, Protokolle ----------

function Add-OldImageBackupFindings {
    param([string]$Category)
    $images = @(Get-SystemImageBackups)
    if (-not $images) { return }
    # Je Computer bleibt das neueste Abbild; ältere (und Abbilder anderer Computer) werden angeboten
    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($g in $images | Group-Object { "$($_.Drive)|$($_.Computer)" }) {
        $sorted = @($g.Group | Sort-Object Date -Descending)
        foreach ($old in $sorted | Select-Object -Skip 1) { $candidates.Add($old) }
    }
    $items = @($images | Sort-Object Date -Descending | ForEach-Object { '{0,10}  {1:dd.MM.yyyy}  {2}' -f (Format-Bytes $_.Size), $_.Date, $_.Path })
    if (-not $candidates.Count) {
        Add-Finding $Category Info "Systemabbild-Sicherung: $(@($images).Count) vorhanden" -Items $items -Detail 'Es gibt je Computer nur ein Abbild – es wird nicht zum Löschen angeboten.'
        return
    }
    $sum = [double](($candidates | Measure-Object Size -Sum).Sum)
    $labels = @($candidates | ForEach-Object { '{0} · {1:dd.MM.yyyy} · {2}' -f (Format-Bytes $_.Size), $_.Date, $_.Path })
    Add-Finding $Category Info "Alte Systemabbilder: $(Format-Bytes $sum) in $($candidates.Count) älteren Sicherung(en)" -Items $items -SelectLabels $labels -FixData $candidates.ToArray() `
        -Detail 'Das jeweils neueste Abbild je Computer bleibt immer erhalten und wird nicht angeboten. Abbilder auf externen Platten haben keinen Papierkorb – sie erscheinen dann auf der Karte »Endgültig löschen?«.' `
        -FixLabel 'Ausgewählte alte Systemabbilder löschen' -Fix {
        param($d, $pre)
        $res = Remove-PathsToRecycleBin @($d)
        if (@($res.Ok).Count) { Register-Change -Beschreibung "Alte Systemabbilder gelöscht: $(@($res.Ok).Count)" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis (($res.Ok | ForEach-Object { $_.Path }) -join '; ') }
        Add-PermanentDeleteFinding $res.Rest
        Get-DeleteResultText $res 'Sicherung(en)'
    }
}

function Add-FileHistoryVersionFindings {
    param([string]$Category)
    $fh = Get-FileHistoryInfo
    if (-not $fh -or -not $fh.Target) { return }
    $root = $fh.Target.TrimEnd('\')
    $data = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'FileHistory' } | Select-Object -First 1
    $path = if ($data) { $data.FullName } elseif (Test-Path -LiteralPath $root) { $root } else { $null }
    if (-not $path) { return }
    $size = [double](Get-DirectorySizeFast $path)
    if ($size -lt 5GB) { return }
    Add-Finding $Category Info "Dateiversionsverlauf belegt $(Format-Bytes $size) auf dem Sicherungsziel" -Detail "Ziel: $path. Windows bewahrt standardmäßig alle Versionen »für immer« auf. Ältere Versionen lassen sich mit der Windows-Funktion entfernen – die aktuelle Version jeder Datei bleibt erhalten." `
        -FixLabel 'Dateiversionen älter als 1 Jahr entfernen (Windows-Funktion)' -Fix {
        param($d)
        $exe = Join-Path $env:SystemRoot 'System32\fhmanagew.exe'
        if (-not (Test-Path -LiteralPath $exe)) { throw 'fhmanagew.exe nicht gefunden.' }
        $p = Start-Process -FilePath $exe -ArgumentList '-cleanup 365 -quiet' -Wait -PassThru
        Register-Change -Beschreibung 'Dateiversionsverlauf: Versionen älter als 1 Jahr entfernt' -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis "Exitcode $($p.ExitCode)"
        "Aufräumen des Dateiversionsverlaufs beendet (Exitcode $($p.ExitCode))."
    }
}

function Add-UpgradeLeftoverFindings {
    param([string]$Category)
    $sd = $env:SystemDrive + '\'
    $paths = @('$WINDOWS.~BT', '$WINDOWS.~WS', 'ESD', '$GetCurrent', '$SysReset') | ForEach-Object { Join-Path $sd $_ } | Where-Object { Test-Path -LiteralPath $_ }
    if (-not $paths) { return }
    if (Get-Process -Name SetupHost, SetupPrep, WindowsUpdateBox -ErrorAction SilentlyContinue) {
        Add-Finding $Category Info 'Reste von Windows-Upgrades vorhanden – ein Upgrade läuft gerade' -Detail 'Erst nach Abschluss des Upgrades aufräumen.'
        return
    }
    $entries = @($paths | ForEach-Object { [pscustomobject]@{ Path = $_; Size = [double](Get-DirectorySizeFast $_) } } | Where-Object { $_.Size -gt 50MB })
    if (-not $entries) { return }
    $sum = [double](($entries | Measure-Object Size -Sum).Sum)
    Add-Finding $Category $(if ($sum -ge 3GB) { 'Warnung' } else { 'Info' }) "Reste von Windows-Upgrades belegen $(Format-Bytes $sum)" `
        -Items @($entries | ForEach-Object { '{0,10}  {1}' -f (Format-Bytes $_.Size), $_.Path }) -FixData $entries `
        -Detail 'Installationsdateien früherer Windows-Upgrades (Ordner $WINDOWS.~BT, $WINDOWS.~WS, ESD …). Sie werden nach erfolgreichem Upgrade nicht mehr gebraucht.' `
        -FixLabel 'Upgrade-Reste entfernen (Datenträgerbereinigung)' -Fix {
        param($d)
        $res = Invoke-CleanMgr @('Temporary Setup Files', 'Windows ESD installation files', 'Windows Upgrade Log Files', 'Setup Log Files')
        foreach ($e in @($d)) {
            if (Test-Path -LiteralPath $e.Path) {
                $null = & takeown.exe /F $e.Path /R /A /D Y 2>&1
                $null = & icacls.exe $e.Path /grant '*S-1-5-32-544:F' /T /C /Q 2>&1
                Remove-Item -LiteralPath $e.Path -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        $left = @($d | Where-Object { Test-Path -LiteralPath $_.Path })
        Register-Change -Beschreibung 'Reste von Windows-Upgrades entfernt' -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis $res
        $res + $(if ($left) { " Nicht vollständig entfernt: $(($left | ForEach-Object { $_.Path }) -join ', ')." } else { '' })
    }
}

#endregion

#region ---------- Alte Treiberpakete ----------

function Get-OldDriverPackages {
    <# Ältere Versionen desselben Treibers im Treiberspeicher, die von keinem Gerät benutzt werden. #>
    $all = @(Get-WindowsDriver -Online -ErrorAction Stop | Where-Object { $_.Driver -like 'oem*.inf' })
    $inUse = @{}
    foreach ($s in Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue) { if ($s.InfName) { $inUse[$s.InfName.ToLowerInvariant()] = $true } }
    foreach ($g in $all | Group-Object { '{0}|{1}|{2}' -f [IO.Path]::GetFileName($_.OriginalFileName).ToLowerInvariant(), $_.ProviderName, $_.ClassName } | Where-Object { $_.Count -gt 1 }) {
        $sorted = @($g.Group | Sort-Object { try { [version]$_.Version } catch { [version]'0.0' } }, Date -Descending)
        foreach ($old in $sorted | Select-Object -Skip 1) {
            if ($inUse.ContainsKey($old.Driver.ToLowerInvariant())) { continue }
            $dir = Split-Path -Parent $old.OriginalFileName
            $size = if ($dir -and (Test-Path -LiteralPath $dir)) { [double](Get-DirectorySizeFast $dir) } else { [double]0 }
            [pscustomobject]@{ Inf = $old.Driver; Name = [IO.Path]::GetFileName($old.OriginalFileName); Provider = $old.ProviderName; Class = $old.ClassName; Version = $old.Version; Date = $old.Date; Size = $size; Newest = $sorted[0].Version }
        }
    }
}

function Add-OldDriverPackageFindings {
    param([string]$Category)
    $old = @(Get-OldDriverPackages | Sort-Object Size -Descending)
    if (-not $old) { Add-Finding $Category OK 'Keine alten Treiberpakete im Treiberspeicher'; return }
    $sum = [double](($old | Measure-Object Size -Sum).Sum)
    $labels = @($old | ForEach-Object { '{0} · {1} {2} · Version {3} (aktuell {4}) · {5}' -f (Format-Bytes $_.Size), $_.Provider, $_.Class, $_.Version, $_.Newest, $_.Inf })
    Add-Finding $Category $(if ($sum -ge 2GB) { 'Warnung' } else { 'Info' }) "Alte Treiberpakete: $(Format-Bytes $sum) in $($old.Count) Paket(en)" -Items $labels -SelectLabels $labels -SelectAllByDefault -FixData $old `
        -Detail 'Windows behält nach Treiber-Updates die älteren Versionen im Treiberspeicher. Angeboten werden nur ältere Versionen, die von keinem Gerät benutzt werden – der aktuelle Treiber bleibt immer erhalten (Windows verweigert das Löschen benutzter Treiber zusätzlich).' `
        -FixLabel 'Ausgewählte alte Treiberpakete entfernen (pnputil)' -Fix {
        param($d, $pre)
        $ok = @(); $failed = @()
        foreach ($p in @($d)) {
            $null = & pnputil.exe /delete-driver $p.Inf 2>&1
            if ($LASTEXITCODE -eq 0) { $ok += $p } else { $failed += $p.Inf }
        }
        $freed = [double](($ok | Measure-Object Size -Sum).Sum)
        if ($ok) { Register-Change -Beschreibung "Alte Treiberpakete entfernt: $(($ok | ForEach-Object { $_.Inf }) -join ', ')" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis "$(Format-Bytes $freed) freigegeben" }
        $msg = "$(@($ok).Count) Treiberpaket(e) entfernt ($(Format-Bytes $freed))."
        if ($failed) { $msg += " Nicht entfernt (in Benutzung oder geschützt): $($failed -join ', ')." }
        $msg
    }
}

#endregion

function Add-RecoveryDataFindings {
    <# Alle Prüfungen zu alten Sicherungen und Wiederherstellungsdaten (Bereich »Speicherfresser«). #>
    param([string]$Category, [switch]$Tiefenanalyse)
    Invoke-Check $Category 'Wiederherstellungspunkte' { Add-RestorePointFindings -Category $Category }
    Invoke-Check $Category 'Reste von Windows-Upgrades' { Add-UpgradeLeftoverFindings -Category $Category }
    Invoke-Check $Category 'Alte Systemabbild-Sicherungen' { Add-OldImageBackupFindings -Category $Category }
    Invoke-Check $Category 'Dateiversionsverlauf' { Add-FileHistoryVersionFindings -Category $Category }
    if ($Tiefenanalyse) {
        Invoke-Check $Category 'Alte Treiberpakete (Treiberspeicher)' { Add-OldDriverPackageFindings -Category $Category }
    }
}
