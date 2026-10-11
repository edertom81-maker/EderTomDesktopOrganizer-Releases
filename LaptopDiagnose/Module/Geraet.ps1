<#
    Gerätecheck (z. B. beim Gebrauchtkauf) mit Bericht »Zustand des Geräts« sowie Garantie und Inventar:
    Hersteller, Modell, Seriennummer, Hardware-Übersicht, Link zur Garantieabfrage des Herstellers.
    Die interaktiven Tests laufen in einem eigenen Fenster-Prozess (Module\Fenster\Geraetetest.ps1).
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:WarrantyLinks = @(
    @{ Pattern = 'Lenovo'; Url = 'https://pcsupport.lenovo.com/warrantylookup' }
    @{ Pattern = 'HP|Hewlett'; Url = 'https://support.hp.com/checkwarranty' }
    @{ Pattern = 'Dell'; Url = 'https://www.dell.com/support/home/' }
    @{ Pattern = 'ASUS'; Url = 'https://www.asus.com/support/warranty-status-inquiry/' }
    @{ Pattern = 'Acer'; Url = 'https://www.acer.com/support' }
    @{ Pattern = 'Micro-Star|MSI'; Url = 'https://www.msi.com/support' }
    @{ Pattern = 'Microsoft'; Url = 'https://account.microsoft.com/devices' }
    @{ Pattern = 'Samsung'; Url = 'https://www.samsung.com/de/support/' }
    @{ Pattern = 'Medion'; Url = 'https://www.medion.com/de/service/' }
    @{ Pattern = 'Dynabook|Toshiba'; Url = 'https://support.dynabook.com/' }
    @{ Pattern = 'Apple'; Url = 'https://checkcoverage.apple.com/' }
)

function Test-RealSerial {
    param([string]$Serial)
    $s = "$Serial".Trim()
    return [bool]($s -and $s -notmatch '(?i)^(to be filled|default string|system serial|none|n/?a|0+|123456789|chassis serial|not applicable|o\.e\.m\.)')
}

function ConvertFrom-WmiChars {
    param($Chars)
    (@($Chars) | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ }) -join ''
}

function Get-BatteryState {
    $static = Get-CimInstance -Namespace root/wmi -ClassName BatteryStaticData -ErrorAction SilentlyContinue | Select-Object -First 1
    $full = Get-CimInstance -Namespace root/wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue | Select-Object -First 1
    $cyc = Get-CimInstance -Namespace root/wmi -ClassName BatteryCycleCount -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $static -or -not $full -or -not $static.DesignedCapacity) { return $null }
    [pscustomobject]@{
        Design = [double]$static.DesignedCapacity; Full = [double]$full.FullChargedCapacity
        Health = [math]::Round(100 * [double]$full.FullChargedCapacity / [double]$static.DesignedCapacity)
        Cycles = $(if ($cyc -and $cyc.CycleCount) { [int]$cyc.CycleCount } else { $null })
    }
}

function ConvertTo-HealthText {
    param($Status)
    switch ("$Status") { 'Healthy' { 'gesund' } 'Warning' { 'Warnung' } 'Unhealthy' { 'defekt' } default { "$Status" } }
}

