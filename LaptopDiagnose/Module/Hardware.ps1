<#
    Hardware-Prüfungen, die vor allem bei Desktop-PCs Leistung kosten (helfen aber auch bei Laptops):
    Bildwiederholrate, Arbeitsspeicher-Takt und -Bestückung, Netzwerkkabel, Grafiktreiber, BIOS-Alter, Energie/Standby.
    Alle Prüfungen lesen nur. Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

function ConvertFrom-CimDate {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return $Value }
    try { return [Management.ManagementDateTimeConverter]::ToDateTime("$Value") } catch { return $null }
}

function Open-Url {
    param([string]$Url)
    # Über den Explorer öffnen: der Browser startet dann ohne Administratorrechte
    Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$Url`""
    "Seite geöffnet: $Url"
}

#region ---------- Bildwiederholrate ----------

function Get-MonitorModes {
    <# Vom Monitor gemeldete Anzeigemodi (aus den EDID-Daten): Auflösung und maximale Bildwiederholrate je Monitor. #>
    $names = @{}
    foreach ($id in @(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)) {
        $n = (@($id.UserFriendlyName) | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ }) -join ''
        $names[$id.InstanceName] = $n
    }
    foreach ($m in @(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorListedSupportedSourceModes -ErrorAction SilentlyContinue)) {
        $modes = foreach ($s in @($m.MonitorSourceModes)) {
            if (-not $s.VerticalRefreshRateDenominator) { continue }
            [pscustomobject]@{
                W  = [int]$s.HorizontalActivePixels
                H  = [int]$s.VerticalActivePixels
                Hz = [math]::Round([double]$s.VerticalRefreshRateNumerator / [double]$s.VerticalRefreshRateDenominator)
            }
        }
        [pscustomobject]@{ Name = $(if ($names[$m.InstanceName]) { $names[$m.InstanceName] } else { 'Monitor' }); Modes = @($modes) }
    }
}

function Add-RefreshRateFindings {
    param([string]$Category)
    $gpus = @(Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.CurrentRefreshRate -gt 0 -and $_.CurrentHorizontalResolution -gt 0 })
    if (-not $gpus) { return }
    $monitors = @(Get-MonitorModes)
    foreach ($g in $gpus) {
        $cur = [int]$g.CurrentRefreshRate
        $w = [int]$g.CurrentHorizontalResolution; $h = [int]$g.CurrentVerticalResolution
        # Monitor mit passender Auflösung suchen; bei mehreren Bildschirmen nur eindeutige Fälle bewerten
        $match = @($monitors | Where-Object { $_.Modes | Where-Object { $_.W -eq $w -and $_.H -eq $h } })
        if ($match.Count -ne 1) { if ($monitors.Count -eq 1) { $match = $monitors } else { continue } }
        $mon = $match[0]
        $best = @($mon.Modes | Where-Object { $_.W -eq $w -and $_.H -eq $h } | Measure-Object Hz -Maximum).Maximum
        if (-not $best) { $best = @($mon.Modes | Measure-Object Hz -Maximum).Maximum }
        if (-not $best) { continue }
        $text = "$($mon.Name) ($w × $h): $cur Hz"
        if ($best -ge 75 -and $best -ge $cur * 1.15) {
            Add-Finding $Category Warnung "Bildschirm läuft mit $cur Hz, kann aber $best Hz" `
                -Detail "$text. Windows stellt neue Monitore oft auf 60 Hz ein. Mit $best Hz wirken Mauszeiger, Scrollen und Spiele deutlich flüssiger. Einstellen unter »Anzeige › Erweiterte Anzeige › Bildwiederholfrequenz«. Bei mehreren Bildschirmen den richtigen auswählen; bei sehr hohen Raten ggf. DisplayPort- bzw. passendes HDMI-Kabel verwenden." `
                -FixLabel 'Erweiterte Anzeigeeinstellungen öffnen' -Fix { param($d) Start-Process 'ms-settings:display-advanced'; 'Anzeigeeinstellungen geöffnet – dort die höchste Bildwiederholfrequenz wählen.' }
        } else {
            Add-Finding $Category OK "Bildwiederholrate passt: $text"
        }
    }
}

#endregion

#region ---------- Arbeitsspeicher ----------

function Add-MemoryConfigFindings {
    param([string]$Category)
    $mods = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop | Where-Object { $_.Capacity -gt 0 })
    if (-not $mods) { return }
    $desktop = (Get-DeviceKind) -eq 'Desktop'
    $slots = [int](@(Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction SilentlyContinue | Measure-Object MemoryDevices -Sum).Sum)
    $typeNames = @{ 20 = 'DDR'; 21 = 'DDR2'; 24 = 'DDR3'; 26 = 'DDR4'; 34 = 'DDR5'; 35 = 'LPDDR5' }
    $type = $typeNames[[int]$mods[0].SMBIOSMemoryType]
    $configured = [int](@($mods | Where-Object { $_.ConfiguredClockSpeed -gt 0 } | Measure-Object ConfiguredClockSpeed -Minimum).Minimum)
    $rated = [int](@($mods | Where-Object { $_.Speed -gt 0 } | Measure-Object Speed -Minimum).Minimum)
    $items = @($mods | ForEach-Object { '{0}: {1} {2}, {3} MT/s (eingestellt {4} MT/s) – {5}' -f $_.DeviceLocator, (Format-Bytes ([double]$_.Capacity)), $type, $_.Speed, $_.ConfiguredClockSpeed, ("$($_.Manufacturer) $($_.PartNumber)").Trim() })
    $total = Format-Bytes ([double](($mods | Measure-Object Capacity -Sum).Sum))
    $summary = "$total in $($mods.Count) Modul(en)" + $(if ($slots) { " bei $slots Steckplätzen" } else { '' }) + $(if ($configured) { ", Takt $configured MT/s" } else { '' })

    # 1) Takt unter dem Nenntakt der Module
    if ($configured -and $rated -and $configured -lt $rated * 0.92) {
        $sev = if ($desktop) { 'Warnung' } else { 'Info' }
        Add-Finding $Category $sev "Arbeitsspeicher läuft langsamer als möglich ($configured statt $rated MT/s)" `
            -Detail 'Im BIOS/UEFI das Speicherprofil aktivieren (Intel: XMP, AMD: EXPO bzw. DOCP). Das bringt meist spürbar mehr Leistung, besonders bei Spielen und integrierter Grafik.' -Items $items
    } elseif ($desktop -and $configured -and (($type -eq 'DDR4' -and $configured -le 2400) -or ($type -eq 'DDR5' -and $configured -le 4800))) {
        # Ohne XMP/EXPO meldet Windows nur den Standardtakt – ein Hinweis ist dann sinnvoll
        Add-Finding $Category Info "Arbeitsspeicher läuft mit dem Standardtakt ($type-$configured)" `
            -Detail "Viele Speichermodule sind für mehr ausgelegt (z. B. $(if ($type -eq 'DDR4') { 'DDR4-3200 oder 3600' } else { 'DDR5-6000' }); steht auf dem Aufkleber bzw. im Datenblatt). Dann im BIOS/UEFI das Profil XMP bzw. EXPO/DOCP aktivieren." -Items $items
    }

    # 2) Nur ein Modul bei mehreren Steckplätzen = Single-Channel
    if ($mods.Count -eq 1 -and $slots -ge 2) {
        $sev = if ($desktop) { 'Warnung' } else { 'Info' }
        $detail = 'Mit nur einem Modul arbeitet der Speicher im Single-Channel-Betrieb und hat nur die halbe Bandbreite. Das kostet je nach Anwendung 10–30 % Leistung, mit integrierter Grafik noch mehr. Ein zweites, baugleiches Modul nachrüsten (Steckplatz laut Mainboard-Handbuch, meist A2/B2).'
        if (-not $desktop) { $detail += ' Bei Laptops ist ein Teil des Speichers oft fest verlötet – dann kann trotzdem Dual-Channel aktiv sein.' }
        Add-Finding $Category $sev 'Nur ein Speichermodul eingesetzt (Single-Channel)' -Detail $detail -Items $items
    } else {
        Add-Finding $Category OK "Arbeitsspeicher-Bestückung: $summary" -Items $items
    }
}

#endregion

#region ---------- Netzwerkkabel ----------

function Add-LanFindings {
    param([string]$Category)
    if (-not (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)) { return }
    $lan = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.MediaType -eq '802.3' -and $_.Status -eq 'Up' -and $_.InterfaceDescription -notmatch 'Virtual|Hyper-V|VPN|TAP|Bluetooth' })
    foreach ($a in $lan) {
        $bps = [double]$a.ReceiveLinkSpeed
        if (-not $bps) { $bps = [double]$a.Speed }
        $speedText = if ($bps -ge 1e9) { '{0:N1} Gbit/s' -f ($bps / 1e9) } else { '{0:N0} Mbit/s' -f ($bps / 1e6) }
        $name = "$($a.Name) ($($a.InterfaceDescription))"
        if ($bps -gt 0 -and $bps -le 100e6) {
            Add-Finding $Category Warnung "Netzwerkkabel nur mit $speedText verbunden" `
                -Detail "$name. Fast alle Netzwerkkarten und Router schaffen 1 Gbit/s. Nur 100 Mbit/s deutet auf ein beschädigtes oder zu einfaches Kabel (mindestens Cat 5e nötig), einen schlecht steckenden Stecker oder einen alten Switch/Port hin. Kabel tauschen bzw. einen anderen Router-Port testen."
        } elseif ($a.PSObject.Properties['FullDuplex'] -and $a.FullDuplex -eq $false) {
            Add-Finding $Category Warnung "Netzwerkverbindung im Halbduplex-Betrieb ($speedText)" -Detail "$name. Halbduplex bremst stark – meist ein Kabel- oder Portproblem."
        } else {
            Add-Finding $Category OK "Kabelverbindung: $speedText" -Detail $name
        }
        # Verbindungsabbrüche/Fehler des Netzwerktreibers (7 Tage)
        $driver = [IO.Path]::GetFileNameWithoutExtension("$($a.DriverFileName)")
        if ($driver) {
            $since = (Get-Date).AddDays(-7)
            $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = $driver; Level = 2, 3; StartTime = $since } -ErrorAction SilentlyContinue)
            if ($ev.Count -ge 5) {
                Add-Finding $Category Warnung "Netzwerkkarte meldete $($ev.Count) Verbindungsabbrüche oder Fehler (7 Tage)" `
                    -Detail "$name. Häufige Ursachen: Kabel/Stecker, Energiesparfunktionen der Netzwerkkarte, veralteter Treiber." `
                    -Items @($ev | Select-Object -First 8 | ForEach-Object { '{0:dd.MM. HH:mm}  {1}' -f $_.TimeCreated, (("$($_.Message)" -split "`r?`n")[0]) })
            }
        }
    }
}

