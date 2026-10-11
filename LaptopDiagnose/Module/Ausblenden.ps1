<#
    Meldungen ausblenden: ausgeblendete Meldungen erscheinen bei späteren Prüfungen nicht mehr, zählen nicht in den
    Gesundheitswert und lassen sich unter »Einstellungen › Ausgeblendete Meldungen« wieder einblenden.
    Regeln liegen in Einstellungen.json (Schlüssel »Ausgeblendet«).
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:HiddenFindings = New-Object System.Collections.Generic.List[object]
$Script:HiddenRulesCache = $null
$Script:HiddenRulesStamp = $null
$Script:CurrentCheck = ''

function ConvertTo-StableTitle {
    <# Zahlen und Größenangaben neutralisieren, damit z. B. »Akku-Gesundheit: 76 %« auch bei 75 % wiedererkannt wird. #>
    param([string]$Title)
    $t = $Title -replace '\d+([.,]\d+)?\s*(B|KB|MB|GB|TB)\b', '#GROESSE'
    $t = $t -replace '\d+([.,]\d+)*', '#'
    return ($t -replace '\s+', ' ').Trim()
}

function Get-FindingHideKeys {
    param([string]$Category, [string]$Check, [string]$Title)
    [pscustomobject]@{
        Fund     = '{0}|{1}|{2}' -f $Category, $Check, (ConvertTo-StableTitle $Title)
        Pruefung = '{0}|{1}|*' -f $Category, $Check
    }
}

function Get-HiddenRules {
    <# Ausblend-Regeln aus den Einstellungen (zwischengespeichert, neu gelesen sobald sich die Datei ändert). #>
    $path = Join-Path $BerichtOrdner 'Einstellungen.json'
    if (-not (Test-Path -LiteralPath $path)) { $Script:HiddenRulesCache = @(); return @() }
    $stamp = (Get-Item -LiteralPath $path).LastWriteTimeUtc
    if ($null -ne $Script:HiddenRulesCache -and $stamp -eq $Script:HiddenRulesStamp) { return $Script:HiddenRulesCache }
    $rules = @()
    try {
        $j = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) | ConvertFrom-Json
        $rules = @($j.Ausgeblendet | Where-Object { $_ -and $_.Key })
    } catch { }
    $Script:HiddenRulesCache = $rules
    $Script:HiddenRulesStamp = $stamp
    return $rules
}

function Test-FindingHidden {
    param($Finding)
    if ($Finding.Repeatable -or $Finding.Category -eq 'Werkzeuge' -or $Finding.Severity -eq 'OK') { return $false }
    foreach ($r in Get-HiddenRules) {
        if ($r.Key -eq $Finding.HideKey -or $r.Key -eq $Finding.CheckKey) { return $true }
    }
    return $false
}

function Hide-FindingsNow {
    <# Nach dem Ausblenden im Fenster: passende Meldungen sofort aus der Ergebnisliste nehmen. #>
    param([string]$Key)
    $Script:HiddenRulesCache = $null
    for ($i = $Script:Findings.Count - 1; $i -ge 0; $i--) {
        $f = $Script:Findings[$i]
        if ($f.HideKey -eq $Key -or $f.CheckKey -eq $Key) { $Script:HiddenFindings.Add($f); $Script:Findings.RemoveAt($i) }
    }
}

function Show-HiddenNow {
    <# Nach dem Wiedereinblenden: zurückgehaltene Meldungen der laufenden Sitzung sofort wieder anzeigen. #>
    param([string]$Key)
    $Script:HiddenRulesCache = $null
    for ($i = $Script:HiddenFindings.Count - 1; $i -ge 0; $i--) {
        $f = $Script:HiddenFindings[$i]
        if (-not $Key -or $f.HideKey -eq $Key -or $f.CheckKey -eq $Key) {
            if (-not (Test-FindingHidden $f)) { $Script:Findings.Add($f); $Script:HiddenFindings.RemoveAt($i) }
        }
    }
}
