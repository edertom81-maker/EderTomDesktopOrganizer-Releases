<#
    Autostart vollständig: geplante Aufgaben, die bei Anmeldung/Start laufen, und automatisch startende Dienste
    von Fremdherstellern. Deaktivieren nur nach Auswahl, rückgängig über »Änderungen«.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

# Virenschutz, Sicherheits- und Treiberkomponenten bleiben unangetastet
$Script:AutostartKeepPattern = 'Defender|Bitdefender|Kaspersky|ESET|Norton|Symantec|McAfee|Avast|AVG|Avira|Sophos|Malwarebytes|Trend ?Micro|F-Secure|G DATA|Panda|Webroot|Intel|Realtek|NVIDIA Display|AMD External|Synaptics|ELAN|Dolby|Waves|Conexant|Logitech|Razer Synapse|ASUS (System|Optimization|Link)|ArmouryCrate|MyASUS|Lenovo Vantage|Dell (SupportAssist|Optimizer)|HP (Support|Insights)|Thunderbolt|Bluetooth|Wireless|TPM|BitLocker|PC Repair Pro|LaptopDiagnose|EderTom'

function Get-StartupScheduledTasks {
    <# Aktive Aufgaben von Fremdherstellern, die bei der Anmeldung oder beim Systemstart laufen. #>
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return @() }
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Disabled' -and $_.TaskPath -notlike '\Microsoft\*' -and $_.TaskPath -notlike '\EderTom\*' })) {
        $trig = @($t.Triggers | Where-Object { $_.CimClass.CimClassName -in 'MSFT_TaskLogonTrigger', 'MSFT_TaskBootTrigger' })
        if (-not $trig) { continue }
        $exe = (@($t.Actions) | Where-Object { $_.Execute } | Select-Object -First 1).Execute
        $text = "$($t.TaskName) $($t.TaskPath) $($t.Author) $exe"
        if ($text -match $Script:AutostartKeepPattern) { continue }
        [pscustomobject]@{
            Name = $t.TaskName; Path = $t.TaskPath; Exe = [Environment]::ExpandEnvironmentVariables("$exe").Trim('"')
            When = $(if ($trig | Where-Object { $_.CimClass.CimClassName -eq 'MSFT_TaskBootTrigger' }) { 'beim Systemstart' } else { 'bei der Anmeldung' })
            Author = "$($t.Author)"
        }
    }
}

function Get-ThirdPartyAutoServices {
    <# Automatisch startende Dienste, deren Programm nicht zu Windows gehört. #>
    foreach ($s in @(Get-CimInstance Win32_Service -Filter "StartMode='Auto'" -ErrorAction SilentlyContinue)) {
        $path = "$($s.PathName)"
        if (-not $path -or $path -match '(?i)\\Windows\\(System32|SysWOW64|servicing|WinSxS)\\|\\Windows Defender|\\Microsoft\\') { continue }
        if ("$($s.Name) $($s.DisplayName) $path" -match $Script:AutostartKeepPattern) { continue }
        $exe = if ($path -match '^"([^"]+)"') { $Matches[1] } else { ($path -split '\s+')[0] }
        $company = ''
        try { $company = (Get-Item -LiteralPath $exe -ErrorAction Stop).VersionInfo.CompanyName } catch { }
        if ($company -match '^Microsoft') { continue }
        [pscustomobject]@{ Name = $s.Name; Display = $s.DisplayName; State = $s.State; Exe = $exe; Company = "$company" }
    }
}

function Disable-StartupTasks {
    param($Tasks)
    $done = @(); $failed = @(); $undo = @()
    foreach ($t in @($Tasks)) {
        try { $null = Disable-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction Stop; $done += $t.Name; $undo += @{ Name = $t.Name; Path = $t.Path } }
        catch { $failed += $t.Name }
    }
    if ($done) { Register-Change -Beschreibung "Geplante Aufgaben deaktiviert: $($done -join ', ')" -Typ 'Aufgabe' -Daten @{ Aufgaben = $undo } }
    $msg = "$(@($done).Count) Aufgabe(n) deaktiviert. Rückgängig über »Änderungen«."
    if ($failed) { $msg += " Nicht möglich: $($failed -join ', ')." }
    $msg
}

