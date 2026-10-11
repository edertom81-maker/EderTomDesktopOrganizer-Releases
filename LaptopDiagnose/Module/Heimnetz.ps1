<#
    »Wer ist in meinem WLAN?«: Geräte im eigenen Netz finden (Ping an alle Adressen des Netzes, danach die
    Nachbarschaftstabelle von Windows), Namen auflösen, zufällige (private) MAC-Adressen erkennen und Geräte
    markieren, die seit der letzten Prüfung neu sind. Liest nur; die Liste bekannter Geräte liegt im Berichtordner.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:KnownOui = @{ 'B8-27-EB' = 'Raspberry Pi'; 'DC-A6-32' = 'Raspberry Pi'; 'E4-5F-01' = 'Raspberry Pi' }

function Get-HomeNetworkFile { Join-Path $BerichtOrdner 'Heimnetz.json' }

function Get-KnownHomeDevices {
    $f = Get-HomeNetworkFile
    if (-not (Test-Path -LiteralPath $f)) { return @{} }
    $h = @{}
    try { foreach ($e in @([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8) | ConvertFrom-Json)) { if ($e.Mac) { $h["$($e.Mac)"] = $e } } } catch { }
    return $h
}

function Save-KnownHomeDevices {
    param($Devices)
    $known = Get-KnownHomeDevices
    foreach ($d in @($Devices)) {
        $known[$d.Mac] = [pscustomobject]@{ Mac = $d.Mac; Name = $d.Name; Ip = $d.Ip; FirstSeen = $(if ($known[$d.Mac].FirstSeen) { $known[$d.Mac].FirstSeen } else { (Get-Date).ToString('s') }); LastSeen = (Get-Date).ToString('s') }
    }
    $json = ConvertTo-Json -InputObject @($known.Values) -Depth 3
    [IO.File]::WriteAllText((Get-HomeNetworkFile), $json, (New-Object Text.UTF8Encoding($true)))
    return $known.Count
}

function ConvertTo-IpNumber { param([string]$Ip) $b = ([Net.IPAddress]::Parse($Ip)).GetAddressBytes(); [uint32](([uint32]$b[0] -shl 24) -bor ([uint32]$b[1] -shl 16) -bor ([uint32]$b[2] -shl 8) -bor [uint32]$b[3]) }
function ConvertFrom-IpNumber { param([uint32]$N) '{0}.{1}.{2}.{3}' -f (($N -shr 24) -band 255), (($N -shr 16) -band 255), (($N -shr 8) -band 255), ($N -band 255) }

function Get-HomeSubnet {
    <# Aktives Netz mit Standardgateway: eigene Adresse, Präfix, Gateway, Adressbereich (höchstens /24 um die eigene Adresse). #>
    $cfg = @(Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' }) | Select-Object -First 1
    if (-not $cfg) { return $null }
    $addr = @($cfg.IPv4Address)[0]
    $prefix = [int]$addr.PrefixLength
    if ($prefix -lt 24) { $prefix = 24 }   # große Netze nur im eigenen /24-Bereich durchsuchen
    $own = ConvertTo-IpNumber $addr.IPAddress
    $mask = [uint32]([math]::Pow(2, 32) - [math]::Pow(2, 32 - $prefix))
    $net = $own -band $mask
    $count = [int][math]::Pow(2, 32 - $prefix)
    [pscustomobject]@{
        Index = $cfg.InterfaceIndex; Alias = $cfg.InterfaceAlias; Own = $addr.IPAddress; Gateway = "$(@($cfg.IPv4DefaultGateway)[0].NextHop)"
        Prefix = $prefix; Hosts = @(for ($i = 1; $i -lt $count - 1; $i++) { ConvertFrom-IpNumber ($net + [uint32]$i) })
    }
}

function Invoke-PingSweep {
    <# Alle Adressen parallel anpingen (füllt die Nachbarschaftstabelle, auch wenn Geräte Ping nicht beantworten). #>
    param([string[]]$Hosts, [int]$TimeoutMs = 600)
    $tasks = @{}
    foreach ($h in $Hosts) { try { $tasks[$h] = (New-Object Net.NetworkInformation.Ping).SendPingAsync($h, $TimeoutMs) } catch { } }
    try { $null = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($tasks.Values), $TimeoutMs + 2500) } catch { }
    $ok = @{}
    foreach ($h in $tasks.Keys) { $t = $tasks[$h]; if ($t.Status -eq 'RanToCompletion' -and "$($t.Result.Status)" -eq 'Success') { $ok[$h] = $true } }
    return $ok
}

function Resolve-HostNames {
    param([string[]]$Ips, [int]$TimeoutMs = 2500)
    $tasks = @{}
    foreach ($ip in $Ips) { try { $tasks[$ip] = [Net.Dns]::GetHostEntryAsync($ip) } catch { } }
    try { $null = [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($tasks.Values), $TimeoutMs) } catch { }
    $names = @{}
    foreach ($ip in $tasks.Keys) {
        $t = $tasks[$ip]
        if ($t.Status -eq 'RanToCompletion' -and $t.Result.HostName -and $t.Result.HostName -ne $ip) { $names[$ip] = $t.Result.HostName }
    }
    return $names
}

function Test-RandomMac {
    <# Lokal verwaltete (zufällige) MAC-Adresse: zweites Zeichen 2, 6, A oder E – typisch für Handys und Laptops mit »privater Adresse«. #>
    param([string]$Mac)
    return [bool]($Mac -match '^.[26AEae]')
}