#endregion

#region ---------- Grafiktreiber ----------

function Get-GpuVendorInfo {
    param([string]$Name)
    switch -Regex ($Name) {
        'NVIDIA|GeForce|Quadro|RTX' { return @{ Vendor = 'NVIDIA'; Tool = 'NVIDIA App'; Url = 'https://www.nvidia.com/de-de/software/nvidia-app/' } }
        'AMD|Radeon' { return @{ Vendor = 'AMD'; Tool = 'AMD Software: Adrenalin Edition'; Url = 'https://www.amd.com/de/support/download/drivers.html' } }
        'Intel' { return @{ Vendor = 'Intel'; Tool = 'Intel Driver & Support Assistant'; Url = 'https://www.intel.de/content/www/de/de/support/detect.html' } }
        default { return $null }
    }
}

function Add-GpuDriverFindings {
    param([string]$Category)
    foreach ($g in @(Get-CimInstance Win32_VideoController -ErrorAction Stop)) {
        $name = "$($g.Name)"
        if ($name -match 'Basic Display|Standard-VGA|Standard VGA|Microsoft Basic Render') {
            Add-Finding $Category Warnung "Kein passender Grafiktreiber installiert ($name)" `
                -Detail 'Windows nutzt nur einen Notfall-Treiber: keine Hardwarebeschleunigung, oft falsche Auflösung und Bildwiederholrate. Den Treiber des Grafikkarten- bzw. Geräteherstellers installieren.' `
                -FixLabel 'Windows-Update nach Treibern suchen lassen' -Fix { param($d) Start-Process 'ms-settings:windowsupdate'; 'Windows Update geöffnet – unter »Erweiterte Optionen › Optionale Updates« nach Treibern suchen.' }
            continue
        }
        if ($name -match 'Virtual|Remote|Parsec|Meta|DisplayLink|Citrix') { continue }
        $info = Get-GpuVendorInfo $name
        $date = ConvertFrom-CimDate $g.DriverDate
        if (-not $info -or -not $date) { continue }
        $months = [math]::Floor(((Get-Date) - $date).TotalDays / 30.4)
        $text = "$name – Treiber $($g.DriverVersion) vom $($date.ToString('dd.MM.yyyy'))"
        $fixLabel = "$($info.Tool) öffnen (Treiber aktualisieren)"
        $laptopHint = if ((Get-DeviceKind) -eq 'Laptop') { ' Bei Laptops bietet oft auch das Hersteller-Tool (z. B. MyASUS) geprüfte Grafiktreiber an.' } else { '' }
        if ($months -ge 12) {
            Add-Finding $Category Warnung "Grafiktreiber ist $months Monate alt" -Detail "$text. Neue Treiber bringen Fehlerbehebungen und oft mehr Leistung in Spielen und Videos. Empfohlen: $($info.Tool).$laptopHint" `
                -FixLabel $fixLabel -FixData $info.Url -Fix { param($d) Open-Url $d }
        } elseif ($months -ge 6) {
            Add-Finding $Category Info "Grafiktreiber ist $months Monate alt" -Detail "$text. Ein Update über $($info.Tool) lohnt sich.$laptopHint" `
                -FixLabel $fixLabel -FixData $info.Url -Fix { param($d) Open-Url $d }
        } else {
            Add-Finding $Category OK "Grafiktreiber aktuell: $text"
        }
    }
}

