<#
    Live-Monitor: laufende Messung von Prozessor, Arbeitsspeicher, Datenträger, Netzwerk und Temperatur mit den
    größten Verbrauchern sowie Aufzeichnung »Was bremst gerade?« mit Auswertung. Liest nur, ändert nichts.
    Eigenständig (ohne Funktionen des Kerns), damit es auch im Mess-Runspace des Programmfensters läuft.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

function Format-MonRate {
    param([double]$BytesPerSec)
    if ($BytesPerSec -ge 1MB) { return '{0:N1} MB/s' -f ($BytesPerSec / 1MB) }
    if ($BytesPerSec -ge 1KB) { return '{0:N0} KB/s' -f ($BytesPerSec / 1KB) }
    return '{0:N0} B/s' -f $BytesPerSec
}

function New-LiveMonitorState {
    @{ Prev = @{}; PrevTime = $null; Cores = [math]::Max(1, [Environment]::ProcessorCount); TempTime = [datetime]::MinValue; Temp = $null
        DiskNames = @{}; DiskNamesTime = [datetime]::MinValue }
}

function Get-MonDiskNames {
    <# Anzeigenamen je Datenträgernummer, z. B. »E: SanDisk Ultra (USB)«; alle 15 Sekunden bzw. bei unbekannter Nummer neu gelesen. #>
    param([hashtable]$State, [string[]]$Numbers)
    $now = [datetime]::UtcNow
    $missing = @($Numbers | Where-Object { -not $State.DiskNames.ContainsKey($_) })
    if (-not $missing -and ($now - $State.DiskNamesTime).TotalSeconds -lt 15) { return $State.DiskNames }
    $State.DiskNamesTime = $now
    $names = @{}
    try {
        foreach ($d in @(Get-Disk -ErrorAction Stop)) {
            $bus = "$($d.BusType)"
            $kind = if ($bus -in 'USB', 'SD', 'MMC', '1394') { $bus } else { 'intern' }
            $names["$($d.Number)"] = @{ Name = ("$($d.FriendlyName)".Trim() -replace '\s+', ' '); Kind = $kind }
        }
    } catch { }
    # Unbekannte Nummern merken, damit nicht bei jeder Messung neu gelesen wird
    foreach ($n in $Numbers) { if (-not $names.ContainsKey($n)) { $names[$n] = $null } }
    $State.DiskNames = $names
    return $names
}

