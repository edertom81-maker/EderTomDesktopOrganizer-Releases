<#
    Tiefere Analysen: Bluescreen-Ursachen, Speicherplatzbelegung, Akkuverlauf, Speichertest-Ergebnisse.
    Teil von LaptopDiagnose – Copyright 2026 by Eder Tom
#>

#region ---------- Bluescreens ----------

# Häufige Stoppcodes mit Name, wahrscheinlicher Ursache und Empfehlung
$Script:BugcheckCodes = @{
    0x0A  = @('IRQL_NOT_LESS_OR_EQUAL', 'Treiber', 'Treiber aktualisieren, insbesondere kürzlich installierte.')
    0x19  = @('BAD_POOL_HEADER', 'Treiber', 'Treiber und Virenschutz aktualisieren.')
    0x1A  = @('MEMORY_MANAGEMENT', 'Arbeitsspeicher', 'Arbeitsspeicher-Test durchführen (Bereich »Reparatur-Werkzeuge«).')
    0x1E  = @('KMODE_EXCEPTION_NOT_HANDLED', 'Treiber', 'Treiber aktualisieren.')
    0x24  = @('NTFS_FILE_SYSTEM', 'Datenträger', 'Daten sichern, Dateisystem prüfen.')
    0x3B  = @('SYSTEM_SERVICE_EXCEPTION', 'Treiber (oft Grafik)', 'Grafik- und Chipsatztreiber aktualisieren.')
    0x50  = @('PAGE_FAULT_IN_NONPAGED_AREA', 'Treiber oder Arbeitsspeicher', 'Treiber aktualisieren und Arbeitsspeicher testen.')
    0x7A  = @('KERNEL_DATA_INPAGE_ERROR', 'Datenträger', 'Daten sichern, SSD/Festplatte prüfen.')
    0x7E  = @('SYSTEM_THREAD_EXCEPTION_NOT_HANDLED', 'Treiber', 'Treiber aktualisieren.')
    0x7F  = @('UNEXPECTED_KERNEL_MODE_TRAP', 'Hardware oder Überhitzung', 'Lüfter reinigen, Arbeitsspeicher testen.')
    0x80  = @('NMI_HARDWARE_FAILURE', 'Hardware', 'Arbeitsspeicher testen, ggf. Service kontaktieren.')
    0x9F  = @('DRIVER_POWER_STATE_FAILURE', 'Treiber beim Standby/Energiesparen', 'Treiber (v. a. WLAN, Grafik, Chipsatz) und BIOS aktualisieren.')
    0xBE  = @('ATTEMPTED_WRITE_TO_READONLY_MEMORY', 'Treiber', 'Treiber aktualisieren.')
    0xC2  = @('BAD_POOL_CALLER', 'Treiber', 'Treiber aktualisieren.')
    0xC5  = @('DRIVER_CORRUPTED_EXPOOL', 'Treiber', 'Treiber aktualisieren.')
    0xD1  = @('DRIVER_IRQL_NOT_LESS_OR_EQUAL', 'Treiber (oft Netzwerk/WLAN)', 'Netzwerk- und WLAN-Treiber aktualisieren.')
    0xEF  = @('CRITICAL_PROCESS_DIED', 'Systemdateien oder Datenträger', 'Systemdateien prüfen (SFC/DISM), Datenträger prüfen.')
    0xF4  = @('CRITICAL_OBJECT_TERMINATION', 'Datenträger', 'Daten sichern, SSD/Festplatte prüfen.')
    0x101 = @('CLOCK_WATCHDOG_TIMEOUT', 'Prozessor/BIOS', 'BIOS aktualisieren, Übertaktung entfernen.')
    0x116 = @('VIDEO_TDR_FAILURE', 'Grafiktreiber', 'Grafiktreiber aktualisieren bzw. neu installieren.')
    0x117 = @('VIDEO_TDR_TIMEOUT_DETECTED', 'Grafiktreiber', 'Grafiktreiber aktualisieren.')
    0x124 = @('WHEA_UNCORRECTABLE_ERROR', 'Hardware (CPU, RAM, Überhitzung)', 'Lüfter reinigen, Belastungstest und Speichertest durchführen, BIOS aktualisieren.')
    0x133 = @('DPC_WATCHDOG_VIOLATION', 'Treiber oder SSD-Firmware', 'Speicher- und Chipsatztreiber sowie SSD-Firmware aktualisieren.')
    0x139 = @('KERNEL_SECURITY_CHECK_FAILURE', 'Treiber oder Arbeitsspeicher', 'Treiber aktualisieren, Arbeitsspeicher testen.')
    0x13A = @('KERNEL_MODE_HEAP_CORRUPTION', 'Treiber', 'Treiber aktualisieren.')
    0x154 = @('UNEXPECTED_STORE_EXCEPTION', 'Datenträger oder Arbeitsspeicher', 'SSD prüfen, Arbeitsspeicher testen.')
    0x1A8 = @('BUGCODE_ID_DRIVER', 'Treiber', 'Treiber aktualisieren.')
}