#endregion

#region ---------- BIOS ----------

function Get-BiosSupportUrl {
    param([string]$Vendor)
    switch -Regex ($Vendor) {
        'ASUS' { 'https://www.asus.com/de/support/' }
        'Micro-Star|MSI' { 'https://de.msi.com/support' }
        'Gigabyte' { 'https://www.gigabyte.com/de/Support' }
        'ASRock' { 'https://www.asrock.com/support/index.de.asp' }
        'LENOVO' { 'https://pcsupport.lenovo.com/de/de' }
        'Dell' { 'https://www.dell.com/support/home/de-de' }
        'HP|Hewlett' { 'https://support.hp.com/de-de/drivers' }
        'Acer' { 'https://www.acer.com/de-de/support' }
        'Medion' { 'https://www.medion.com/de/service/start/' }
        'Fujitsu' { 'https://support.ts.fujitsu.com/' }
        default { $null }
    }
}

function Add-BiosAgeFindings {
    param([string]$Category)
    $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
    $date = ConvertFrom-CimDate $bios.ReleaseDate
    if (-not $date) { return }
    $desktop = (Get-DeviceKind) -eq 'Desktop'
    $board = Get-CimInstance Win32_BaseBoard -ErrorAction SilentlyContinue
    $system = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    # Bei selbst gebauten PCs kommt das BIOS vom Mainboard-Hersteller, sonst vom Gerätehersteller
    $vendor = if ($desktop -and $board.Manufacturer) { "$($board.Manufacturer)" } else { "$($system.Manufacturer)" }
    $model = if ($desktop -and $board.Product) { "$($board.Product)" } else { "$($system.Model)" }
    $years = [math]::Round(((Get-Date) - $date).TotalDays / 365.25, 1)
    $text = "BIOS $($bios.SMBIOSBIOSVersion) vom $($date.ToString('dd.MM.yyyy')) – $vendor $model"
    if ($years -ge 3) {
        $url = Get-BiosSupportUrl $vendor
        $detail = "$text. BIOS-Updates beheben Stabilitäts- und Sicherheitsprobleme und verbessern oft die Unterstützung für Speicher und Prozessoren. Auf der Support-Seite nach »$model« suchen und prüfen, ob es eine neuere Version gibt. Wichtig: Ein BIOS-Update nur am Netzteil durchführen, nicht unterbrechen und genau nach Anleitung des Herstellers."
        if ($url) {
            Add-Finding $Category Info "BIOS ist $years Jahre alt" -Detail $detail -FixLabel "Support-Seite von $vendor öffnen" -FixData $url -Fix { param($d) Open-Url $d }
        } else {
            Add-Finding $Category Info "BIOS ist $years Jahre alt" -Detail $detail
        }
    } else {
        Add-Finding $Category OK "BIOS-Stand: $text"
    }
}

