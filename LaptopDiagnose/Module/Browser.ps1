<#
    Browser: Caches (für den Datenmüll) und installierte Erweiterungen prüfen.
    Cookies, Passwörter, Verlauf und Lesezeichen werden nie angefasst.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

function Get-ChromiumBrowsers {
    @(
        @{ Name = 'Microsoft Edge'; Data = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'); Process = 'msedge'; Store = 'edge.microsoft.com|clients2.google.com' }
        @{ Name = 'Google Chrome'; Data = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'); Process = 'chrome'; Store = 'clients2.google.com' }
        @{ Name = 'Brave'; Data = (Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data'); Process = 'brave'; Store = 'clients2.google.com' }
        @{ Name = 'Vivaldi'; Data = (Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data'); Process = 'vivaldi'; Store = 'clients2.google.com' }
    ) | Where-Object { $_.Data -and (Test-Path -LiteralPath $_.Data) }
}

function Get-ChromiumProfiles {
    param([string]$DataDir)
    Get-ChildItem -LiteralPath $DataDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' }
}

function Get-BrowserCacheLocations {
    <# Je Browser ein Datenmüll-Eintrag mit allen Cache-Ordnern (wird nur bei geschlossenem Browser geleert). #>
    $raw = @(Get-BrowserCacheFolders)
    foreach ($g in $raw | Group-Object { $_.Browser }) {
        @{ Name = "Browser-Cache: $($g.Name)"; Paths = @($g.Group | ForEach-Object { $_.Path }); Hours = 0; Process = $g.Group[0].Process; Browser = $g.Name }
    }
}

function Get-BrowserCacheFolders {
    foreach ($b in Get-ChromiumBrowsers) {
        foreach ($p in Get-ChromiumProfiles $b.Data) {
            foreach ($sub in 'Cache', 'Code Cache', 'GPUCache', 'Service Worker\CacheStorage', 'Service Worker\ScriptCache') {
                $path = Join-Path $p.FullName $sub
                if (Test-Path -LiteralPath $path) { @{ Name = "$($b.Name): Cache ($($p.Name), $sub)"; Path = $path; Hours = 0; Process = $b.Process; Browser = $b.Name } }
            }
        }
        foreach ($sub in 'ShaderCache', 'GrShaderCache') {
            $path = Join-Path $b.Data $sub
            if (Test-Path -LiteralPath $path) { @{ Name = "$($b.Name): $sub"; Path = $path; Hours = 0; Process = $b.Process; Browser = $b.Name } }
        }
    }
    $opera = Join-Path $env:LOCALAPPDATA 'Opera Software\Opera Stable\Cache'
    if (Test-Path -LiteralPath $opera) { @{ Name = 'Opera: Cache'; Path = $opera; Hours = 0; Process = 'opera'; Browser = 'Opera' } }
    $ff = Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles'
    if (Test-Path -LiteralPath $ff) {
        foreach ($p in Get-ChildItem -LiteralPath $ff -Directory -ErrorAction SilentlyContinue) {
            $path = Join-Path $p.FullName 'cache2'
            if (Test-Path -LiteralPath $path) { @{ Name = "Firefox: Cache ($($p.Name))"; Path = $path; Hours = 0; Process = 'firefox'; Browser = 'Firefox' } }
        }
    }
}

function Resolve-ExtensionName {
    <# Chromium-Erweiterungen nennen sich oft »__MSG_appName__« – den Namen aus den Sprachdateien holen. #>
    param([string]$Name, [string]$Dir, [string]$DefaultLocale)
    if ($Name -notmatch '^__MSG_(.+)__$') { return $Name }
    $key = $Matches[1]
    foreach ($loc in @('de', $DefaultLocale, 'en', 'en_US') | Where-Object { $_ } | Select-Object -Unique) {
        $f = Join-Path $Dir "_locales\$loc\messages.json"
        if (-not (Test-Path -LiteralPath $f)) { continue }
        try {
            $m = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($prop in $m.PSObject.Properties) { if ($prop.Name -ieq $key) { return $prop.Value.message } }
        } catch { }
    }
    return $Name
}

# Namensmuster, die häufig zu Werbe-, Such-Umleitungs- oder Datensammel-Erweiterungen gehören (Hinweis, kein Urteil)
$Script:SuspiciousExtensionPattern = 'coupon|gutschein|shopping assistant|price ?comparison|safe ?search|search (manager|protect|baron)|quick ?search|pdf (converter|maker) online|weather (forecast|now)|new ?tab (search|plus)|video download(er)? (helper|pro)|hola|web ?companion|savefrom|mysearch|ask toolbar|conduit|crossrider|superfish|wajam'

function Get-BrowserExtensions {
    $list = New-Object System.Collections.Generic.List[object]
    foreach ($b in Get-ChromiumBrowsers) {
        foreach ($p in Get-ChromiumProfiles $b.Data) {
            $extRoot = Join-Path $p.FullName 'Extensions'
            if (-not (Test-Path -LiteralPath $extRoot)) { continue }
            foreach ($idDir in Get-ChildItem -LiteralPath $extRoot -Directory -ErrorAction SilentlyContinue) {
                $ver = Get-ChildItem -LiteralPath $idDir.FullName -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
                if (-not $ver) { continue }
                $mf = Join-Path $ver.FullName 'manifest.json'
                if (-not (Test-Path -LiteralPath $mf)) { continue }
                try { $m = Get-Content -LiteralPath $mf -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
                $name = Resolve-ExtensionName "$($m.name)" $ver.FullName "$($m.default_locale)"
                if ($name -match '^(Chrome|Edge|Microsoft) .*(Web Store|Payments|Wallet)$' -or $m.theme) { continue }
                $perms = @(@($m.permissions) + @($m.host_permissions) | Where-Object { $_ -is [string] })
                $broad = [bool]($perms | Where-Object { $_ -in '<all_urls>', 'http://*/*', 'https://*/*', '*://*/*', 'webRequest', 'webRequestBlocking', 'debugger', 'proxy', 'nativeMessaging' })
                $store = "$($m.update_url)" -match $b.Store -or -not $m.update_url
                $list.Add([pscustomobject]@{ Browser = $b.Name; Profile = $p.Name; Id = $idDir.Name; Name = $name; Version = "$($m.version)"; Broad = $broad; FromStore = $store; Suspicious = ($name -match $Script:SuspiciousExtensionPattern) })
            }
        }
    }
    $ff = Join-Path $env:APPDATA 'Mozilla\Firefox\Profiles'
    if (Test-Path -LiteralPath $ff) {
        foreach ($p in Get-ChildItem -LiteralPath $ff -Directory -ErrorAction SilentlyContinue) {
            $f = Join-Path $p.FullName 'extensions.json'
            if (-not (Test-Path -LiteralPath $f)) { continue }
            try { $j = Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json } catch { continue }
            foreach ($a in @($j.addons | Where-Object { $_.type -eq 'extension' -and $_.location -eq 'app-profile' })) {
                $name = "$($a.defaultLocale.name)"
                $list.Add([pscustomobject]@{ Browser = 'Firefox'; Profile = $p.Name; Id = $a.id; Name = $name; Version = "$($a.version)"; Broad = $false; FromStore = ($a.signedState -ge 2); Suspicious = ($name -match $Script:SuspiciousExtensionPattern) })
            }
        }
    }
    return $list.ToArray()
}

function Add-BrowserExtensionFindings {
    param([string]$Category)
    $ext = @(Get-BrowserExtensions)
    if (-not $ext) { return }
    $flagged = @($ext | Where-Object { $_.Suspicious -or (-not $_.FromStore -and $_.Broad) })
    $items = foreach ($g in $ext | Group-Object Browser) {
        "$($g.Name):"
        foreach ($e in $g.Group | Sort-Object Name) {
            $marks = @()
            if ($e.Suspicious) { $marks += 'typischer Name für Werbe-/Such-Erweiterungen' }
            if (-not $e.FromStore) { $marks += 'nicht aus dem offiziellen Store' }
            if ($e.Broad) { $marks += 'darf alle Webseiten lesen/ändern' }
            '   {0} {1}{2}' -f $e.Name, $e.Version, $(if ($marks) { "  ⚠ $($marks -join ', ')" } else { '' })
        }
    }
    $howTo = 'Entfernen im jeweiligen Browser: edge://extensions bzw. chrome://extensions in die Adresszeile eingeben (Firefox: about:addons).'
    if ($flagged) {
        Add-Finding $Category Warnung "$($flagged.Count) Browser-Erweiterung(en) prüfen" -Items @($items) `
            -Detail "Markierte Erweiterungen stammen nicht aus dem offiziellen Store und dürfen alle Webseiten lesen, oder tragen Namen, die häufig zu Werbe- und Such-Umleitungen gehören. Das ist ein Hinweis, kein Beweis – unbekannte oder nicht mehr genutzte Erweiterungen am besten entfernen. $howTo"
    } else {
        Add-Finding $Category OK "$($ext.Count) Browser-Erweiterung(en) – keine Auffälligkeiten" -Items @($items) -Detail "Erweiterungen, die man nicht mehr nutzt, trotzdem entfernen – jede kann Daten der besuchten Seiten lesen. $howTo"
    }
}