function Set-ServicesManual {
    <# Dienste auf »Manuell« stellen – sie starten dann nur noch, wenn ein Programm sie braucht. #>
    param($Services)
    $done = @(); $failed = @(); $undo = @()
    foreach ($s in @($Services)) {
        try {
            $delayed = $false
            try { $delayed = [bool](Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)" -Name DelayedAutostart -ErrorAction Stop).DelayedAutostart } catch { }
            Set-Service -Name $s.Name -StartupType Manual -ErrorAction Stop
            $done += $s.Display
            $undo += @{ Name = $s.Name; Delayed = $delayed }
        } catch { $failed += $s.Display }
    }
    if ($done) { Register-Change -Beschreibung "Dienste auf »Manuell« gestellt: $($done -join ', ')" -Typ 'Dienst' -Daten @{ Dienste = $undo } }
    $msg = "$(@($done).Count) Dienst(e) auf »Manuell« gestellt – sie starten nur noch bei Bedarf. Rückgängig über »Änderungen«."
    if ($failed) { $msg += " Nicht möglich: $($failed -join ', ')." }
    $msg
}

function Add-ExtendedAutostartFindings {
    param([string]$Category)
    $tasks = @(Get-StartupScheduledTasks)
    if ($tasks) {
        $labels = @($tasks | ForEach-Object { '{0} – {1} · {2}' -f $_.Name, $_.When, $(if ($_.Exe) { Split-Path -Leaf $_.Exe } else { 'ohne Programm' }) })
        Add-Finding $Category Info "$($tasks.Count) geplante Aufgabe(n) starten bei Anmeldung oder Systemstart" -Items @($tasks | ForEach-Object { '{0}{1}  →  {2}' -f $_.Path, $_.Name, $_.Exe }) `
            -Detail 'Viele Programme starten ihre Update-Prüfung oder Hilfsprogramme über die Aufgabenplanung statt über den Autostart. Updater zu deaktivieren ist meist unkritisch – das Programm sucht dann beim eigenen Start nach Updates. Virenschutz, Treiber-Werkzeuge und Windows-Aufgaben werden nicht angeboten.' `
            -SelectLabels $labels -FixData $tasks -FixLabel 'Ausgewählte geplante Aufgaben deaktivieren' -Fix {
            param($d, $pre)
            if (-not $pre) {
                $all = @($d); for ($i = 0; $i -lt $all.Count; $i++) { Write-Host ('    {0,3}) {1}' -f ($i + 1), $all[$i].Name) }
                $d = @((Read-Selection (Read-Host '   Deaktivieren: Nummern oder leer = keine') $all.Count) | ForEach-Object { $all[$_] })
                if (-not $d) { return 'Nichts ausgewählt.' }
            }
            Disable-StartupTasks $d
        }
    }
    $svc = @(Get-ThirdPartyAutoServices)
    if ($svc) {
        $labels = @($svc | ForEach-Object { '{0} · {1}{2}' -f $_.Display, $(if ($_.Company) { $_.Company } else { 'Hersteller unbekannt' }), $(if ($_.State -ne 'Running') { ' · läuft gerade nicht' } else { '' }) })
        Add-Finding $Category Info "$($svc.Count) Dienst(e) von Fremdherstellern starten automatisch" -Items @($svc | ForEach-Object { '{0} ({1})  →  {2}' -f $_.Display, $_.Name, $_.Exe }) `
            -Detail 'Ausgewählte Dienste werden auf »Manuell« gestellt (nicht deaktiviert): Sie starten dann nur noch, wenn ein Programm sie braucht. Bei Hilfsdiensten von Druckern, Spiele-Launchern oder Update-Diensten spart das Startzeit und Arbeitsspeicher. Im Zweifel nicht ändern. Virenschutz, Treiber und Windows-Dienste werden nicht angeboten.' `
            -SelectLabels $labels -FixData $svc -FixLabel 'Ausgewählte Dienste auf »Manuell« stellen' -Fix {
            param($d, $pre)
            if (-not $pre) {
                $all = @($d); for ($i = 0; $i -lt $all.Count; $i++) { Write-Host ('    {0,3}) {1}' -f ($i + 1), $all[$i].Display) }
                $d = @((Read-Selection (Read-Host '   Auf »Manuell« stellen: Nummern oder leer = keine') $all.Count) | ForEach-Object { $all[$_] })
                if (-not $d) { return 'Nichts ausgewählt.' }
            }
            Set-ServicesManual $d
        }
    }
}
