<#
    Browser-Entführer erkennen: erzwungene Browser-Richtlinien (Startseite, Suchmaschine, Zwangs-Erweiterungen),
    ungewöhnliche Startseiten, Firefox »user.js«, Proxy-Skript (PAC), manipulierte DNS-Server, Einträge in der
    Hosts-Datei und Browser-Verknüpfungen mit angehängter Webadresse. Ändern nur nach Auswahl, umkehrbar.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:KnownGoodHosts = 'google\.|bing\.com|duckduckgo\.com|ecosia\.org|startpage\.com|qwant\.com|yahoo\.|msn\.com|microsoft\.com|mozilla\.|brave\.com|web\.de|gmx\.|t-online\.de|orf\.at|about:|chrome:|edge:|newtab'
$Script:KnownDns = @('8.8.8.8', '8.8.4.4', '1.1.1.1', '1.0.0.1', '9.9.9.9', '149.112.112.112', '208.67.222.222', '208.67.220.220', '94.140.14.14', '94.140.15.15', '76.76.2.0', '76.76.10.0', '2001:4860:4860::8888', '2001:4860:4860::8844', '2606:4700:4700::1111', '2606:4700:4700::1001', '2620:fe::fe')
$Script:SensitiveHosts = 'microsoft|windowsupdate|update\.|google|bing|avast|avg|bitdefender|kaspersky|eset|norton|mcafee|malwarebytes|sophos|defender|virustotal|paypal|bank|sparkasse|volksbank|amazon|apple'

function Remove-RegistryValuesTracked {
    <# Entfernt Registry-Werte und protokolliert sie (mit Typ und bisherigem Wert) als EINE umkehrbare Änderung. #>
    param([Parameter(Mandatory)]$Values, [Parameter(Mandatory)][string]$Beschreibung)
    $undo = @()
    foreach ($v in @($Values)) {
        $key = Get-Item -Path $v.Path -ErrorAction SilentlyContinue
        if (-not $key -or $null -eq $key.GetValue($v.Name, $null)) { continue }
        $kind = "$($key.GetValueKind($v.Name))"
        $prev = $key.GetValue($v.Name, $null, 'DoNotExpandEnvironmentNames')
        if ($kind -eq 'Binary') { $prev = [Convert]::ToBase64String([byte[]]$prev) }
        Remove-ItemProperty -Path $v.Path -Name $v.Name -ErrorAction Stop
        $undo += @{ Path = $v.Path; Name = $v.Name; Type = $kind; Existed = $true; Previous = $prev }
    }
    if ($undo) { Register-Change -Beschreibung $Beschreibung -Typ 'Registry' -Daten @{ Werte = $undo } }
    return $undo.Count
}

function Get-BrowserPolicyEntries {
    <# Erzwungene Richtlinien in Edge/Chrome/Brave: typisches Werkzeug von Browser-Entführern auf Privatgeräten. #>
    $roots = @{ 'Edge' = 'Microsoft\Edge'; 'Chrome' = 'Google\Chrome'; 'Brave' = 'BraveSoftware\Brave' }
    $names = 'HomepageLocation', 'HomepageIsNewTabPage', 'NewTabPageLocation', 'RestoreOnStartup', 'DefaultSearchProviderEnabled', 'DefaultSearchProviderSearchURL', 'DefaultSearchProviderName', 'DefaultSearchProviderKeyword'
    foreach ($b in $roots.Keys) {
        foreach ($hive in 'HKLM', 'HKCU') {
            $p = "$($hive):\SOFTWARE\Policies\$($roots[$b])"
            $item = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
            if ($item) {
                foreach ($n in $names) { if ($null -ne $item.$n) { [pscustomobject]@{ Browser = $b; Path = $p; Name = $n; Value = "$($item.$n)"; Display = "$($b): $n = $($item.$n)" } } }
            }
            foreach ($sub in 'RestoreOnStartupURLs', 'ExtensionInstallForcelist') {
                $sp = "$p\$sub"
                $si = Get-ItemProperty -Path $sp -ErrorAction SilentlyContinue
                if ($si) {
                    foreach ($prop in $si.PSObject.Properties | Where-Object { $_.Name -match '^\d+$' }) {
                        [pscustomobject]@{ Browser = $b; Path = $sp; Name = $prop.Name; Value = "$($prop.Value)"; Display = "$($b): $sub = $($prop.Value)" }
                    }
                }
            }
        }
    }
}