function Get-LiveSample {
    <# Ein Messpunkt. $State hält die Prozessorzeiten der vorigen Messung (für die Prozessorlast je Programm). #>
    param([hashtable]$State)
    $now = [datetime]::UtcNow
    $cpu = $null; $disk = $null; $net = [double]0; $ramPct = $null; $ramUsed = [double]0; $ramTotal = [double]0
    try { $cpu = [double](Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop).PercentProcessorTime } catch { }
    $disks = @()
    try {
        $all = @(Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction Stop)
        $tot = $all | Where-Object { $_.Name -eq '_Total' } | Select-Object -First 1
        if ($tot) { $disk = [math]::Min(100, [math]::Max(0, 100 - [double]$tot.PercentIdleTime)) }
        # Einzelne Datenträger: Instanzname »1 E: F:« = Datenträgernummer und Laufwerksbuchstaben
        $per = @($all | Where-Object { $_.Name -ne '_Total' })
        $names = Get-MonDiskNames -State $State -Numbers @($per | ForEach-Object { ("$($_.Name)" -split ' ')[0] })
        foreach ($x in $per) {
            $parts = "$($x.Name)" -split ' '
            $num = $parts[0]
            $letters = @($parts | Select-Object -Skip 1 | Where-Object { $_ -match '^[A-Za-z]:$' })
            $info = $names[$num]
            $label = '{0}{1} ({2})' -f $(if ($letters) { ($letters -join ' ') + ' ' } else { '' }), $(if ($info) { $info.Name } else { "Datenträger $num" }), $(if ($info) { $info.Kind } else { '?' })
            $disks += [pscustomobject]@{ Key = $num; Name = $label; External = [bool]($info -and $info.Kind -ne 'intern')
                Active = [math]::Min(100, [math]::Max(0, 100 - [double]$x.PercentIdleTime)); Read = [double]$x.DiskReadBytesPersec; Write = [double]$x.DiskWriteBytesPersec }
        }
    } catch { }
    try { Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction Stop | ForEach-Object { $net += [double]$_.BytesTotalPersec } } catch { }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $ramTotal = [double]$os.TotalVisibleMemorySize * 1KB
        $ramUsed = $ramTotal - [double]$os.FreePhysicalMemory * 1KB
        if ($ramTotal -gt 0) { $ramPct = [math]::Round(100 * $ramUsed / $ramTotal, 1) }
    } catch { }
    # Temperatur nur alle 10 Sekunden (die Abfrage ist vergleichsweise langsam und oft nicht verfügbar)
    if (($now - $State.TempTime).TotalSeconds -ge 10) {
        $State.TempTime = $now
        $State.Temp = $null
        try {
            $z = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop | ForEach-Object { [double]$_.CurrentTemperature / 10 - 273.15 } | Where-Object { $_ -gt 5 -and $_ -lt 120 })
            if ($z) { $State.Temp = [math]::Round(($z | Measure-Object -Maximum).Maximum, 0) }
        } catch { }
    }
    # Prozesse: Prozessorlast aus der Differenz der Prozessorzeit, gruppiert nach Programmname
    $elapsed = if ($State.PrevTime) { ($now - $State.PrevTime).TotalMilliseconds } else { 0 }
    $cur = @{}; $byName = @{}
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        if ($p.Id -le 4) { continue }
        $t = 0.0; try { $t = $p.TotalProcessorTime.TotalMilliseconds } catch { }
        $cur[$p.Id] = $t
        $c = 0.0
        if ($elapsed -gt 0 -and $State.Prev.ContainsKey($p.Id)) { $c = [math]::Max(0, ($t - $State.Prev[$p.Id]) / $elapsed / $State.Cores * 100) }
        $n = $p.ProcessName
        if (-not $byName.ContainsKey($n)) { $byName[$n] = [pscustomobject]@{ Name = $n; Cpu = 0.0; Ram = [double]0; Count = 0 } }
        $e = $byName[$n]; $e.Cpu += $c; $e.Ram += [double]$p.WorkingSet64; $e.Count++
    }
    $State.Prev = $cur; $State.PrevTime = $now
    [pscustomobject]@{
        Time = [datetime]::Now; Cpu = $cpu; RamPct = $ramPct; RamUsed = $ramUsed; RamTotal = $ramTotal
        Disk = $disk; Net = $net; Temp = $State.Temp; Disks = @($disks | Sort-Object Key)
        Procs = @($byName.Values | Sort-Object Cpu, Ram -Descending | Select-Object -First 25)
        HasCpuDelta = ($elapsed -gt 0)
    }
}