function Get-HomeNetworkDevices {
    $net = Get-HomeSubnet
    if (-not $net) { throw 'Keine aktive Netzwerkverbindung mit Router gefunden.' }
    Write-Host "     › Heimnetz $($net.Gateway) /$($net.Prefix) wird durchsucht ($($net.Hosts.Count) Adressen) …" -ForegroundColor Gray
    $alive = Invoke-PingSweep -Hosts $net.Hosts
    Start-Sleep -Milliseconds 500
    $neigh = @(Get-NetNeighbor -AddressFamily IPv4 -InterfaceIndex $net.Index -ErrorAction SilentlyContinue |
            Where-Object { "$($_.State)" -in 'Reachable', 'Stale', 'Delay', 'Probe', 'Permanent' -and $_.LinkLayerAddress -and $_.LinkLayerAddress -notmatch '^(00-00-00-00-00-00|FF-FF-FF-FF-FF-FF|01-00-5E)' -and $net.Hosts -contains $_.IPAddress })
    $byIp = @{}
    foreach ($n in $neigh) { $byIp[$n.IPAddress] = ("$($n.LinkLayerAddress)".ToUpperInvariant() -replace ':', '-') }
    foreach ($ip in $alive.Keys) { if (-not $byIp.ContainsKey($ip)) { $byIp[$ip] = '' } }
    $ownMac = ''
    try { $ownMac = ("$((Get-NetAdapter -InterfaceIndex $net.Index -ErrorAction Stop).MacAddress)".ToUpperInvariant() -replace ':', '-') } catch { }
    $byIp[$net.Own] = $ownMac
    $names = Resolve-HostNames -Ips @($byIp.Keys)
    $known = Get-KnownHomeDevices
    foreach ($ip in @($byIp.Keys | Sort-Object { ConvertTo-IpNumber $_ })) {
        $mac = $byIp[$ip]
        $name = if ($ip -eq $net.Own) { "$env:COMPUTERNAME (dieser PC)" } elseif ($names[$ip]) { $names[$ip] } else { '' }
        $hints = @()
        if ($ip -eq $net.Gateway) { $hints += 'Router' }
        if ($mac -and $Script:KnownOui[$mac.Substring(0, [math]::Min(8, $mac.Length))]) { $hints += $Script:KnownOui[$mac.Substring(0, 8)] }
        if ($mac -and (Test-RandomMac $mac)) { $hints += 'private (zufällige) Adresse – meist Handy, Tablet oder Laptop' }
        [pscustomobject]@{
            Ip = $ip; Mac = $(if ($mac) { $mac } else { "IP:$ip" }); Name = $name; Hints = $hints
            IsNew = [bool]($known.Count -and -not $known.ContainsKey($(if ($mac) { $mac } else { "IP:$ip" })))
            Unnamed = (-not $name -and -not $hints)
        }
    }
}

function Find-HomeNetworkDevices {
    $devs = @(Get-HomeNetworkDevices)
    $firstScan = -not (Get-KnownHomeDevices).Count
    $new = @($devs | Where-Object { $_.IsNew })
    $items = @($devs | ForEach-Object {
            $tag = @()
            if ($_.IsNew) { $tag += 'NEU' }
            if ($_.Unnamed) { $tag += 'unbekannt' }
            '{0,-16} {1,-18} {2}{3}{4}' -f $_.Ip, $(if ($_.Mac -like 'IP:*') { '–' } else { $_.Mac }), $(if ($_.Name) { $_.Name } else { '(ohne Namen)' }), $(if ($_.Hints) { "  · $($_.Hints -join ', ')" } else { '' }), $(if ($tag) { "   [$($tag -join ', ')]" } else { '' })
        })
    Remove-FindingByKey 'Heimnetz'
    $title = "$($devs.Count) Gerät(e) im Heimnetz$(if ($new) { " – $($new.Count) neu seit der letzten Prüfung" })"
    $sev = if ($new) { 'Warnung' } else { 'Info' }
    $detail = if ($firstScan) { 'Erste Prüfung: Geräte durchsehen und mit »Alle als bekannt speichern« merken – bei späteren Prüfungen werden neue Geräte dann hervorgehoben.' }
    elseif ($new) { 'Neue Geräte seit der letzten Prüfung. Gehören sie Ihnen (z. B. neues Handy, Gäste)? Dann als bekannt speichern. Ein unbekanntes Gerät im WLAN: WLAN-Passwort im Router ändern und die Geräteliste des Routers prüfen.' }
    else { 'Keine neuen Geräte seit der letzten Prüfung.' }
    $detail += ' Geräte ohne Namen und mit privater Adresse sind meist Handys oder Laptops; Fernseher, Lautsprecher und Smart-Home-Geräte erscheinen oft ohne Namen. Ausgeschaltete oder schlafende Geräte fehlen in der Liste.'
    Add-Finding 'Netzwerk' $sev $title -Key 'Heimnetz' -Items $items -Detail $detail `
        -FixLabel 'Alle angezeigten Geräte als bekannt speichern' -FixData $devs -Fix {
        param($d)
        $n = Save-KnownHomeDevices $d
        "$(@($d).Count) Gerät(e) als bekannt gespeichert ($n insgesamt)."
    }
    "$($devs.Count) Gerät(e) gefunden$(if ($new) { ", davon $($new.Count) neu" })."
}

function Add-HomeNetworkToolFinding {
    param([string]$Category)
    Add-Finding $Category Info 'Wer ist in meinem WLAN?' -Silent -Repeatable `
        -Detail 'Sucht alle Geräte im eigenen Netz (Router, Handys, Fernseher, Smart-Home …) mit Adresse und Namen und markiert Geräte, die seit der letzten Prüfung neu sind. Dauert ca. 10 Sekunden; es wird nichts verändert.' `
        -FixLabel 'Geräte im Heimnetz suchen' -Fix { param($d) Find-HomeNetworkDevices }
}