function Get-DeviceInventory {
    <# Hardware-Übersicht in Abschnitten (für Inventar-Datei, Gerätecheck-Bericht und Karte). #>
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
    $prod = Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cpu = @(Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue)
    $serial = "$($bios.SerialNumber)".Trim()
    if (-not (Test-RealSerial $serial)) { $serial = "$($prod.IdentifyingNumber)".Trim() }
    $hasSerial = Test-RealSerial $serial
    $act = $null
    try { $act = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" -ErrorAction Stop | Select-Object -First 1 } catch { }
    $winVer = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue)
    $sections = [ordered]@{}
    $sections['Gerät'] = @(
        "Hersteller: $($cs.Manufacturer)"
        "Modell: $($cs.Model)$(if ($prod.Version -and $prod.Version -ne $cs.Model) { " ($($prod.Version))" })"
        "Seriennummer: $(if ($hasSerial) { $serial } else { 'nicht hinterlegt (z. B. selbst gebauter PC)' })"
        "BIOS: $($bios.SMBIOSBIOSVersion) vom $(if ($bios.ReleaseDate) { ([datetime]$bios.ReleaseDate).ToString('dd.MM.yyyy') } else { '?' })"
        "Windows: $($os.Caption) $($winVer.DisplayVersion) (Build $($os.BuildNumber)), installiert am $(if ($os.InstallDate) { ([datetime]$os.InstallDate).ToString('dd.MM.yyyy') } else { '?' })"
        "Aktivierung: $(if ($act) { if ([int]$act.LicenseStatus -eq 1) { 'aktiviert' } else { "nicht aktiviert (Status $($act.LicenseStatus))" } } else { 'unbekannt' })"
    )
    $sections['Prozessor'] = @($cpu | ForEach-Object { "$("$($_.Name)".Trim()) – $($_.NumberOfCores) Kerne / $($_.NumberOfLogicalProcessors) Threads" })
    $mem = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
    $sections['Arbeitsspeicher'] = @("Gesamt: $(Format-Bytes ([double]$cs.TotalPhysicalMemory))") + @($mem | ForEach-Object {
            '{0}: {1} {2} {3} MHz{4}' -f $_.DeviceLocator, (Format-Bytes ([double]$_.Capacity)), "$($_.Manufacturer) $("$($_.PartNumber)".Trim())".Trim(), $_.ConfiguredClockSpeed, $(if (Test-RealSerial $_.SerialNumber) { ", SN $("$($_.SerialNumber)".Trim())" } else { '' })
        })
    $disks = @(Get-PhysicalDisk -ErrorAction SilentlyContinue)
    $sections['Datenträger'] = @($disks | ForEach-Object {
            $rel = $null; try { $rel = $_ | Get-StorageReliabilityCounter -ErrorAction Stop } catch { }
            '{0} ({1}, {2}) – Zustand: {3}{4}{5}{6}' -f $_.FriendlyName, $_.MediaType, (Format-Bytes ([double]$_.Size)), (ConvertTo-HealthText $_.HealthStatus), $(if ($rel.Wear -ne $null) { ", Abnutzung $($rel.Wear) %" }), $(if ($rel.PowerOnHours) { ", $($rel.PowerOnHours) Betriebsstunden" }), $(if (Test-RealSerial $_.SerialNumber) { ", SN $("$($_.SerialNumber)".Trim())" })
        })
    $sections['Grafik'] = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name) (Treiber $($_.DriverVersion))" })
    $mons = @(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue)
    if ($mons) { $sections['Bildschirme'] = @($mons | ForEach-Object { "$(ConvertFrom-WmiChars $_.ManufacturerName) $(ConvertFrom-WmiChars $_.UserFriendlyName)$(if ((ConvertFrom-WmiChars $_.SerialNumberID) -match '\w{3,}') { ", SN $(ConvertFrom-WmiChars $_.SerialNumberID)" })".Trim() }) }
    $sections['Netzwerk'] = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name): $($_.InterfaceDescription) – MAC $($_.MacAddress)" })
    $bat = Get-BatteryState
    if ($bat) { $sections['Akku'] = @("Gesundheit: $($bat.Health) % ($([math]::Round($bat.Full / 1000, 1)) von $([math]::Round($bat.Design / 1000, 1)) Wh)$(if ($null -ne $bat.Cycles) { ", $($bat.Cycles) Ladezyklen" })") }
    [pscustomobject]@{ Manufacturer = "$($cs.Manufacturer)"; Model = "$($cs.Model)"; Serial = $(if ($hasSerial) { $serial } else { '' }); Sections = $sections; Battery = $bat; Disks = $disks }
}

function Get-WarrantyUrl {
    param([string]$Manufacturer)
    foreach ($w in $Script:WarrantyLinks) { if ($Manufacturer -match $w.Pattern) { return $w.Url } }
    return $null
}

function Export-Inventory {
    $inv = Get-DeviceInventory
    if (-not (Test-Path -LiteralPath $BerichtOrdner)) { $null = New-Item -ItemType Directory -Path $BerichtOrdner -Force }
    $file = Join-Path $BerichtOrdner ('Inventar_{0}_{1:yyyyMMdd_HHmm}.txt' -f $env:COMPUTERNAME, (Get-Date))
    $lines = @("PC Repair Pro – Inventar von $env:COMPUTERNAME, erstellt am $(Get-Date -Format 'dd.MM.yyyy HH:mm')", '')
    foreach ($k in $inv.Sections.Keys) { $lines += $k.ToUpperInvariant(); $lines += @($inv.Sections[$k] | ForEach-Object { "  $_" }); $lines += '' }
    $url = Get-WarrantyUrl $inv.Manufacturer
    if ($url) { $lines += "Garantieabfrage: $url" }
    [IO.File]::WriteAllLines($file, [string[]]$lines, (New-Object Text.UTF8Encoding($true)))
    [pscustomobject]@{ Inventory = $inv; File = $file; Url = $url }
}