function Get-LoadAnalysis {
    <# Auswertung einer Aufzeichnung: Durchschnitt/Spitze je Messgröße, Hauptverbraucher und Fazit. #>
    param($Samples)
    $s = @($Samples | Where-Object { $_.HasCpuDelta })
    if ($s.Count -lt 3) { return [pscustomobject]@{ Verdict = 'Zu wenige Messpunkte für eine Auswertung.'; Lines = @(); Causes = @() } }
    $avg = { param($n) $v = @($s | ForEach-Object { $_.$n } | Where-Object { $null -ne $_ }); if ($v) { [math]::Round(($v | Measure-Object -Average).Average, 0) } else { $null } }
    $max = { param($n) $v = @($s | ForEach-Object { $_.$n } | Where-Object { $null -ne $_ }); if ($v) { [math]::Round(($v | Measure-Object -Maximum).Maximum, 0) } else { $null } }
    $cpuA = & $avg 'Cpu'; $cpuM = & $max 'Cpu'; $ramA = & $avg 'RamPct'; $ramM = & $max 'RamPct'
    $diskA = & $avg 'Disk'; $diskM = & $max 'Disk'; $netA = & $avg 'Net'; $tempM = & $max 'Temp'
    # Hauptverbraucher: durchschnittliche Prozessorlast bzw. Arbeitsspeicher je Programm
    $agg = @{}
    foreach ($x in $s) { foreach ($p in $x.Procs) {
            if (-not $agg.ContainsKey($p.Name)) { $agg[$p.Name] = @{ Cpu = 0.0; Ram = [double]0 } }
            $agg[$p.Name].Cpu += $p.Cpu; $agg[$p.Name].Ram = [math]::Max($agg[$p.Name].Ram, $p.Ram) } }
    $topCpu = @($agg.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Name = $_.Key; Cpu = [math]::Round($_.Value.Cpu / $s.Count, 1); Ram = $_.Value.Ram } } | Where-Object { $_.Name -ne 'Idle' } | Sort-Object Cpu -Descending | Select-Object -First 5)
    $topRam = @($agg.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Name = $_.Key; Ram = $_.Value.Ram } } | Sort-Object Ram -Descending | Select-Object -First 5)

    $causes = @()
    if ($cpuA -ge 70) { $causes += "Prozessor dauerhaft stark ausgelastet (Ø $cpuA %)$(if ($topCpu) { " – vor allem durch $($topCpu[0].Name) (Ø $($topCpu[0].Cpu) %)" })" }
    elseif ($cpuM -ge 95 -and $cpuA -ge 40) { $causes += "Prozessor zeitweise voll ausgelastet (Spitze $cpuM %)" }
    if ($ramA -ge 85) { $causes += "Arbeitsspeicher fast voll (Ø $ramA %) – Windows lagert auf den Datenträger aus$(if ($topRam) { "; größter Verbraucher: $($topRam[0].Name) ($([math]::Round($topRam[0].Ram / 1MB)) MB)" })" }
    # Einzelne Datenträger: Durchschnitt der Aktivität sowie Lesen/Schreiben je Datenträger
    $dagg = @{}
    foreach ($x in $s) { foreach ($dk in @($x.Disks)) {
            if (-not $dagg.ContainsKey($dk.Key)) { $dagg[$dk.Key] = @{ Name = $dk.Name; External = $dk.External; Act = 0.0; Read = 0.0; Write = 0.0; N = 0 } }
            $e = $dagg[$dk.Key]; $e.Act += $dk.Active; $e.Read += $dk.Read; $e.Write += $dk.Write; $e.N++ } }
    $perDisk = @($dagg.Values | ForEach-Object { [pscustomobject]@{ Name = $_.Name; External = $_.External; Act = [math]::Round($_.Act / $_.N, 0); Read = $_.Read / $_.N; Write = $_.Write / $_.N } } | Sort-Object Act -Descending)
    $busy = @($perDisk | Where-Object { $_.Act -ge 60 })
    if ($busy) {
        foreach ($b in $busy) { $causes += "$(if ($b.External) { 'Externer Datenträger' } else { 'Datenträger' }) »$($b.Name)« dauerhaft stark beschäftigt (Ø $($b.Act) % aktiv)$(if ($b.External) { ' – z. B. Kopieren, Sicherung oder ein langsamer USB-Anschluss' } else { ' – typisch bei HDD, Updates, Virenscan oder Indizierung' })" }
    } elseif ($diskA -ge 60) { $causes += "Datenträger dauerhaft stark beschäftigt (Ø $diskA % aktiv) – typisch bei HDD, Updates, Virenscan oder Indizierung" }
    if ($tempM -ge 90) { $causes += "Sehr hohe Temperatur ($tempM °C) – der Prozessor drosselt vermutlich" }
    $verdict = if ($causes) { 'Was gerade bremst: ' + ($causes -join '; ') + '.' } else { 'Keine auffällige Last – das System hatte während der Aufzeichnung genug Reserven.' }

    $lines = @(
        "Prozessor:        Ø $cpuA %, Spitze $cpuM %"
        "Arbeitsspeicher:  Ø $ramA %, Spitze $ramM %"
        "Datenträger:      Ø $diskA % aktiv, Spitze $diskM %"
        "Netzwerk:         Ø $(Format-MonRate ([double]$netA))"
    )
    if ($null -ne $tempM) { $lines += "Temperatur:       höchstens $tempM °C" }
    if ($perDisk) {
        $lines += 'Datenträger einzeln (Ø aktiv, lesen, schreiben):'
        $lines += @($perDisk | ForEach-Object { '  {0,4} %  {1,10}  {2,10}  {3}' -f $_.Act, (Format-MonRate $_.Read), (Format-MonRate $_.Write), $_.Name })
    }
    $lines += ''
    $lines += 'Größte Prozessor-Verbraucher (Durchschnitt):'
    $lines += @($topCpu | ForEach-Object { '  {0,6:N1} %  {1}' -f $_.Cpu, $_.Name })
    $lines += 'Größte Arbeitsspeicher-Verbraucher:'
    $lines += @($topRam | ForEach-Object { '  {0,6:N0} MB  {1}' -f ($_.Ram / 1MB), $_.Name })
    [pscustomobject]@{ Verdict = $verdict; Lines = $lines; Causes = $causes; Samples = $s.Count }
}

