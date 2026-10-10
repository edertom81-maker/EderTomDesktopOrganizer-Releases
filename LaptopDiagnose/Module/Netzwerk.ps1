<#
    Netzwerk & WLAN: Internetverbindung, WLAN-Qualität, Geschwindigkeit, Latenz, Proxy, WLAN-Treiber, WLAN-Bericht.
    Teil von LaptopDiagnose – Copyright 2026 by Eder Tom
#>

function Reset-NetworkStack {
    $null = & ipconfig.exe /flushdns
    $null = & ipconfig.exe /release
    $null = & ipconfig.exe /renew
    $null = & netsh.exe winsock reset
    $null = & netsh.exe int ip reset
    $Script:RebootNeeded = $true
    Register-Change -Beschreibung 'Netzwerkstack zurückgesetzt (DNS, IP, Winsock, TCP/IP)' -Typ 'Protokoll' -NichtUmkehrbar
    'DNS-Cache geleert, IP-Adresse erneuert, Winsock und TCP/IP zurückgesetzt (wirksam nach Neustart).'
}

function ConvertFrom-NetshInterfaces {
    <# Wertet »netsh wlan show interfaces« sprachunabhängig (Deutsch/Englisch) aus. #>
    param([string[]]$Lines)
    $result = @()
    $cur = $null
    foreach ($l in $Lines) {
        if ($l -notmatch '^\s+(\S[^:]*?)\s*:\s(.*)$') { continue }
        $key = $Matches[1].Trim(); $val = $Matches[2].Trim()
        if ($key -match '^Name$') {
            if ($cur) { $result += [pscustomobject]$cur }
            $cur = [ordered]@{ Name = $val; State = ''; SSID = ''; Radio = ''; Band = ''; Channel = ''; Rx = $null; Tx = $null; Signal = $null; Auth = '' }
            continue
        }
        if (-not $cur) { continue }
        switch -Regex ($key) {
            '^(State|Status)$' { $cur.State = $val }
            '^SSID$' { $cur.SSID = $val }
            '^(Radio type|Funktyp)$' { $cur.Radio = $val }
            '^Band$' { $cur.Band = $val }
            '^(Channel|Kanal)$' { $cur.Channel = $val }
            '^(Receive rate|Empfangsrate)' { $cur.Rx = [double]($val -replace ',', '.') }
            'bertragungsrate|^Transmit rate' { $cur.Tx = [double]($val -replace ',', '.') }
            '^Signal$' { $cur.Signal = [int]($val -replace '[^\d]', '') }
            '^(Authentication|Authentifizierung)$' { $cur.Auth = $val }
        }
    }
    if ($cur) { $result += [pscustomobject]$cur }
    return $result
}

function Measure-InternetSpeed {
    <# Lädt 20 MB von Cloudflare und misst die TCP-Verbindungszeit (funktioniert auch, wenn Ping blockiert ist). #>
    $lat = @()
    for ($i = 0; $i -lt 4; $i++) {
        $c = New-Object Net.Sockets.TcpClient
        try {
            $sw = [Diagnostics.Stopwatch]::StartNew()
            $task = $c.ConnectAsync('speed.cloudflare.com', 443)
            if ($task.Wait(3000)) { $sw.Stop(); $lat += $sw.Elapsed.TotalMilliseconds }
        } catch { } finally { $c.Dispose() }
    }
    $wc = New-Object Net.WebClient
    $wc.Headers.Add('User-Agent', "LaptopDiagnose/$Script:ToolVersion")
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $data = $wc.DownloadData('https://speed.cloudflare.com/__down?bytes=20000000')
    $sw.Stop()
    $wc.Dispose()
    $mbit = $data.Length * 8 / 1e6 / [math]::Max($sw.Elapsed.TotalSeconds, 0.001)
    return [pscustomobject]@{
        Download = [math]::Round($mbit, 1)
        Latenz   = $(if ($lat) { [math]::Round((($lat | Sort-Object)[0..([math]::Min(2, $lat.Count - 1))] | Measure-Object -Average).Average) })
    }
}