function Get-BugcheckEvents {
    param([int]$Days = 30)
    $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1001; StartTime = (Get-Date).AddDays(-$Days) } -MaxEvents 200 -ErrorAction SilentlyContinue |
            Where-Object { $_.ProviderName -match 'WER-SystemErrorReporting' })
    foreach ($ev in $events) {
        $code = $null; $dump = $null
        if ($ev.Message -match '0x([0-9a-fA-F]{8})\s*\(') { $code = [Convert]::ToInt32($Matches[1], 16) }
        if ($ev.Message -match '([A-Za-z]:\\[^\s"]+\.dmp)') { $dump = $Matches[1] }
        $info = if ($null -ne $code -and $Script:BugcheckCodes.ContainsKey($code)) { $Script:BugcheckCodes[$code] } else { @('Unbekannter Stoppcode', 'unklar', 'Treiber und Windows aktualisieren.') }
        [pscustomobject]@{
            Zeit    = $ev.TimeCreated
            Code    = $code
            CodeHex = $(if ($null -ne $code) { '0x{0:X}' -f $code } else { '?' })
            Name    = $info[0]
            Ursache = $info[1]
            Tipp    = $info[2]
            Dump    = $dump
        }
    }
}

function Find-Debugger {
    $candidates = @(
        "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\cdb.exe"
        "$env:ProgramFiles\Windows Kits\10\Debuggers\x64\cdb.exe"
        "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\arm64\cdb.exe"
    )
    return $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
}

function Invoke-DumpAnalysis {
    <# Wertet die letzten Absturzabbilder mit dem Windows-Debugger aus und nennt den verursachenden Treiber. #>
    param([string[]]$Dumps)
    $cdb = Find-Debugger
    if (-not $cdb) { throw 'Die »Debugging Tools for Windows« sind nicht installiert.' }
    $symbols = 'srv*' + (Join-Path $env:TEMP 'LaptopDiagnoseSymbols') + '*https://msdl.microsoft.com/download/symbols'
    $results = foreach ($d in $Dumps | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 3) {
        Write-Host "     Analysiere $([IO.Path]::GetFileName($d)) …" -ForegroundColor Gray
        $out = & $cdb -z $d -y $symbols -c '!analyze -v; q' 2>&1 | Out-String
        $module = if ($out -match '(?m)^\s*MODULE_NAME:\s*(\S+)') { $Matches[1] }
        $image = if ($out -match '(?m)^\s*IMAGE_NAME:\s*(\S+)') { $Matches[1] }
        $bucket = if ($out -match '(?m)^\s*FAILURE_BUCKET_ID:\s*(\S+)') { $Matches[1] }
        '{0}: Verursacher {1}{2}' -f [IO.Path]::GetFileName($d), $(if ($image) { $image } elseif ($module) { $module } else { 'nicht ermittelbar' }), $(if ($bucket) { " ($bucket)" })
    }
    if (-not $results) { return 'Keine Absturzabbilder gefunden.' }
    return ($results -join ' | ')
}

function Add-BugcheckFindings {
    param([string]$Category)
    $all = @(Get-BugcheckEvents -Days 30)
    $recent = @($all | Where-Object { $_.Zeit -gt (Get-Date).AddDays(-7) })
    Set-Metric 'Bluescreens' $recent.Count
    if (-not $all) { return }
    $top = $all | Group-Object Name | Sort-Object Count -Descending | Select-Object -First 1
    $main = $top.Group[0]
    $items = @($all | Select-Object -First 8 | ForEach-Object { '{0:dd.MM. HH:mm} – {1} {2}: {3}' -f $_.Zeit, $_.CodeHex, $_.Name, $_.Ursache })
    $sev = if ($recent) { 'Kritisch' } else { 'Warnung' }
    $dumps = @($all | Where-Object { $_.Dump } | ForEach-Object { $_.Dump } | Select-Object -Unique)
    $minidumps = @(Get-ChildItem -LiteralPath (Join-Path $env:windir 'Minidump') -Filter '*.dmp' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | ForEach-Object { $_.FullName })
    if ($minidumps) { $dumps = @($minidumps + $dumps | Select-Object -Unique) }
    $params = @{
        Category = $Category; Severity = $sev
        Title    = "$($all.Count) Bluescreen(s) in den letzten 30 Tagen – häufigste Ursache: $($main.Ursache)"
        Detail   = "Häufigster Stoppcode: $($main.Name) ($($top.Count)×). Empfehlung: $($main.Tipp)"
        Items    = $items
    }
    if ((Find-Debugger) -and $dumps) {
        $params.FixLabel = 'Absturzabbilder mit dem Windows-Debugger auswerten (lädt Symbole, einige Minuten)'
        $params.FixData = $dumps
        $params.Fix = { param($d) Invoke-DumpAnalysis $d }
    }
    Add-Finding @params
}