function Get-ChromiumStartPages {
    <# Startseiten aus den Profil-Einstellungen von Edge, Chrome und Brave (nur lesen). #>
    $profiles = @{
        'Edge'   = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'
        'Chrome' = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'
        'Brave'  = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'
    }
    foreach ($b in $profiles.Keys) {
        if (-not (Test-Path -LiteralPath $profiles[$b])) { continue }
        foreach ($dir in @(Get-ChildItem -LiteralPath $profiles[$b] -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })) {
            $pref = Join-Path $dir.FullName 'Preferences'
            if (-not (Test-Path -LiteralPath $pref)) { continue }
            try { $j = [IO.File]::ReadAllText($pref) | ConvertFrom-Json } catch { continue }
            $urls = @()
            if ($j.session -and [int]$j.session.restore_on_startup -eq 4) { $urls += @($j.session.startup_urls) }
            if ($j.homepage -and -not $j.homepage_is_newtabpage) { $urls += $j.homepage }
            foreach ($u in @($urls | Where-Object { $_ })) { [pscustomobject]@{ Browser = $b; Profile = $dir.Name; Url = "$u" } }
        }
    }
}

function Get-FirefoxHijackSigns {
    $root = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
    foreach ($dir in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
        $userJs = Join-Path $dir.FullName 'user.js'
        if (Test-Path -LiteralPath $userJs) { [pscustomobject]@{ Profile = $dir.Name; What = 'user.js vorhanden (erzwingt Einstellungen bei jedem Start)'; Path = $userJs } }
        $prefs = Join-Path $dir.FullName 'prefs.js'
        if (Test-Path -LiteralPath $prefs) {
            $m = Select-String -LiteralPath $prefs -Pattern 'user_pref\("browser\.startup\.homepage",\s*"([^"]+)"' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($m) {
                $u = $m.Matches[0].Groups[1].Value
                if ($u -notmatch $Script:KnownGoodHosts) { [pscustomobject]@{ Profile = $dir.Name; What = "Startseite: $u"; Path = $prefs } }
            }
        }
    }
}

function Get-HostsEntries {
    $path = Join-Path $env:windir 'System32\drivers\etc\hosts'
    if (-not (Test-Path -LiteralPath $path)) { return }
    $i = 0
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        $i++
        $t = ($line -replace '#.*$', '').Trim()
        if (-not $t) { continue }
        $parts = $t -split '\s+'
        if ($parts.Count -lt 2) { continue }
        $names = @($parts | Select-Object -Skip 1)
        if (($names | Where-Object { $_ -notin 'localhost', 'localhost.localdomain' }).Count -eq 0) { continue }
        [pscustomobject]@{ Line = $i; Text = $line.Trim(); Ip = $parts[0]; Names = $names; Sensitive = [bool]($names -match $Script:SensitiveHosts) }
    }
}

function Get-StaticDnsAdapters {
    <# Netzwerkadapter mit fest eingetragenen DNS-Servern, die nicht zu bekannten Anbietern oder dem eigenen Netz gehören. #>
    $ifs = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    foreach ($a in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' })) {
        $ns = "$((Get-ItemProperty -Path "$ifs\$($a.InterfaceGuid)" -Name NameServer -ErrorAction SilentlyContinue).NameServer)"
        if (-not $ns.Trim()) { continue }
        $servers = @($ns -split '[,\s]+' | Where-Object { $_ })
        $odd = @($servers | Where-Object { $_ -notin $Script:KnownDns -and $_ -notmatch '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|127\.|fe80:|fd|::1)' })
        [pscustomobject]@{ Alias = $a.Name; Index = $a.ifIndex; Servers = $servers; Odd = $odd }
    }
}

