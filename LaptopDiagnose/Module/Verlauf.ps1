<#
    Verlauf: Kennzahlen jeder Komplett-Diagnose speichern, Trends berechnen, Geräteübersicht erstellen.
    Teil von LaptopDiagnose – Copyright 2026 by Eder Tom
#>

$Script:MetricCatalog = [ordered]@{
    'Gesundheitswert'   = @{ Label = 'Gesundheitswert'; Unit = ''; Better = 'hoch' }
    'Kritisch'          = @{ Label = 'Kritische Probleme'; Unit = ''; Better = 'niedrig' }
    'Warnungen'         = @{ Label = 'Warnungen'; Unit = ''; Better = 'niedrig' }
    'AkkuGesundheit'    = @{ Label = 'Akku-Gesundheit'; Unit = '%'; Better = 'hoch' }
    'AkkuZyklen'        = @{ Label = 'Ladezyklen'; Unit = ''; Better = 'niedrig' }
    'Startdauer'        = @{ Label = 'Systemstart'; Unit = 's'; Better = 'niedrig' }
    'Herunterfahren'    = @{ Label = 'Herunterfahren'; Unit = 's'; Better = 'niedrig' }
    'FreierSpeicher'    = @{ Label = 'Freier Speicher (Systemlaufwerk)'; Unit = 'GB'; Better = 'hoch' }
    'RAMAuslastung'     = @{ Label = 'RAM-Auslastung'; Unit = '%'; Better = 'niedrig' }
    'CPULast'           = @{ Label = 'Prozessorlast im Leerlauf'; Unit = '%'; Better = 'niedrig' }
    'Temperatur'        = @{ Label = 'Temperatur'; Unit = '°C'; Better = 'niedrig' }
    'Datenmuell'        = @{ Label = 'Datenmüll'; Unit = 'GB'; Better = 'niedrig' }
    'Autostarts'        = @{ Label = 'Autostart-Programme'; Unit = ''; Better = 'niedrig' }
    'Programmabstuerze' = @{ Label = 'Programmabstürze (7 Tage)'; Unit = ''; Better = 'niedrig' }
    'ProgrammHaenger'   = @{ Label = 'Programm-Hänger (7 Tage)'; Unit = ''; Better = 'niedrig' }
    'Bluescreens'       = @{ Label = 'Bluescreens (7 Tage)'; Unit = ''; Better = 'niedrig' }
    'Ereignisfehler'    = @{ Label = 'Fehler im Ereignisprotokoll (7 Tage)'; Unit = ''; Better = 'niedrig' }
    'SoftwareUpdates'   = @{ Label = 'Offene Programm-Updates'; Unit = ''; Better = 'niedrig' }
    'WindowsUpdates'    = @{ Label = 'Offene Windows-Updates'; Unit = ''; Better = 'niedrig' }
    'TreiberUpdates'    = @{ Label = 'Offene Treiber-Updates'; Unit = ''; Better = 'niedrig' }
    'WLANSignal'        = @{ Label = 'WLAN-Signal'; Unit = '%'; Better = 'hoch' }
    'Download'          = @{ Label = 'Download-Geschwindigkeit'; Unit = 'Mbit/s'; Better = 'hoch' }
    'Latenz'            = @{ Label = 'Latenz (Ping)'; Unit = 'ms'; Better = 'niedrig' }
}
$Script:Metrics = [ordered]@{}

function Set-Metric {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Value)
    if ($null -eq $Value) { return }
    $Script:Metrics[$Name] = [math]::Round([double]$Value, 1)
}

function Get-HealthScore {
    $open = @($Script:Findings | Where-Object { -not $_.Fixed })
    $crit = @($open | Where-Object { $_.Severity -eq 'Kritisch' }).Count
    $warn = @($open | Where-Object { $_.Severity -eq 'Warnung' }).Count
    return [pscustomobject]@{ Score = [math]::Max(0, 100 - 15 * $crit - 5 * $warn); Kritisch = $crit; Warnungen = $warn }
}