function Measure-SystemLoad {
    <# Zeichnet die Systemlast über die angegebene Dauer auf (ein Messpunkt pro Sekunde) und wertet sie aus. #>
    param([int]$Seconds = 60)
    $state = New-LiveMonitorState
    $samples = New-Object System.Collections.Generic.List[object]
    $end = [datetime]::UtcNow.AddSeconds($Seconds)
    $i = 0
    while ([datetime]::UtcNow -lt $end) {
        $t0 = [datetime]::UtcNow
        $samples.Add((Get-LiveSample -State $state))
        $i++
        if ($i % 10 -eq 0) { Write-Host ("     … {0} von {1} Sekunden aufgezeichnet" -f $i, $Seconds) -ForegroundColor DarkGray }
        $wait = 1000 - ([datetime]::UtcNow - $t0).TotalMilliseconds
        if ($wait -gt 0) { Start-Sleep -Milliseconds ([int]$wait) }
    }
    Get-LoadAnalysis $samples.ToArray()
}

function Add-LoadRecordingToolFinding {
    param([string]$Category)
    Add-Finding $Category Info 'Was bremst gerade? (Live-Aufzeichnung)' -Silent -Repeatable `
        -Detail 'Zeichnet 60 Sekunden lang Prozessor, Arbeitsspeicher, Datenträger, Netzwerk und Temperatur auf und nennt die größten Verbraucher. Am besten starten, während das Gerät gerade langsam ist. Im Programmfenster zeigt der Bereich »Live-Monitor« die Werte zusätzlich laufend an.' `
        -FixLabel '60 Sekunden aufzeichnen und auswerten' -Fix {
        param($d)
        Write-Host '     Aufzeichnung läuft 60 Sekunden – das Gerät dabei normal weiterbenutzen …' -ForegroundColor Gray
        $a = Measure-SystemLoad -Seconds 60
        $sev = if ($a.Causes) { 'Warnung' } else { 'OK' }
        Remove-FindingByKey 'Lastaufzeichnung'
        Add-Finding 'Leistung' $sev "Live-Aufzeichnung: $(if ($a.Causes) { "$(@($a.Causes).Count) Bremse(n) gefunden" } else { 'keine auffällige Last' })" -Key 'Lastaufzeichnung' -Detail $a.Verdict -Items $a.Lines
        $a.Verdict
    }
}