function Add-MemoryTestFinding {
    param([string]$Category)
    $ev = Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-MemoryDiagnostics-Results' } -MaxEvents 1 -ErrorAction SilentlyContinue
    if (-not $ev) { return }
    if ($ev.Id -eq 1202) {
        Add-Finding $Category Kritisch ('Der Arbeitsspeicher-Test vom {0:dd.MM.yyyy} hat Fehler gefunden' -f $ev.TimeCreated) `
            -Detail 'Defekter Arbeitsspeicher führt zu Abstürzen und Datenfehlern. RAM-Riegel prüfen bzw. tauschen lassen.'
    } elseif ($ev.Id -eq 1201) {
        Add-Finding $Category OK ('Arbeitsspeicher-Test vom {0:dd.MM.yyyy}: keine Fehler' -f $ev.TimeCreated)
    }
}

#endregion

#region ---------- Programm-Hänger ----------

function Get-ToolSessions {
    <# Zeiträume, in denen LaptopDiagnose lief (aus den Sitzungsprotokollen im Berichtsordner). #>
    $dirs = @((Join-Path $env:LOCALAPPDATA 'LaptopDiagnose\Protokolle'), $BerichtOrdner)
    $sessions = foreach ($f in Get-ChildItem -LiteralPath $dirs -Filter 'Protokoll_*.txt' -File -ErrorAction SilentlyContinue) {
        if ($f.BaseName -match '(\d{8}_\d{6})$') {
            $start = [datetime]::ParseExact($Matches[1], 'yyyyMMdd_HHmmss', $null)
            [pscustomobject]@{ Start = $start; Ende = $f.LastWriteTime }
        }
    }
    return @($sessions)
}

function Add-HangFindings {
    param([string]$Category, [int]$Days = 7)
    $since = (Get-Date).AddDays(-$Days)
    $hangs = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'Application Hang'; Id = 1002; StartTime = $since } -ErrorAction SilentlyContinue)
    Set-Metric 'ProgrammHaenger' $hangs.Count
    if ($hangs) {
        $byApp = $hangs | Group-Object { "$($_.Properties[0].Value)" } | Sort-Object Count -Descending
        $sessions = @(Get-ToolSessions | Where-Object { $_.Ende -gt $since })
        $near = @($hangs | Where-Object { $t = $_.TimeCreated; $sessions | Where-Object { $t -ge $_.Start -and $t -le $_.Ende.AddMinutes(30) } })
        $detail = if (-not $sessions) {
            'Diese Programme reagierten zeitweise nicht mehr. Betroffene Programme aktualisieren; bei Explorer-Hängern Autostarts und Kontextmenü-Erweiterungen prüfen.'
        } elseif ($near) {
            "$($near.Count) von $($hangs.Count) Hängern traten während oder bis 30 Minuten nach einer Nutzung der Laptop-Diagnose auf ($($sessions.Count) Sitzungen). Bitte die Zeitpunkte unter »Details« prüfen."
        } else {
            "Keiner der Hänger trat während oder bis 30 Minuten nach einer Nutzung der Laptop-Diagnose auf ($($sessions.Count) Sitzungen)."
        }
        $items = @($byApp | Select-Object -First 8 | ForEach-Object { '{0} – {1}×' -f $_.Name, $_.Count })
        $items += @($hangs | Sort-Object TimeCreated -Descending | Select-Object -First 10 | ForEach-Object {
                $t = $_.TimeCreated
                $mark = if ($sessions | Where-Object { $t -ge $_.Start -and $t -le $_.Ende.AddMinutes(30) }) { '  ← nach Laptop-Diagnose' } else { '' }
                '{0:dd.MM. HH:mm}  {1}{2}' -f $t, $_.Properties[0].Value, $mark
            })
        $sev = if ($hangs.Count -ge 3) { 'Warnung' } else { 'Info' }
        Add-Finding $Category $sev "$($hangs.Count) Programm-Hänger in den letzten $Days Tagen" -Detail $detail -Items $items
    } else {
        Add-Finding $Category OK "Keine Programm-Hänger in den letzten $Days Tagen protokolliert"
    }

    $low = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Resource-Exhaustion-Detector'; Id = 2004; StartTime = $since } -ErrorAction SilentlyContinue)
    if ($low) {
        $users = @{}
        foreach ($e in $low) {
            foreach ($m in [regex]::Matches("$($e.Message)", '([^\s,:]+\.exe)\s*\(\d+\)[^\d]*(\d{6,})')) {
                $n = $m.Groups[1].Value; $b = [double]$m.Groups[2].Value
                if (-not $users.ContainsKey($n) -or $users[$n] -lt $b) { $users[$n] = $b }
            }
        }
        $top = @($users.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 6 | ForEach-Object { '{0} – bis {1}' -f $_.Key, (Format-Bytes $_.Value) })
        Add-Finding $Category Warnung "Windows hatte $($low.Count)× zu wenig Arbeitsspeicher" `
            -Detail 'Speicherengpässe führen zu Hängern und Abstürzen. Die größten Verbraucher schließen oder aktualisieren; bei wenig RAM ggf. aufrüsten.' -Items $top
    }
}