function Get-HijackedShortcuts {
    <# Browser-Verknüpfungen, an die eine Webadresse angehängt wurde (öffnet bei jedem Start eine bestimmte Seite). #>
    $dirs = @([Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('CommonDesktopDirectory'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'),
        [Environment]::GetFolderPath('StartMenu'), [Environment]::GetFolderPath('CommonStartMenu')) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    $shell = $null
    try { $shell = New-Object -ComObject WScript.Shell } catch { return }
    foreach ($d in $dirs) {
        foreach ($f in @(Get-ChildItem -LiteralPath $d -Filter '*.lnk' -Recurse -Depth 2 -ErrorAction SilentlyContinue)) {
            try { $l = $shell.CreateShortcut($f.FullName) } catch { continue }
            if ($l.TargetPath -match '(?i)\\(msedge|chrome|firefox|brave|opera|iexplore)\.exe$' -and $l.Arguments -match '(?i)https?://|www\.') {
                [pscustomobject]@{ Path = $f.FullName; Target = $l.TargetPath; Arguments = $l.Arguments }
            }
        }
    }
}

function Add-HijackFindings {
    param([string]$Category)
    $found = 0

    # 1) Erzwungene Richtlinien
    $pol = @(Get-BrowserPolicyEntries)
    if ($pol) {
        $found++
        $isDomain = $false
        try { $isDomain = [bool](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).PartOfDomain } catch { }
        $sev = if ($isDomain) { 'Info' } else { 'Warnung' }
        Add-Finding $Category $sev "$($pol.Count) erzwungene Browser-Einstellung(en) (»Von Ihrer Organisation verwaltet«)" -Items @($pol | ForEach-Object { $_.Display }) `
            -Detail $(if ($isDomain) { 'Das Gerät gehört zu einer Firmen-Domäne – diese Richtlinien setzt vermutlich die IT. Nichts ändern, ohne die IT zu fragen.' } else { 'Auf einem Privatgerät setzen fast nur Browser-Entführer (Adware) solche Richtlinien: Startseite, Suchmaschine oder Erweiterungen lassen sich dann nicht mehr ändern. Entfernen ist über »Änderungen« umkehrbar; danach den Browser neu starten.' }) `
            -SelectLabels @($pol | ForEach-Object { $_.Display }) -SelectAllByDefault:(-not $isDomain) -FixData $pol -FixLabel 'Ausgewählte Browser-Richtlinien entfernen' -Fix {
            param($d, $pre)
            if (-not $pre) {
                $all = @($d); for ($i = 0; $i -lt $all.Count; $i++) { Write-Host ('    {0,3}) {1}' -f ($i + 1), $all[$i].Display) }
                $sel = Read-Host '   Entfernen: [A] alle, Nummern oder leer = keine'
                $d = if ($sel -match '^\s*(a|alle)\s*$') { $all } else { @((Read-Selection $sel $all.Count) | ForEach-Object { $all[$_] }) }
            }
            $n = Remove-RegistryValuesTracked -Values @($d | ForEach-Object { @{ Path = $_.Path; Name = $_.Name } }) -Beschreibung "Browser-Richtlinien entfernt: $(@($d).Count)"
            "$n Richtlinie(n) entfernt. Browser neu starten. Rückgängig über »Änderungen«."
        }
    }

    # 2) Ungewöhnliche Startseiten
    $pages = @(Get-ChromiumStartPages | Where-Object { $_.Url -notmatch $Script:KnownGoodHosts })
    $ff = @(Get-FirefoxHijackSigns)
    if ($pages -or $ff) {
        $found++
        $items = @($pages | ForEach-Object { "$($_.Browser) ($($_.Profile)): $($_.Url)" }) + @($ff | ForEach-Object { "Firefox ($($_.Profile)): $($_.What)" })
        Add-Finding $Category Info 'Ungewöhnliche Startseite im Browser' -Items $items `
            -Detail 'Beim Browserstart öffnet sich eine Seite, die nicht zu einer bekannten Suchmaschine oder einem großen Portal gehört. Selbst eingestellt? Dann ist alles in Ordnung. Sonst in den Browser-Einstellungen unter »Beim Start« ändern; bei Firefox eine »user.js« im Profilordner löschen (erzwingt die Einstellung bei jedem Start).' `
            -FixLabel 'Start-Einstellungen der Browser öffnen' -FixData @{ Pages = $pages; Ff = $ff } -Fix {
            param($d)
            foreach ($b in @($d.Pages | ForEach-Object { $_.Browser } | Select-Object -Unique)) {
                switch ($b) { 'Edge' { Start-Process 'msedge.exe' 'edge://settings/onStartup' -ErrorAction SilentlyContinue } 'Chrome' { Start-Process 'chrome.exe' 'chrome://settings/onStartup' -ErrorAction SilentlyContinue } 'Brave' { Start-Process 'brave.exe' 'brave://settings/getStarted' -ErrorAction SilentlyContinue } }
            }
            if ($d.Ff) { Start-Process 'firefox.exe' 'about:preferences#home' -ErrorAction SilentlyContinue; foreach ($x in @($d.Ff | Where-Object { $_.Path -like '*user.js' })) { Start-Process explorer.exe "/select,`"$($x.Path)`"" } }
            'Browser-Einstellungen geöffnet.'
        }
    }

    # 3) Proxy-Skript (PAC)
    $pac = $null
    try { $pac = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -Name AutoConfigURL -ErrorAction Stop).AutoConfigURL } catch { }
    if ($pac) {
        $found++
        Add-Finding $Category Warnung "Proxy-Skript eingetragen: $pac" `
            -Detail 'Ein Proxy-Skript (PAC) kann den gesamten Internetverkehr über fremde Server umleiten – eine bekannte Methode von Adware und Betrügern. In Firmen wird es manchmal bewusst gesetzt. Entfernen ist über »Änderungen« umkehrbar.' `
            -FixLabel 'Proxy-Skript entfernen' -Fix {
            param($d)
            $null = Remove-RegistryValuesTracked -Values @(@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'; Name = 'AutoConfigURL' }) -Beschreibung 'Proxy-Skript (AutoConfigURL) entfernt'
            'Proxy-Skript entfernt. Rückgängig über »Änderungen«.'
        }
    }

    # 4) DNS-Server
    $dns = @(Get-StaticDnsAdapters | Where-Object { $_.Odd })
    if ($dns) {
        $found++
        Add-Finding $Category Warnung 'Unbekannte DNS-Server fest eingetragen' -Items @($dns | ForEach-Object { "$($_.Alias): $($_.Servers -join ', ')" }) `
            -Detail 'Der DNS-Server übersetzt Webadressen in Server-Adressen. Ein fremder DNS-Server kann Sie unbemerkt auf gefälschte Seiten (z. B. Online-Banking) umleiten. Selbst eingetragen (z. B. ein eigener Werbeblocker)? Dann ist alles in Ordnung. Sonst auf »automatisch« zurücksetzen – umkehrbar über »Änderungen«.' `
            -SelectLabels @($dns | ForEach-Object { "$($_.Alias): $($_.Servers -join ', ')" }) -SelectAllByDefault -FixData $dns -FixLabel 'DNS-Server auf automatisch zurücksetzen' -Fix {
            param($d, $pre)
            foreach ($a in @($d)) {
                Set-DnsClientServerAddress -InterfaceIndex $a.Index -ResetServerAddresses -ErrorAction Stop
                Register-Change -Beschreibung "DNS-Server von »$($a.Alias)« auf automatisch zurückgesetzt (vorher $($a.Servers -join ', '))" -Typ 'DnsServer' -Daten @{ Index = $a.Index; Alias = $a.Alias; Servers = @($a.Servers) }
            }
            try { Clear-DnsClientCache -ErrorAction Stop } catch { }
            "$(@($d).Count) Adapter auf automatische DNS-Server zurückgesetzt. Rückgängig über »Änderungen«."
        }
    }

    # 5) Hosts-Datei
    $hosts = @(Get-HostsEntries)
    if ($hosts) {
        $found++
        $sens = @($hosts | Where-Object { $_.Sensitive })
        $sev = if ($sens) { 'Warnung' } else { 'Info' }
        Add-Finding $Category $sev "$($hosts.Count) Eintrag/Einträge in der Hosts-Datei$(if ($sens) { " – $($sens.Count) betreffen Update-, Sicherheits- oder Bankseiten" })" -Items @($hosts | ForEach-Object { "Zeile $($_.Line): $($_.Text)" }) `
            -Detail 'Die Hosts-Datei leitet Webadressen fest um. Schadsoftware blockiert damit Updates und Virenscanner oder leitet auf gefälschte Seiten um; manche Programme (z. B. Werbeblocker, Entwickler-Tools) tragen dort bewusst etwas ein. Vor dem Entfernen wird die Datei gesichert; umkehrbar über »Änderungen«.' `
            -SelectLabels @($hosts | ForEach-Object { "Zeile $($_.Line): $($_.Text)" }) -SelectDefault ([bool[]]@($hosts | ForEach-Object { $_.Sensitive })) -FixData $hosts -FixLabel 'Ausgewählte Hosts-Einträge entfernen' -Fix {
            param($d, $pre)
            if (-not $pre) {
                $all = @($d); for ($i = 0; $i -lt $all.Count; $i++) { Write-Host ('    {0,3}) Zeile {1}: {2}' -f ($i + 1), $all[$i].Line, $all[$i].Text) }
                $d = @((Read-Selection (Read-Host '   Entfernen: Nummern oder leer = keine') $all.Count) | ForEach-Object { $all[$_] })
                if (-not $d) { return 'Nichts ausgewählt.' }
            }
            $path = Join-Path $env:windir 'System32\drivers\etc\hosts'
            $old = [IO.File]::ReadAllText($path)
            $backup = Join-Path $BerichtOrdner ('hosts_Sicherung_{0:yyyyMMdd_HHmmss}.txt' -f (Get-Date))
            [IO.File]::WriteAllText($backup, $old)
            $drop = @{}; foreach ($x in @($d)) { $drop[[int]$x.Line] = $true }
            $lines = [IO.File]::ReadAllLines($path)
            $keep = for ($i = 0; $i -lt $lines.Count; $i++) { if (-not $drop.ContainsKey($i + 1)) { $lines[$i] } }
            [IO.File]::WriteAllLines($path, [string[]]@($keep))
            Register-Change -Beschreibung "Hosts-Datei: $(@($d).Count) Eintrag/Einträge entfernt" -Typ 'Hosts' -Daten @{ Backup = $backup }
            try { Clear-DnsClientCache -ErrorAction Stop } catch { }
            "$(@($d).Count) Eintrag/Einträge entfernt (Sicherung: $backup). Rückgängig über »Änderungen«."
        }
    }

    # 6) Verknüpfungen mit angehängter Webadresse
    $lnk = @(Get-HijackedShortcuts)
    if ($lnk) {
        $found++
        Add-Finding $Category Warnung "$($lnk.Count) Browser-Verknüpfung(en) öffnen eine feste Webseite" -Items @($lnk | ForEach-Object { "$($_.Path) → $($_.Arguments)" }) `
            -Detail 'An die Verknüpfung wurde eine Webadresse angehängt – typischer Trick von Browser-Entführern, damit auch nach dem Ändern der Startseite deren Seite erscheint. Die Adresse wird entfernt; umkehrbar über »Änderungen«.' `
            -SelectLabels @($lnk | ForEach-Object { "$($_.Path) → $($_.Arguments)" }) -SelectAllByDefault -FixData $lnk -FixLabel 'Webadressen aus den Browser-Verknüpfungen entfernen' -Fix {
            param($d, $pre)
            $shell = New-Object -ComObject WScript.Shell
            foreach ($x in @($d)) {
                $l = $shell.CreateShortcut($x.Path)
                $l.Arguments = (($l.Arguments -split '\s+') | Where-Object { $_ -notmatch '(?i)https?://|www\.' }) -join ' '
                $l.Save()
            }
            Register-Change -Beschreibung "Webadressen aus $(@($d).Count) Browser-Verknüpfung(en) entfernt" -Typ 'Verknuepfung' -Daten @{ Eintraege = @($d | ForEach-Object { @{ Path = $_.Path; Arguments = $_.Arguments } }) }
            "$(@($d).Count) Verknüpfung(en) bereinigt. Rückgängig über »Änderungen«."
        }
    }

    if (-not $found) { Add-Finding $Category OK 'Keine Spuren von Browser-Entführern gefunden' -Detail 'Geprüft: erzwungene Browser-Richtlinien, Startseiten, Firefox user.js, Proxy-Skript, DNS-Server, Hosts-Datei und Browser-Verknüpfungen.' }
}