function Get-HistoryFolder { Join-Path $BerichtOrdner 'Verlauf' }

function Save-History {
    $h = Get-HealthScore
    Set-Metric 'Gesundheitswert' $h.Score
    Set-Metric 'Kritisch' $h.Kritisch
    Set-Metric 'Warnungen' $h.Warnungen
    $folder = Get-HistoryFolder
    if (-not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
    $entry = [ordered]@{
        Zeit        = (Get-Date).ToString('s')
        Computer    = $env:COMPUTERNAME
        Modell      = $(if ($Script:SystemInfo) { "$($Script:SystemInfo['Hersteller']) $($Script:SystemInfo['Modell'])" })
        ToolVersion = $Script:ToolVersion
        Metriken    = $Script:Metrics
        # In den Einstellungen abgewählte Bereiche dieser Komplett-Diagnose
        Ohne        = @($Script:LastFullScanSkipped | ForEach-Object { $Script:Categories[$_] })
    }
    $file = Join-Path $folder ('{0}_{1:yyyyMMdd_HHmmss}.json' -f $env:COMPUTERNAME, (Get-Date))
    [IO.File]::WriteAllText($file, ($entry | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding $false))
    return $file
}

function Get-HistoryEntries {
    param([string]$Computer = $env:COMPUTERNAME)
    $folder = Get-HistoryFolder
    if (-not (Test-Path -LiteralPath $folder)) { return @() }
    $list = foreach ($f in Get-ChildItem -LiteralPath $folder -Filter '*.json' -File -ErrorAction SilentlyContinue) {
        try {
            $e = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if (-not $Computer -or $e.Computer -eq $Computer) { $e }
        } catch { }
    }
    return @($list | Sort-Object { [datetime]$_.Zeit })
}

function Format-MetricValue {
    param($Value, [string]$Unit)
    $txt = if ([math]::Abs([double]$Value - [math]::Round([double]$Value)) -lt 0.05) { '{0:N0}' -f $Value } else { '{0:N1}' -f $Value }
    if ($Unit) { $txt += " $Unit" }
    return $txt
}

function Get-MetricSeries {
    <# Liefert je Kennzahl die Werte über die Zeit samt Veränderung und Bewertung. #>
    param([string]$Name, $Entries)
    if ($null -eq $Entries) { $Entries = Get-HistoryEntries }
    $names = if ($Name) { @($Name) } else { @($Script:MetricCatalog.Keys) }
    $result = foreach ($n in $names) {
        $def = $Script:MetricCatalog[$n]
        $points = @(foreach ($e in $Entries) {
                $v = $e.Metriken.$n
                if ($null -ne $v) { [pscustomobject]@{ Zeit = [datetime]$e.Zeit; Wert = [double]$v } }
            })
        if (-not $points) { continue }
        $cur = $points[-1].Wert
        $change = $null; $trend = 'gleich'; $text = 'erste Messung'; $perMonth = $null
        if ($points.Count -ge 2) {
            $first = $points[0]
            $change = $cur - $first.Wert
            if ([math]::Abs($change) -ge 0.05) {
                $improved = if ($def.Better -eq 'hoch') { $change -gt 0 } else { $change -lt 0 }
                $trend = if ($improved) { 'besser' } else { 'schlechter' }
            }
            $sign = if ($change -gt 0) { '+' } elseif ($change -lt 0) { '−' } else { '±' }
            $text = '{0}{1} seit {2:dd.MM.yyyy}' -f $sign, (Format-MetricValue ([math]::Abs($change)) $def.Unit), $first.Zeit
            # Lineare Regression für den Verlauf pro Monat (ab 14 Tagen und 3 Messungen)
            $spanDays = ($points[-1].Zeit - $first.Zeit).TotalDays
            if ($points.Count -ge 3 -and $spanDays -ge 14) {
                $xs = @($points | ForEach-Object { ($_.Zeit - $first.Zeit).TotalDays })
                $ys = @($points | ForEach-Object { $_.Wert })
                $mx = ($xs | Measure-Object -Average).Average
                $my = ($ys | Measure-Object -Average).Average
                $num = 0.0; $den = 0.0
                for ($i = 0; $i -lt $xs.Count; $i++) { $num += ($xs[$i] - $mx) * ($ys[$i] - $my); $den += [math]::Pow($xs[$i] - $mx, 2) }
                if ($den -gt 0) { $perMonth = [math]::Round($num / $den * 30, 2) }
            }
        }
        [pscustomobject]@{
            Name      = $n
            Label     = $def.Label
            Unit      = $def.Unit
            Better    = $def.Better
            Current   = $cur
            ValueText = Format-MetricValue $cur $def.Unit
            Change    = $change
            Trend     = $trend
            TrendText = $text
            PerMonth  = $perMonth
            Values    = [double[]]@($points | ForEach-Object { $_.Wert })
            Dates     = [string[]]@($points | ForEach-Object { $_.Zeit.ToString('dd.MM.yy') })
        }
    }
    return @($result)
}

function New-SparklineSvg {
    param([double[]]$Values, [int]$Width = 160, [int]$Height = 36, [string]$Color = '#1570EF')
    if (-not $Values -or $Values.Count -lt 2) { return '' }
    $min = ($Values | Measure-Object -Minimum).Minimum
    $max = ($Values | Measure-Object -Maximum).Maximum
    $range = if ($max -eq $min) { 1 } else { $max - $min }
    $ptsText = (@(for ($i = 0; $i -lt $Values.Count; $i++) {
                $x = 2 + ($Width - 4) * $i / ($Values.Count - 1)
                $y = ($Height - 3) - ($Height - 6) * ($Values[$i] - $min) / $range
                [string]::Format([Globalization.CultureInfo]::InvariantCulture, '{0:0.#},{1:0.#}', $x, $y)
            })) -join ' '
    return "<svg width=""$Width"" height=""$Height"" viewBox=""0 0 $Width $Height"" xmlns=""http://www.w3.org/2000/svg""><polyline fill=""none"" stroke=""$Color"" stroke-width=""2"" stroke-linejoin=""round"" stroke-linecap=""round"" points=""$ptsText""/></svg>"
}

function Show-HistoryConsole {
    Write-Title 'Verlauf'
    $series = @(Get-MetricSeries)
    if (-not $series) { Write-Host '   Noch kein Verlauf vorhanden – nach jeder Komplett-Diagnose wird ein Messpunkt gespeichert.' -ForegroundColor Gray; return }
    $n = @(Get-HistoryEntries).Count
    Write-Host "   $n Messung(en) gespeichert.`n" -ForegroundColor DarkGray
    foreach ($s in $series) {
        $color = switch ($s.Trend) { 'besser' { 'Green' } 'schlechter' { 'Yellow' } default { 'Gray' } }
        Write-Host ('   {0,-38} {1,12}   ' -f $s.Label, $s.ValueText) -NoNewline
        Write-Host $s.TrendText -ForegroundColor $color
    }
}

function Export-FleetOverview {
    <# Liest die JSON-Berichte mehrerer Geräte aus einem Ordner und erstellt eine Vergleichsübersicht. #>
    param([Parameter(Mandatory)][string]$Ordner)
    if (-not (Test-Path -LiteralPath $Ordner)) { throw "Ordner nicht gefunden: $Ordner" }
    $reports = foreach ($f in Get-ChildItem -LiteralPath $Ordner -Filter 'Diagnosebericht_*.json' -File -Recurse -ErrorAction SilentlyContinue) {
        try {
            $r = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($r.System.Computer) {
                $time = if ($r.Erstellt) { [datetime]$r.Erstellt } else { $f.LastWriteTime }
                [pscustomobject]@{ Report = $r; Zeit = $time }
            }
        } catch { }
    }
    $latest = @($reports | Group-Object { $_.Report.System.Computer } | ForEach-Object { $_.Group | Sort-Object Zeit | Select-Object -Last 1 } | Sort-Object { $_.Report.System.Computer })
    if (-not $latest) { throw 'In diesem Ordner wurden keine Diagnoseberichte (Diagnosebericht_*.json) gefunden.' }

    $e = { param($t) [System.Net.WebUtility]::HtmlEncode("$t") }
    $rows = foreach ($x in $latest) {
        $r = $x.Report
        $m = $r.Metriken
        $score = if ($null -ne $r.Gesundheitswert) { [int]$r.Gesundheitswert } else { $null }
        $scoreColor = if ($null -eq $score) { '#5d6b80' } elseif ($score -ge 80) { '#079455' } elseif ($score -ge 50) { '#dc8a00' } else { '#d92d20' }
        $crit = @($r.Findings | Where-Object { $_.Severity -eq 'Kritisch' -and -not $_.Fixed }).Count
        $warn = @($r.Findings | Where-Object { $_.Severity -eq 'Warnung' -and -not $_.Fixed }).Count
        $upd = '{0} / {1} / {2}' -f $(if ($null -ne $m.SoftwareUpdates) { $m.SoftwareUpdates } else { '–' }), $(if ($null -ne $m.WindowsUpdates) { $m.WindowsUpdates } else { '–' }), $(if ($null -ne $m.TreiberUpdates) { $m.TreiberUpdates } else { '–' })
        "<tr><td><b>$(& $e $r.System.Computer)</b><br><span class=""sub"">$(& $e "$($r.System.Hersteller) $($r.System.Modell)")</span></td>" +
        "<td>$(& $e $r.System.Betriebssystem)</td><td>$('{0:dd.MM.yyyy HH:mm}' -f $x.Zeit)</td>" +
        "<td style=""color:$scoreColor;font-weight:700;font-size:20px"">$(if ($null -ne $score) { $score } else { '–' })</td>" +
        "<td><span class=""c"">$crit</span> / <span class=""w"">$warn</span></td>" +
        "<td>$(if ($null -ne $m.AkkuGesundheit) { "$($m.AkkuGesundheit) %" } else { '–' })</td>" +
        "<td>$(if ($null -ne $m.FreierSpeicher) { "$($m.FreierSpeicher) GB" } else { '–' })</td><td>$upd</td></tr>"
    }
    $html = @"
<!DOCTYPE html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Geräteübersicht</title><style>
body{margin:0;background:#f5f7fa;color:#1d2533;font:15px/1.5 "Segoe UI",system-ui,sans-serif}.wrap{max-width:1200px;margin:0 auto;padding:24px 16px}
h1{margin:0 0 4px}.sub{color:#5d6b80;font-size:13px}table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #e3e8ef;border-radius:12px;overflow:hidden;margin-top:18px}
th,td{padding:10px 12px;border-bottom:1px solid #e3e8ef;text-align:left;vertical-align:top}th{background:#eef2f7;font-size:13px;color:#3b4a60}
td:nth-child(n+3){white-space:nowrap}.c{color:#d92d20;font-weight:700}.w{color:#dc8a00;font-weight:700}.scroll{overflow-x:auto}
</style></head><body><div class="wrap"><h1>Geräteübersicht</h1><div class="sub">$($latest.Count) Gerät(e) · jeweils letzter Bericht · erstellt am $((Get-Date).ToString('dd.MM.yyyy HH:mm'))</div>
<div class="scroll"><table><tr><th>Gerät</th><th>Windows</th><th>Letzte Diagnose</th><th>Gesundheit</th><th>Kritisch / Warnungen</th><th>Akku</th><th>Frei (System)</th><th>Updates Prog. / Win / Treiber</th></tr>
$($rows -join "`n")
</table></div><p class="sub">Erstellt mit PC Repair Pro $Script:ToolVersion · © 2026 Eder Tom</p></div></body></html>
"@
    $out = Join-Path $Ordner ('Geraeteuebersicht_{0:yyyyMMdd_HHmm}.html' -f (Get-Date))
    [IO.File]::WriteAllText($out, $html, (New-Object System.Text.UTF8Encoding $true))
    return $out
}