#endregion

#region ---------- Energie und Standby (Desktop) ----------

function Get-PowerSettingAc {
    <# Liest einen Wert (Sekunden) des aktiven Energiesparplans im Netzbetrieb. #>
    param([string]$SubGroup, [string]$Setting)
    $q = (& powercfg.exe /query SCHEME_CURRENT $SubGroup $Setting 2>$null | Out-String)
    $hex = @([regex]::Matches($q, '0x[0-9a-fA-F]{8}') | ForEach-Object { $_.Value })
    if ($hex.Count -ge 2) { return [Convert]::ToInt32($hex[-2], 16) }
    return $null
}

function Add-DesktopPowerFindings {
    param([string]$Category)
    if ((Get-DeviceKind) -ne 'Desktop') { return }
    $sleep = Get-PowerSettingAc 'SUB_SLEEP' 'STANDBYIDLE'
    $display = Get-PowerSettingAc 'SUB_VIDEO' 'VIDEOIDLE'
    $items = @()
    if ($null -ne $display) { $items += "Bildschirm aus nach: $(if ($display) { "$([math]::Round($display / 60)) Min." } else { 'nie' })" }
    if ($null -ne $sleep) { $items += "Energiesparmodus (Standby) nach: $(if ($sleep) { "$([math]::Round($sleep / 60)) Min." } else { 'nie' })" }
    if ($sleep -eq 0 -or $display -eq 0) {
        Add-Finding $Category Info 'PC schaltet bei Nichtbenutzung nie ab' -Items $items `
            -Detail 'Ein Desktop-PC verbraucht im Leerlauf oft 40–100 Watt. Bildschirm nach 10–15 Minuten aus und Standby nach 30–60 Minuten sparen Strom, ohne beim Arbeiten zu stören (Ausnahme: PCs, die nachts Downloads oder Backups erledigen).' `
            -FixLabel 'Einstellungen für Bildschirm und Energiesparmodus öffnen' -Fix { param($d) Start-Process 'ms-settings:powersleep'; 'Einstellungen geöffnet.' }
    } elseif ($items) {
        Add-Finding $Category OK 'Bildschirm- und Standby-Zeiten eingestellt' -Items $items
    }
}

#endregion
