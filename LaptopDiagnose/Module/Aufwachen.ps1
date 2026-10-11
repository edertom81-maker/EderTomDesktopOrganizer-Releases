<#
    Ungewolltes Aufwachen aus dem Energiesparmodus: Weckquellen der letzten Tage, Geräte mit Weckberechtigung,
    Reaktivierungszeitgeber. Weckberechtigungen und Zeitgeber nur nach Auswahl ändern, umkehrbar.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:RtcWakeGuid = 'bd3b718a-0680-4d9d-8ab2-e1d2b4ac806d'   # »Reaktivierungszeitgeber zulassen«

function Get-WakeEvents {
    <# Aufwachvorgänge der letzten Tage mit Weckquelle (Ereignis 1 des Power-Troubleshooters). #>
    param([int]$Days = 7)
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Microsoft-Windows-Power-Troubleshooter'; Id = 1; StartTime = (Get-Date).AddDays(-$Days) } -ErrorAction SilentlyContinue)
    foreach ($e in $ev) {
        $src = $null
        foreach ($line in ("$($e.Message)" -split "`r?`n")) {
            if ($line -match '(Reaktivierungsquelle|Aktivierungsquelle|Wake Source|Quelle)\s*:\s*(.+)$') { $src = $Matches[2].Trim() }
        }
        [pscustomobject]@{ Time = $e.TimeCreated; Source = $(if ($src) { $src } else { 'unbekannt' }) }
    }
}

function Get-WakeArmedDevices {
    <# Geräte, die den Computer aufwecken dürfen. #>
    @(& powercfg.exe /devicequery wake_armed 2>$null | ForEach-Object { "$_".Trim() } | Where-Object { $_ -and $_ -notmatch '^(NONE|KEINE)$' })
}

function Get-PowerSettingValues {
    <# Wechsel- und Gleichstromwert einer Energieeinstellung des aktiven Plans. #>
    param([string]$Sub, [string]$Setting)
    $q = (& powercfg.exe /query SCHEME_CURRENT $Sub $Setting 2>$null | Out-String)
    $hex = @([regex]::Matches($q, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($hex.Count -ge 2) { return [pscustomobject]@{ AC = [Convert]::ToInt32($hex[-2], 16); DC = [Convert]::ToInt32($hex[-1], 16) } }
    return $null
}

function Disable-WakeDevices {
    param($Devices)
    $done = @(); $failed = @()
    foreach ($d in @($Devices)) {
        $null = & powercfg.exe /devicedisablewake "$d" 2>&1
        if ($LASTEXITCODE -eq 0) { $done += "$d" } else { $failed += "$d" }
    }
    if ($done) { Register-Change -Beschreibung "Weckberechtigung entzogen: $($done -join ', ')" -Typ 'Weckgeraet' -Daten @{ Geraete = $done } }
    $msg = "$(@($done).Count) Gerät(en) die Weckberechtigung entzogen. Rückgängig über »Änderungen«."
    if ($failed) { $msg += " Nicht möglich: $($failed -join ', ')." }
    $msg
}

function Add-WakeFindings {
    param([string]$Category)
    $events = @(Get-WakeEvents)
    $devices = @(Get-WakeArmedDevices)
    $rtc = Get-PowerSettingValues 'SUB_SLEEP' $Script:RtcWakeGuid
    $laptop = (Get-DeviceKind) -eq 'Laptop'

    if ($events) {
        $groups = @($events | Group-Object Source | Sort-Object Count -Descending)
        $items = @($groups | ForEach-Object { '{0,3}×  {1}' -f $_.Count, $_.Name }) + @('') + @($events | Sort-Object Time -Descending | Select-Object -First 10 | ForEach-Object { '{0:dd.MM. HH:mm}  {1}' -f $_.Time, $_.Source })
        $sev = if ($events.Count -ge 14) { 'Warnung' } else { 'Info' }
        Add-Finding $Category $sev "$($events.Count)× aus dem Energiesparmodus aufgewacht (7 Tage)" -Items $items `
            -Detail 'Häufige Weckquellen: Maus oder Tastatur (schon kleine Erschütterungen), Netzwerkkarte (»Wake on LAN«/Netzwerkverkehr), Reaktivierungszeitgeber (geplante Wartung, Updates). Unerwünschtes Aufwachen leert besonders bei Laptops in der Tasche den Akku.'
    }

    if ($devices) {
        $preselect = @($devices | ForEach-Object { $_ -match '(?i)maus|mouse|ethernet|wi-?fi|wlan|wireless|network|netzwerk|lan|realtek pcie|intel\(r\) (ethernet|wi)' })
        Add-Finding $Category Info "$($devices.Count) Gerät(e) dürfen den Computer aufwecken" -Items $devices `
            -Detail 'Vorausgewählt sind Mäuse und Netzwerkadapter – die häufigsten Ursachen für ungewolltes Aufwachen. Die Tastatur bleibt zum Aufwecken nutzbar, solange sie nicht ausgewählt wird. Rückgängig über »Änderungen«.' `
            -SelectLabels $devices -SelectDefault $preselect -FixData $devices -FixLabel 'Ausgewählten Geräten die Weckberechtigung entziehen' -Fix {
            param($d, $pre)
            if (-not $pre) {
                $all = @($d); for ($i = 0; $i -lt $all.Count; $i++) { Write-Host ('    {0,3}) {1}' -f ($i + 1), $all[$i]) }
                $d = @((Read-Selection (Read-Host '   Weckberechtigung entziehen: Nummern oder leer = keine') $all.Count) | ForEach-Object { $all[$_] })
                if (-not $d) { return 'Nichts ausgewählt.' }
            }
            Disable-WakeDevices $d
        }
    }

    if ($rtc -and $laptop -and $rtc.DC -ne 0) {
        Add-Finding $Category Info 'Reaktivierungszeitgeber im Akkubetrieb erlaubt' `
            -Detail 'Geplante Aufgaben (z. B. Wartung, Updates) dürfen den Laptop auch im Akkubetrieb aus dem Energiesparmodus wecken – etwa in der Tasche. Im Akkubetrieb ausschalten; am Netzteil bleibt es erlaubt. Rückgängig über »Änderungen«.' `
            -FixLabel 'Reaktivierungszeitgeber im Akkubetrieb ausschalten' -FixData $rtc.DC -Fix {
            param($d)
            $null = & powercfg.exe /setdcvalueindex SCHEME_CURRENT SUB_SLEEP $Script:RtcWakeGuid 0
            $null = & powercfg.exe /setactive SCHEME_CURRENT
            Register-Change -Beschreibung 'Reaktivierungszeitgeber im Akkubetrieb ausgeschaltet' -Typ 'Energieeinstellung' -Daten @{ Sub = 'SUB_SLEEP'; Setting = $Script:RtcWakeGuid; Modus = 'DC'; Previous = [int]$d }
            'Reaktivierungszeitgeber im Akkubetrieb ausgeschaltet.'
        }
    }
    if (-not $events -and -not $devices) { Add-Finding $Category OK 'Kein ungewolltes Aufwachen erkannt' }
}