#endregion

#region ---------- Speicherplatzbelegung ----------

function Get-DirectorySizeFast {
    <# Summiert Dateigrößen ohne Verknüpfungspunkte und ohne nur in der Cloud liegende Dateien (OneDrive). #>
    param([string]$Path)
    $total = [long]0
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push($Path)
    $skip = [IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Offline
    while ($stack.Count) {
        $dir = $stack.Pop()
        try {
            foreach ($e in (New-Object IO.DirectoryInfo $dir).EnumerateFileSystemInfos()) {
                if ([int]$e.Attributes -band ([int]$skip -bor 0x400000 -bor 0x40000)) { continue }
                if ($e -is [IO.DirectoryInfo]) { $stack.Push($e.FullName) } else { $total += $e.Length }
            }
        } catch { }
    }
    return $total
}

function Get-StorageBreakdown {
    param([string]$Path, [int]$Top = 12, [switch]$IncludeSystemFiles)
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($d in Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue) {
        if ([int]$d.Attributes -band [int][IO.FileAttributes]::ReparsePoint) { continue }
        $entries.Add([pscustomobject]@{ Label = $d.Name; Value = [double](Get-DirectorySizeFast $d.FullName) })
    }
    if ($IncludeSystemFiles) {
        foreach ($f in 'pagefile.sys', 'hiberfil.sys', 'swapfile.sys') {
            $item = Get-Item -LiteralPath (Join-Path $Path $f) -Force -ErrorAction SilentlyContinue
            if ($item) { $entries.Add([pscustomobject]@{ Label = "$f (System)"; Value = [double]$item.Length }) }
        }
        try {
            $vol = Get-CimInstance Win32_Volume -Filter "DriveLetter='$($Path.TrimEnd('\'))'" -ErrorAction Stop
            $shadow = Get-CimInstance Win32_ShadowStorage -ErrorAction Stop | Where-Object { $_.Volume -match [regex]::Escape($vol.DeviceID) }
            if ($shadow -and $shadow.UsedSpace) { $entries.Add([pscustomobject]@{ Label = 'Wiederherstellungspunkte'; Value = [double]$shadow.UsedSpace }) }
        } catch { }
    }
    return @($entries | Where-Object { $_.Value -gt 0 } | Sort-Object Value -Descending | Select-Object -First $Top |
            ForEach-Object { [pscustomobject]@{ Label = $_.Label; Value = $_.Value; Text = Format-Bytes $_.Value } })
}

function Add-StorageBreakdownFindings {
    param([string]$Category)
    $sys = $env:SystemDrive + '\'
    $chart = @(Get-StorageBreakdown -Path $sys -IncludeSystemFiles)
    if ($chart) {
        Add-Finding $Category Info "Speicherbelegung von $env:SystemDrive – größte Bereiche" -Chart $chart -ChartStyle Kacheln `
            -Detail 'Hinweis: Windows nutzt Hardlinks (WinSxS), daher kann die Summe größer erscheinen als der belegte Platz.'
    }
    $user = @(Get-StorageBreakdown -Path $env:USERPROFILE)
    if ($user) {
        Add-Finding $Category Info 'Benutzerordner – größte Bereiche' -Chart $user -ChartStyle Kacheln `
            -Detail 'Nur lokal gespeicherte Dateien (reine OneDrive-Cloud-Dateien werden nicht mitgezählt).' `
            -FixLabel 'Speicher-Einstellungen von Windows öffnen' -Fix { param($d) Start-Process 'ms-settings:storagesense'; 'Speicher-Einstellungen geöffnet.' }
    }
}

#endregion

#region ---------- Akku-Details ----------

function Add-BatteryHistoryFindings {
    <# Nutzt den Kapazitätsverlauf aus dem Windows-Akkubericht (XML). #>
    param([string]$Category, [xml]$Report)
    $hist = @($Report.BatteryReport.History.HistoryEntry)
    $points = foreach ($h in $hist) {
        $full = [double]"$($h.FullChargeCapacity)"
        $design = [double]"$($h.DesignCapacity)"
        $date = "$($h.LocalStartDate)"
        if ($full -gt 0 -and $design -gt 0 -and $date) { [pscustomobject]@{ Zeit = [datetime]$date; Health = [math]::Round($full / $design * 100, 1) } }
    }
    $points = @($points | Sort-Object Zeit)
    if ($points.Count -lt 2) { return }
    # Bis zu 8 gleichmäßig verteilte Messpunkte für das Diagramm
    $step = [math]::Max(1, [math]::Floor($points.Count / 8))
    $sample = @(for ($i = 0; $i -lt $points.Count; $i += $step) { $points[$i] })
    if ($sample[-1] -ne $points[-1]) { $sample += $points[-1] }
    $chart = @($sample | Select-Object -Last 8 | ForEach-Object { [pscustomobject]@{ Label = $_.Zeit.ToString('MM/yyyy'); Value = $_.Health; Text = "$($_.Health) %" } })
    $days = ($points[-1].Zeit - $points[0].Zeit).TotalDays
    $detail = 'Verlauf der vollen Ladekapazität laut Windows-Akkubericht.'
    $sev = 'Info'
    if ($days -ge 30) {
        $perMonth = [math]::Round(($points[0].Health - $points[-1].Health) / $days * 30, 2)
        if ($perMonth -gt 0) {
            $detail = "Der Akku verliert durchschnittlich ca. $perMonth Prozentpunkte Kapazität pro Monat (Zeitraum: $([math]::Round($days)) Tage)."
            if ($perMonth -ge 1.5) { $sev = 'Warnung'; $detail += ' Das ist überdurchschnittlich – Ladegrenze (z. B. 80 %) im Hersteller-Tool aktivieren und Hitze vermeiden.' }
            $remaining = $points[-1].Health - 60
            if ($remaining -gt 0) { $detail += " Bei gleichbleibendem Verlauf wird die 60-%-Schwelle in etwa $([math]::Round($remaining / $perMonth)) Monaten erreicht." }
        }
    }
    Add-Finding $Category $sev 'Akku-Kapazitätsverlauf' -Detail $detail -Chart $chart
}

function Get-VendorBatteryTool {
    <# Hersteller-App, in der sich die Ladegrenze einstellen lässt. #>
    $vendor = "$((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).Manufacturer)"
    $apps = @(
        @{ Match = 'ASUS'; Package = '*ASUSPCAssistant*'; Name = 'MyASUS'; Path = 'MyASUS › Gerätefunktionen › Energie & Leistung › Akkupflegemodus (Battery Health Charging) › »Ausgeglichen« (80 %)' }
        @{ Match = 'LENOVO'; Package = '*LenovoCompanion*'; Name = 'Lenovo Vantage'; Path = 'Lenovo Vantage › Gerät › Stromversorgung › Ladeschwelle' }
        @{ Match = 'HP|Hewlett'; Package = '*HPSupportAssistant*'; Name = 'HP Support Assistant'; Path = 'BIOS bzw. HP Support Assistant › Akku › Adaptive Battery Optimizer' }
        @{ Match = 'Dell'; Package = '*DellPowerManager*'; Name = 'Dell Power Manager'; Path = 'Dell Power Manager › Akkueinstellungen › »Hauptsächlich Netzbetrieb«' }
    )
    foreach ($a in $apps) {
        if ($vendor -notmatch $a.Match) { continue }
        $pkg = Get-AppxPackage -Name $a.Package -ErrorAction SilentlyContinue | Select-Object -First 1
        return [pscustomobject]@{ Vendor = $vendor; Name = $a.Name; Path = $a.Path; Family = $(if ($pkg) { $pkg.PackageFamilyName }) }
    }
    return [pscustomobject]@{ Vendor = $vendor; Name = $null; Path = 'Hersteller-App bzw. BIOS-Einstellungen des Laptops'; Family = $null }
}

function Add-ChargeLimitFindings {
    <#
        Erkennt, ob eine Ladegrenze (z. B. 80 %) aktiv ist: Am Netzteil, aber nicht ladend, bleibt der Akku dann
        unter 100 % stehen. Die Hersteller speichern die Einstellung nicht einheitlich, daher wird das Verhalten ausgewertet.
    #>
    param([string]$Category, [double]$Health = 0)
    $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $b) { return }
    $charge = [int]$b.EstimatedChargeRemaining
    $ws = Get-CimInstance -Namespace root/wmi -ClassName BatteryStatus -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($ws) { $online = [bool]$ws.PowerOnline; $charging = [bool]$ws.Charging }
    else { $online = [int]$b.BatteryStatus -ne 1; $charging = [int]$b.BatteryStatus -in 6, 7, 8, 9 }
    $tool = Get-VendorBatteryTool
    $toolText = if ($tool.Name) { "Einstellen in: $($tool.Path)." } else { "Einstellen in der $($tool.Path) (Stichwort »Ladegrenze« bzw. »Battery Health Charging«)." }
    $fixLabel = $null; $fix = $null
    if ($tool.Family) {
        $fixLabel = "$($tool.Name) öffnen (Ladegrenze einstellen)"
        $fix = { param($d) Start-Process -FilePath 'explorer.exe' -ArgumentList "shell:AppsFolder\$($d.Family)!App"; "$($d.Name) geöffnet." }
    } elseif ($tool.Name) {
        $fixLabel = "$($tool.Name) im Microsoft Store suchen"
        $fix = { param($d) Start-Process ("ms-windows-store://search/?query=$([uri]::EscapeDataString($d.Name))"); 'Microsoft Store geöffnet.' }
    }
    if ($online -and -not $charging -and $charge -ge 50 -and $charge -le 85) {
        Add-Finding $Category OK "Ladegrenze aktiv: Der Akku wird nur bis ca. $charge % geladen" -Detail 'Das schont den Akku deutlich, vor allem wenn der Laptop meist am Netzteil hängt.'
    } elseif ($online -and -not $charging -and $charge -ge 95) {
        $sev = if ($Health -gt 0 -and $Health -lt 85) { 'Warnung' } else { 'Info' }
        Add-Finding $Category $sev 'Keine Ladegrenze: Der Akku wird am Netzteil immer auf 100 % geladen' `
            -Detail "Dauerhaft volle Ladung bei Wärme lässt den Akku schneller altern. Wer meist am Netzteil arbeitet, sollte die Ladegrenze auf 80 % stellen. $toolText" `
            -FixLabel $fixLabel -FixData $tool -Fix $fix
    } else {
        $why = if (-not $online) { 'Der Laptop läuft gerade im Akkubetrieb.' } else { 'Der Akku lädt gerade noch.' }
        Add-Finding $Category Info 'Ladegrenze: derzeit nicht feststellbar' `
            -Detail "$why Zum Prüfen das Netzteil anschließen und warten, bis das Laden endet. Eine Ladegrenze von 80 % schont den Akku. $toolText" `
            -FixLabel $fixLabel -FixData $tool -Fix $fix
    }
}

function Add-StandbyFindings {
    param([string]$Category)
    $a = (& powercfg.exe /a 2>$null | Out-String)
    $modern = $a -match 'S0'
    $text = if ($modern) { 'Dieser Laptop nutzt »Modern Standby« (S0): Im Standby bleibt er teilweise aktiv – erhöhter Verbrauch im zugeklappten Zustand ist möglich.' } else { 'Dieser Laptop nutzt den klassischen Standby (S3).' }
    Add-Finding $Category Info 'Standby und Akkuverbrauch nach Apps' -Detail $text `
        -FixLabel 'Akkunutzung nach Apps in den Windows-Einstellungen öffnen' `
        -Fix { param($d) Start-Process 'ms-settings:batterysaver-usagedetails'; 'Einstellungen geöffnet.' }
}

#endregion