function Invoke-NetworkScan {
    $cat = 'Netzwerk'
    Clear-CategoryFindings $cat
    Write-Title 'Netzwerk & WLAN'
    $state = @{ Online = $false }

    Invoke-Check $cat 'Internetverbindung' {
        $dnsOk = $false; $webOk = $false
        try { $null = [System.Net.Dns]::GetHostAddresses('www.msftconnecttest.com'); $dnsOk = $true } catch { }
        if ($dnsOk) {
            try {
                $r = Invoke-WebRequest -Uri 'http://www.msftconnecttest.com/connecttest.txt' -UseBasicParsing -TimeoutSec 8
                $webOk = ($r.Content -match 'Microsoft Connect Test')
            } catch { }
        }
        $dns = @()
        try { $dns = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.ServerAddresses } | ForEach-Object { '{0}: {1}' -f $_.InterfaceAlias, ($_.ServerAddresses -join ', ') }) } catch { }
        if ($webOk) {
            $state.Online = $true
            Add-Finding $cat OK 'Internetverbindung funktioniert' -Items $dns
        } elseif (-not $dnsOk) {
            $online = Test-Connection -ComputerName 1.1.1.1 -Count 2 -Quiet -ErrorAction SilentlyContinue
            if ($online) {
                Add-Finding $cat Warnung 'Namensauflösung (DNS) funktioniert nicht – das Internet ist aber erreichbar' -Items $dns `
                    -FixLabel 'DNS-Cache leeren und Netzwerkstack zurücksetzen' -Fix { param($d) Reset-NetworkStack } -RequiresReboot
            } else {
                Add-Finding $cat Warnung 'Keine Internetverbindung' `
                    -Detail 'WLAN/Kabel prüfen. Updates und Online-Prüfungen sind ohne Internet nicht möglich.' `
                    -FixLabel 'Netzwerkstack zurücksetzen (Verbindung wird kurz getrennt)' -Fix { param($d) Reset-NetworkStack } -RequiresReboot
            }
        } else {
            Add-Finding $cat Warnung 'Internet nur eingeschränkt erreichbar (Proxy, Anmeldeseite eines Hotspots oder Filter?)'
        }
    }

    Invoke-Check $cat 'WLAN-Verbindung' {
        $out = & netsh.exe wlan show interfaces 2>$null
        $ifaces = @(ConvertFrom-NetshInterfaces $out)
        $wlan = $ifaces | Where-Object { $_.SSID } | Select-Object -First 1
        if (-not $ifaces) {
            Add-Finding $cat Info 'Kein WLAN-Adapter gefunden oder WLAN-Dienst nicht aktiv'
            return
        }
        if (-not $wlan) {
            Add-Finding $cat Info 'Derzeit nicht mit einem WLAN verbunden (Kabel oder Mobilfunk?)'
            return
        }
        Set-Metric 'WLANSignal' $wlan.Signal
        $items = @(
            "Netzwerk: $($wlan.SSID)"
            "Signal: $($wlan.Signal) %"
            "Standard: $($wlan.Radio)$(if ($wlan.Band) { ", Band $($wlan.Band)" }), Kanal $($wlan.Channel)"
            "Verbindungsrate: $($wlan.Rx) / $($wlan.Tx) Mbit/s (Empfang/Senden)"
            "Sicherheit: $($wlan.Auth)"
        )
        if ($wlan.Auth -match '^(Open|Offen|Geöffnet|Ge.ffnet)$') {
            Add-Finding $cat Warnung "Verbunden mit einem unverschlüsselten WLAN (»$($wlan.SSID)«)" -Items $items `
                -Detail 'Andere im selben Netz können unverschlüsselten Datenverkehr mitlesen. Nur Webseiten mit https nutzen, ggf. VPN verwenden.'
        } elseif ($wlan.Auth -match 'WEP') {
            Add-Finding $cat Kritisch 'WLAN nutzt die unsichere Verschlüsselung WEP' -Items $items -Detail 'Router auf WPA2 oder WPA3 umstellen.'
        }
        if ($wlan.Signal -lt 40) {
            Add-Finding $cat Warnung "Schwaches WLAN-Signal ($($wlan.Signal) %)" -Items $items `
                -Detail 'Näher an den Router gehen, Router frei aufstellen oder einen Repeater/Mesh-System verwenden.'
        } elseif ($wlan.Signal -lt 60) {
            Add-Finding $cat Info "Mittleres WLAN-Signal ($($wlan.Signal) %)" -Items $items
        } else {
            Add-Finding $cat OK "Gutes WLAN-Signal ($($wlan.Signal) %)" -Items $items
        }
        $is24 = ($wlan.Band -match '^2[,.]4') -or ($wlan.Channel -match '^\d+$' -and [int]$wlan.Channel -le 14)
        if ($is24) {
            Add-Finding $cat Info 'Das WLAN nutzt das 2,4-GHz-Band' -Detail 'Das 5-GHz- oder 6-GHz-Band ist meist deutlich schneller und weniger gestört – sofern der Router es anbietet.'
        }
    }

    Invoke-Check $cat 'Geschwindigkeit und Latenz (lädt ca. 20 MB)' {
        if (-not $state.Online) { return }
        $s = Measure-InternetSpeed
        Set-Metric 'Download' $s.Download
        if ($null -ne $s.Latenz) { Set-Metric 'Latenz' $s.Latenz }
        $txt = "Download: $($s.Download) Mbit/s$(if ($null -ne $s.Latenz) { " · Latenz: $($s.Latenz) ms" })"
        $hist = @(Get-MetricSeries -Name 'Download' | Select-Object -First 1)
        $detail = if ($hist -and $hist[0].Values.Count -ge 2) { 'Bisherige Messungen: ' + (($hist[0].Values | Select-Object -Last 5 | ForEach-Object { "$_" }) -join ' · ') + ' Mbit/s' }
        if ($s.Download -lt 10) {
            Add-Finding $cat Warnung "Langsame Internetverbindung ($txt)" -Detail $(if ($detail) { $detail } else { 'Mit Kabel gegentesten – liegt es am WLAN oder am Anschluss?' })
        } elseif ($null -ne $s.Latenz -and $s.Latenz -gt 150) {
            Add-Finding $cat Warnung "Hohe Latenz ($txt)" -Detail 'Hohe Latenz macht Videotelefonate und Spiele ruckelig.'
        } else {
            Add-Finding $cat OK "Internetgeschwindigkeit: $txt" -Detail $detail
        }
    }

    Invoke-Check $cat 'Proxy-Einstellungen' {
        $p = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
        if ($p.ProxyEnable -eq 1 -and $p.ProxyServer) {
            Add-Finding $cat Info "Ein Proxy-Server ist eingetragen ($($p.ProxyServer))" `
                -Detail 'Unbekannte Proxy-Einträge können von Adware stammen. Wenn kein Firmen-Proxy bekannt ist, entfernen.' `
                -FixLabel 'Proxy-Einstellungen öffnen' -Fix { param($d) Start-Process 'ms-settings:network-proxy'; 'Proxy-Einstellungen geöffnet.' }
        }
    }

    Invoke-Check $cat 'Netzwerkkabel (LAN)' { Add-LanFindings -Category $cat }

    Invoke-Check $cat 'WLAN-Treiber' {
        # Nur echte WLAN-Hardware: virtuelle Adapter und Windows-eigene Treiber (Datum 2006) ausklammern, doppelte Einträge zusammenfassen
        $drv = @(Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='NET'" -ErrorAction Stop |
                Where-Object { $_.DeviceName -match 'Wi-?Fi|Wireless|WLAN|802\.11' -and $_.DeviceName -notmatch 'Virtual|Direct|Miniport' -and $_.DriverProviderName -notmatch '^Microsoft' } |
                Sort-Object DeviceName -Unique)
        foreach ($d in $drv) {
            if ($d.DriverDate -and $d.DriverDate -lt (Get-Date).AddYears(-3)) {
                Add-Finding $cat Info ('WLAN-Treiber ist über 3 Jahre alt ({0:dd.MM.yyyy})' -f $d.DriverDate) `
                    -Detail "$($d.DeviceName), Version $($d.DriverVersion). Neuere Treiber verbessern oft Stabilität und Geschwindigkeit (Bereich »Windows & Treiber« oder Hersteller-Tool)."
            }
        }
    }

    Invoke-Check $cat 'WLAN-Bericht' {
        Add-Finding $cat Info 'Optional: Ausführlicher WLAN-Bericht der letzten 3 Tage (Verbindungsabbrüche, Fehler)' `
            -FixLabel 'WLAN-Bericht erstellen und öffnen' -Fix { param($d) New-WlanReport }
    }
}

function New-WlanReport {
    $null = & netsh.exe wlan show wlanreport 2>&1
    $src = Join-Path $env:ProgramData 'Microsoft\Windows\WlanReport\wlan-report-latest.html'
    if (-not (Test-Path -LiteralPath $src)) { throw 'Der WLAN-Bericht konnte nicht erstellt werden (kein WLAN-Adapter?).' }
    if (-not (Test-Path -LiteralPath $BerichtOrdner)) { $null = New-Item -ItemType Directory -Path $BerichtOrdner -Force }
    $dst = Join-Path $BerichtOrdner ('WLAN-Bericht_{0:yyyyMMdd_HHmm}.html' -f (Get-Date))
    Copy-Item -LiteralPath $src -Destination $dst -Force
    if (-not $Unbeaufsichtigt) { Invoke-Item -LiteralPath $dst }
    "WLAN-Bericht gespeichert: $dst"
}
