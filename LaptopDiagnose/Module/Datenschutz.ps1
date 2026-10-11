<#
    Datenschutz-Einstellungen von Windows prüfen und nach Auswahl auf sparsame Werte setzen (umkehrbar),
    dazu: Welche Apps haben zuletzt Kamera und Mikrofon benutzt?
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

function Get-PrivacySettingsCatalog {
    <# Je Einstellung: Registry-Werte, empfohlener Wert und Erklärung. »Gut« = bereits datensparsam. #>
    $cdm = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
    @(
        @{ Key = 'Werbe-ID'; Label = 'Werbe-ID für personalisierte Werbung in Apps ausschalten'
            Values = @(@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo'; Name = 'Enabled'; Good = 0; Default = 1 }) }
        @{ Key = 'Massgeschneidert'; Label = 'Maßgeschneiderte Erfahrungen (Tipps und Werbung anhand der Diagnosedaten) ausschalten'
            Values = @(@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy'; Name = 'TailoredExperiencesWithDiagnosticDataEnabled'; Good = 0; Default = 1 }) }
        @{ Key = 'Diagnose'; Label = 'Optionale Diagnosedaten nicht senden (nur erforderliche)'
            Values = @(@{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection'; Name = 'AllowTelemetry'; Good = 1; Default = 3; GoodIfLower = $true }) }
        @{ Key = 'Vorschlaege'; Label = 'Vorschläge, Tipps und Werbung in Start, Einstellungen und Sperrbildschirm ausschalten'
            Values = @(
                @{ Path = $cdm; Name = 'SubscribedContent-338388Enabled'; Good = 0; Default = 1 }
                @{ Path = $cdm; Name = 'SubscribedContent-338389Enabled'; Good = 0; Default = 1 }
                @{ Path = $cdm; Name = 'SubscribedContent-353694Enabled'; Good = 0; Default = 1 }
                @{ Path = $cdm; Name = 'SubscribedContent-353696Enabled'; Good = 0; Default = 1 }
                @{ Path = $cdm; Name = 'SubscribedContent-338387Enabled'; Good = 0; Default = 1 }
                @{ Path = $cdm; Name = 'SystemPaneSuggestionsEnabled'; Good = 0; Default = 1 }
                @{ Path = $cdm; Name = 'RotatingLockScreenOverlayEnabled'; Good = 0; Default = 1 }) }
        @{ Key = 'AppAutoInstall'; Label = 'Automatisches Installieren beworbener Apps (z. B. Spiele) verhindern'
            Values = @(
                @{ Path = $cdm; Name = 'SilentInstalledAppsEnabled'; Good = 0; Default = 1 }
                @{ Path = $cdm; Name = 'OemPreInstalledAppsEnabled'; Good = 0; Default = 1 }
                @{ Path = $cdm; Name = 'PreInstalledAppsEnabled'; Good = 0; Default = 1 }) }
        @{ Key = 'Websuche'; Label = 'Websuche (Bing) im Startmenü ausschalten – lokale Suche bleibt'
            Values = @(@{ Path = 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'; Name = 'DisableSearchBoxSuggestions'; Good = 1; Default = 0 }) }
        @{ Key = 'Eingabe'; Label = 'Eingabe-Personalisierung (Sammeln von Tipp- und Handschriftdaten) ausschalten'
            Values = @(
                @{ Path = 'HKCU:\Software\Microsoft\InputPersonalization'; Name = 'RestrictImplicitTextCollection'; Good = 1; Default = 0 }
                @{ Path = 'HKCU:\Software\Microsoft\InputPersonalization'; Name = 'RestrictImplicitInkCollection'; Good = 1; Default = 0 }) }
        @{ Key = 'Feedback'; Label = 'Feedback-Anfragen von Windows ausschalten'
            Values = @(@{ Path = 'HKCU:\Software\Microsoft\Siuf\Rules'; Name = 'NumberOfSIUFInPeriod'; Good = 0; Default = $null }) }
        @{ Key = 'Sprachen'; Label = 'Webseiten keinen Zugriff auf die Sprachliste geben'
            Values = @(@{ Path = 'HKCU:\Control Panel\International\User Profile'; Name = 'HttpAcceptLanguageOptOut'; Good = 1; Default = 0 }) }
    )
}

function Test-PrivacySetting {
    param($Setting)
    foreach ($v in $Setting.Values) {
        $cur = $null
        try { $cur = (Get-ItemProperty -Path $v.Path -Name $v.Name -ErrorAction Stop).($v.Name) } catch { }
        if ($null -eq $cur) { $cur = $v.Default }
        if ($null -eq $cur) { return $false }
        if ($v.GoodIfLower) { if ([int]$cur -gt [int]$v.Good) { return $false } }
        elseif ([int]$cur -ne [int]$v.Good) { return $false }
    }
    return $true
}

function Set-RegistryValuesTracked {
    <# Setzt mehrere Registry-Werte und protokolliert sie als EINE umkehrbare Änderung. #>
    param([Parameter(Mandatory)]$Values, [Parameter(Mandatory)][string]$Beschreibung)
    $undo = @()
    foreach ($v in @($Values)) {
        $prev = $null; $existed = $false
        if (Test-Path $v.Path) {
            $item = Get-ItemProperty -Path $v.Path -Name $v.Name -ErrorAction SilentlyContinue
            if ($null -ne $item -and $item.PSObject.Properties[$v.Name]) { $prev = $item.($v.Name); $existed = $true }
        } else { $null = New-Item -Path $v.Path -Force }
        Set-ItemProperty -Path $v.Path -Name $v.Name -Value $v.Value -Type DWord -ErrorAction Stop
        $undo += @{ Path = $v.Path; Name = $v.Name; Type = 'DWord'; Existed = $existed; Previous = $prev }
    }
    Register-Change -Beschreibung $Beschreibung -Typ 'Registry' -Daten @{ Werte = $undo }
}

function Set-PrivacySettings {
    param($Settings)
    $values = @(); $names = @()
    foreach ($s in @($Settings)) {
        foreach ($v in $s.Values) { $values += @{ Path = $v.Path; Name = $v.Name; Value = $v.Good } }
        $names += $s.Label
    }
    if (-not $values) { return 'Nichts ausgewählt.' }
    Set-RegistryValuesTracked -Values $values -Beschreibung "Datenschutz: $($names -join '; ')"
    "$(@($Settings).Count) Datenschutz-Einstellung(en) gesetzt. Rückgängig über »Änderungen«. Einige Änderungen wirken erst nach einer Ab- und Anmeldung."
}

function Get-CapabilityUsage {
    <# Letzte Nutzung von Kamera bzw. Mikrofon je App (aus den Windows-Datenschutzdaten). #>
    param([ValidateSet('webcam', 'microphone')][string]$Capability)
    $base = "HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\$Capability"
    if (-not (Test-Path $base)) { return @() }
    $keys = @(Get-ChildItem -Path $base -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -ne 'NonPackaged' })
    $keys += @(Get-ChildItem -Path (Join-Path $base 'NonPackaged') -ErrorAction SilentlyContinue)
    foreach ($k in $keys) {
        $p = Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue
        if (-not $p.LastUsedTimeStart) { continue }
        $start = [datetime]::FromFileTime([long]$p.LastUsedTimeStart)
        $stop = if ($p.LastUsedTimeStop) { [datetime]::FromFileTime([long]$p.LastUsedTimeStop) } else { $null }
        $name = $k.PSChildName -replace '#', '\'
        if ($name -match '_[a-z0-9]{13}$') { $name = ($name -split '_')[0] }
        [pscustomobject]@{ App = $name; Last = $start; Active = (-not $stop -or $stop -lt $start) }
    }
}

function Add-PrivacyFindings {
    param([string]$Category)
    $catalog = Get-PrivacySettingsCatalog
    $open = @($catalog | Where-Object { -not (Test-PrivacySetting $_) })
    $done = @($catalog | Where-Object { Test-PrivacySetting $_ })
    $items = @($catalog | ForEach-Object { '{0}  {1}' -f $(if (Test-PrivacySetting $_) { '✔' } else { '–' }), $_.Label })
    if ($open) {
        Add-Finding $Category Info "Datenschutz: $($open.Count) von $($catalog.Count) Einstellungen geben mehr Daten preis als nötig" -Items $items `
            -Detail 'Windows sammelt standardmäßig mehr Nutzungsdaten als nötig und zeigt Werbung und »Vorschläge«. Die ausgewählten Einstellungen werden auf datensparsame Werte gesetzt – Funktionen von Windows bleiben erhalten. Alles ist über »Änderungen« umkehrbar.' `
            -SelectLabels @($open | ForEach-Object { $_.Label }) -SelectAllByDefault -FixData $open -FixLabel 'Ausgewählte Datenschutz-Einstellungen setzen' -Fix {
            param($d, $pre)
            if (-not $pre) {
                $all = @($d); for ($i = 0; $i -lt $all.Count; $i++) { Write-Host ('    {0,3}) {1}' -f ($i + 1), $all[$i].Label) }
                $sel = Read-Host '   Setzen: [A] alle, Nummern oder leer = keine'
                $d = if ($sel -match '^\s*(a|alle)\s*$') { $all } else { @((Read-Selection $sel $all.Count) | ForEach-Object { $all[$_] }) }
            }
            Set-PrivacySettings $d
        }
    } else {
        Add-Finding $Category OK 'Datenschutz-Einstellungen sind datensparsam eingestellt' -Items $items
    }

    $loc = $null
    try { $loc = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' -Name Value -ErrorAction Stop).Value } catch { }
    $usage = @()
    foreach ($cap in 'webcam', 'microphone') {
        $label = if ($cap -eq 'webcam') { 'Kamera' } else { 'Mikrofon' }
        foreach ($u in Get-CapabilityUsage $cap | Sort-Object Last -Descending | Select-Object -First 8) {
            $usage += '{0,-9} {1:dd.MM.yyyy HH:mm}  {2}{3}' -f $label, $u.Last, $u.App, $(if ($u.Active) { '   ← gerade in Benutzung' } else { '' })
        }
    }
    if ($usage -or $loc) {
        $items2 = @("Standortdienst: $(if ($loc -eq 'Deny') { 'aus' } elseif ($loc) { 'an' } else { 'unbekannt' })") + @($usage)
        Add-Finding $Category Info 'Kamera, Mikrofon und Standort: zuletzt genutzt von' -Items $items2 `
            -Detail 'Unbekannte Apps in dieser Liste prüfen und ihnen den Zugriff in den Windows-Einstellungen entziehen.' `
            -FixLabel 'Datenschutz-Einstellungen für Kamera und Mikrofon öffnen' -Fix { param($d) Start-Process 'ms-settings:privacy-webcam'; 'Einstellungen geöffnet.' }
    }
}