function Add-InventoryToolFinding {
    param([string]$Category)
    Add-Finding $Category Info 'Garantie und Inventar' -Silent -Repeatable `
        -Detail 'Liest Hersteller, Modell, Seriennummer und alle wichtigen Bauteile aus (Prozessor, Arbeitsspeicher, Datenträger, Grafik, Bildschirme, Netzwerk, Akku), speichert sie als Inventar-Datei im Berichtordner und öffnet die Garantieabfrage des Herstellers – die Seriennummer liegt dann in der Zwischenablage.' `
        -FixLabel 'Inventar erstellen und Garantie prüfen' -FixData @{ Category = $Category } -Fix {
        param($d)
        $r = Export-Inventory
        $inv = $r.Inventory
        if ($inv.Serial) { try { Set-Clipboard -Value $inv.Serial -ErrorAction Stop } catch { } }
        if ($r.Url) { Start-Process $r.Url }
        $items = @(foreach ($k in $inv.Sections.Keys) { "— $k —"; @($inv.Sections[$k]) })
        Remove-FindingByKey 'Inventar'
        Add-Finding $d.Category Info "Inventar: $($inv.Manufacturer) $($inv.Model)$(if ($inv.Serial) { ", SN $($inv.Serial)" })" -Key 'Inventar' -Items $items `
            -Detail ("Gespeichert unter $($r.File)." + $(if ($r.Url) { " Garantieabfrage: $($r.Url)$(if ($inv.Serial) { ' – Seriennummer ist in der Zwischenablage (Strg+V).' })" } else { ' Für diesen Hersteller ist keine Garantieabfrage hinterlegt – auf der Support-Seite des Herstellers mit der Seriennummer suchen.' }))
        "Inventar gespeichert: $($r.File)$(if ($r.Url) { ' – Garantieabfrage geöffnet.' })"
    }
}

function New-DeviceReportHtml {
    param($Inventory, $Tests, [string[]]$Verdict)
    $enc = { param($t) [System.Net.WebUtility]::HtmlEncode("$t") }
    $sb = New-Object System.Text.StringBuilder
    $null = $sb.Append('<!DOCTYPE html><html lang="de"><head><meta charset="utf-8"><title>Zustand des Geräts</title><style>body{font-family:Segoe UI,Arial,sans-serif;margin:32px;color:#101828;background:#f5f7fa}h1{margin:0 0 4px}.sub{color:#667085;margin-bottom:20px}.card{background:#fff;border:1px solid #e4e7ec;border-radius:10px;padding:14px 18px;margin-bottom:14px}h2{font-size:16px;margin:0 0 8px}li{margin:3px 0}.ok{color:#079455}.bad{color:#d92d20}.mid{color:#dc6803}</style></head><body>')
    $null = $sb.Append("<h1>Zustand des Geräts</h1><div class=""sub"">$(& $enc "$($Inventory.Manufacturer) $($Inventory.Model)") · erstellt am $(Get-Date -Format 'dd.MM.yyyy HH:mm') mit PC Repair Pro</div>")
    $null = $sb.Append('<div class="card"><h2>Ergebnis</h2><ul>')
    foreach ($v in $Verdict) { $cls = if ($v -match '^✔') { 'ok' } elseif ($v -match '^✖') { 'bad' } else { 'mid' }; $null = $sb.Append("<li class=""$cls"">$(& $enc $v)</li>") }
    $null = $sb.Append('</ul></div>')
    foreach ($k in $Inventory.Sections.Keys) {
        $null = $sb.Append("<div class=""card""><h2>$(& $enc $k)</h2><ul>")
        foreach ($l in @($Inventory.Sections[$k])) { $null = $sb.Append("<li>$(& $enc $l)</li>") }
        $null = $sb.Append('</ul></div>')
    }
    $null = $sb.Append('</body></html>')
    return $sb.ToString()
}

function Invoke-DeviceCheck {
    param([string]$Category = 'Werkzeuge')
    $json = Join-Path $env:TEMP ('PCRepairPro_Geraetetest_{0}.json' -f [guid]::NewGuid().ToString('N'))
    $script = Join-Path $Script:InstallDir 'Module\Fenster\Geraetetest.ps1'
    if (-not (Test-Path -LiteralPath $script)) { throw "Gerätecheck-Fenster nicht gefunden: $script" }
    $exe = (Get-Process -Id $PID).Path
    Write-Host '     › Gerätecheck läuft im eigenen Fenster – bitte den Anweisungen dort folgen …' -ForegroundColor Gray
    Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', "`"$script`"", '-Ergebnis', "`"$json`"") -Wait
    $tests = $null
    if (Test-Path -LiteralPath $json) { try { $tests = Get-Content -LiteralPath $json -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }; Remove-Item -LiteralPath $json -Force -ErrorAction SilentlyContinue }
    if (-not $tests -or $tests.Abgebrochen) { return 'Gerätecheck abgebrochen.' }
    $inv = Get-DeviceInventory
    $verdict = @(); $bad = 0
    $kb = $tests.Tastatur
    if ($kb) {
        if (@($kb.Fehlend).Count -eq 0) { $verdict += "✔ Tastatur: alle $($kb.Gesamt) Tasten funktionieren" }
        else { $verdict += "• Tastatur: $($kb.Erkannt) von $($kb.Gesamt) Tasten erkannt – nicht gedrückt bzw. defekt: $(@($kb.Fehlend) -join ' ')"; if (@($kb.Fehlend).Count -gt 3) { $bad++ } }
    }
    foreach ($t in @(@('Bildschirm', $tests.Bildschirm), @('Lautsprecher', $tests.Lautsprecher), @('Kamera', $tests.Kamera), @('Mikrofon', $tests.Mikrofon))) {
        if (-not $t[1]) { continue }
        if ($t[1] -eq 'in Ordnung') { $verdict += "✔ $($t[0]): in Ordnung" }
        elseif ($t[1] -in 'übersprungen', 'nicht beurteilt') { $verdict += "• $($t[0]): $($t[1])" }
        else { $verdict += "✖ $($t[0]): $($t[1])"; $bad++ }
    }
    if ($inv.Battery) {
        $h = $inv.Battery.Health
        $verdict += $(if ($h -ge 80) { '✔' } elseif ($h -ge 60) { '•' } else { '✖' }) + " Akku: $h % der ursprünglichen Kapazität$(if ($null -ne $inv.Battery.Cycles) { ", $($inv.Battery.Cycles) Ladezyklen" })"
        if ($h -lt 60) { $bad++ }
    }
    foreach ($dk in @($inv.Disks)) {
        $ok = "$($dk.HealthStatus)" -eq 'Healthy'
        $verdict += $(if ($ok) { '✔' } else { '✖' }) +  " Datenträger $($dk.FriendlyName): $(ConvertTo-HealthText $dk.HealthStatus)"
        if (-not $ok) { $bad++ }
    }
    if (-not (Test-Path -LiteralPath $BerichtOrdner)) { $null = New-Item -ItemType Directory -Path $BerichtOrdner -Force }
    $html = Join-Path $BerichtOrdner ('Geraetezustand_{0:yyyyMMdd_HHmm}.html' -f (Get-Date))
    [IO.File]::WriteAllText($html, (New-DeviceReportHtml -Inventory $inv -Tests $tests -Verdict $verdict), (New-Object Text.UTF8Encoding($true)))
    Invoke-Item -LiteralPath $html
    Remove-FindingByKey 'Geraetecheck'
    Add-Finding $Category $(if ($bad) { 'Warnung' } else { 'OK' }) "Gerätecheck: $(if ($bad) { "$bad Auffälligkeit(en)" } else { 'keine Auffälligkeiten' })" -Key 'Geraetecheck' -Items $verdict -Detail "Bericht »Zustand des Geräts«: $html"
    "Gerätecheck abgeschlossen – Bericht geöffnet ($html)."
}

function Add-DeviceCheckToolFinding {
    param([string]$Category)
    Add-Finding $Category Info 'Gerätecheck (z. B. beim Gebrauchtkauf)' -Silent -Repeatable `
        -Detail 'Testet Schritt für Schritt Tastatur (jede Taste leuchtet auf), Bildschirm (Pixelfehler), Lautsprecher links/rechts, Kamera und Mikrofon und fasst alles mit Akkuzustand, Datenträger-Gesundheit und Seriennummern im Bericht »Zustand des Geräts« zusammen – ideal vor dem Kauf oder Verkauf eines gebrauchten Geräts.' `
        -FixLabel 'Gerätecheck starten' -FixData @{ Category = $Category } -Fix { param($d) Invoke-DeviceCheck -Category $d.Category }
}
