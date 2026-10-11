<#
    Herunterfahren & Neustart: misst die Dauer der letzten Herunterfahrvorgänge, ermittelt bremsende
    Programme, Dienste und Treiber und behebt typische Ursachen (zu lange Wartezeiten, Auslagerungsdatei
    löschen beim Herunterfahren, getrennte Netzlaufwerke, ausstehende Updates).
    Teil von LaptopDiagnose – Copyright 2026 by Eder Tom
#>

$Script:ShutdownDefaults = @{
    WaitToKillServiceTimeout = 5000
    WaitToKillAppTimeout     = 20000
    HungAppTimeout           = 5000
}

function Get-EventDataMap {
    <# Liefert die benannten Felder eines Ereignisses (EventData) als Hashtable. #>
    param($Record)
    $map = @{}
    try {
        $xml = [xml]$Record.ToXml()
        foreach ($d in @($xml.Event.EventData.Data)) {
            if ($d -and $d.Name) { $map[$d.Name] = "$($d.'#text')" }
        }
    } catch { }
    return $map
}

function Get-ShutdownMeasurements {
    <# Ermittelt die Dauer der Herunterfahrvorgänge der letzten 30 Tage aus dem Systemprotokoll. #>
    param([int]$Days = 30)
    $since = (Get-Date).AddDays(-$Days)
    $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 1074, 12, 13, 42, 109, 6005, 6006; StartTime = $since } -ErrorAction SilentlyContinue |
            Sort-Object TimeCreated)
    $result = New-Object System.Collections.Generic.List[object]
    $start = $null; $last = $null; $kind = ''; $initiator = ''
    foreach ($e in $events) {
        $isStart = $e.Id -eq 1074 -and $e.ProviderName -eq 'User32'
        $isBoot = ($e.Id -eq 12 -and $e.ProviderName -eq 'Microsoft-Windows-Kernel-General') -or ($e.Id -eq 6005 -and $e.ProviderName -eq 'EventLog')
        $isEnd = ($e.Id -eq 13 -and $e.ProviderName -eq 'Microsoft-Windows-Kernel-General') -or
                 ($e.Id -in 42, 109 -and $e.ProviderName -eq 'Microsoft-Windows-Kernel-Power') -or
                 ($e.Id -eq 6006 -and $e.ProviderName -eq 'EventLog')
        if ($isStart -or $isBoot) {
            if ($start -and $last) {
                $sec = ($last - $start).TotalSeconds
                if ($sec -gt 0 -and $sec -lt 1800) {
                    $result.Add([pscustomobject]@{ Zeit = $start; Sekunden = [math]::Round($sec); Art = $kind; Ausloeser = $initiator })
                }
            }
            $start = $null; $last = $null
            if ($isStart) {
                $start = $e.TimeCreated
                $kind = "$($e.Properties[4].Value)"
                $initiator = [IO.Path]::GetFileName(("$($e.Properties[0].Value)" -replace '\s*\(.*$', ''))
            }
        } elseif ($isEnd -and $start) {
            $last = $e.TimeCreated
        }
    }
    if ($start -and $last) {
        $sec = ($last - $start).TotalSeconds
        if ($sec -gt 0 -and $sec -lt 1800) { $result.Add([pscustomobject]@{ Zeit = $start; Sekunden = [math]::Round($sec); Art = $kind; Ausloeser = $initiator }) }
    }

    # Ergänzend: Messwerte der Windows-Leistungsdiagnose (Ereignis 200), sofern das Protokoll aktiv ist
    $perf = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 200; StartTime = $since } -ErrorAction SilentlyContinue |
            ForEach-Object {
                $m = Get-EventDataMap $_
                if ($m['ShutdownTime']) { [pscustomobject]@{ Zeit = $_.TimeCreated; Sekunden = [math]::Round([double]$m['ShutdownTime'] / 1000); Art = 'Leistungsdiagnose'; Ausloeser = '' } }
            })
    return [pscustomobject]@{ Protokoll = $result.ToArray(); Leistungsdiagnose = $perf }
}

function Get-ShutdownDelays {
    <# Programme, Dienste und Geräte, die Windows als Verzögerung beim Herunterfahren protokolliert hat (Ereignisse 201–207). #>
    param([int]$Days = 30)
    $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 201, 202, 203, 204, 205, 206, 207; StartTime = (Get-Date).AddDays(-$Days) } -ErrorAction SilentlyContinue)
    $kinds = @{ 201 = 'Programm'; 202 = 'Gerät/Treiber'; 203 = 'Dienst'; 204 = 'Speicher'; 205 = 'Auslagerungsdatei'; 206 = 'Sitzung'; 207 = 'Systemvorgang' }
    $rows = foreach ($e in $events) {
        $m = Get-EventDataMap $e
        $name = @($m['FriendlyName'], $m['Name'], $m['FileName'], $m['ServiceName']) | Where-Object { $_ } | Select-Object -First 1
        if (-not $name) { $name = "Ereignis $($e.Id)" }
        [pscustomobject]@{ Art = $kinds[[int]$e.Id]; Name = $name; Dauer = [double]$m['TotalTime'] / 1000; Zeit = $e.TimeCreated }
    }
    return @($rows | Group-Object Art, Name | ForEach-Object {
            [pscustomobject]@{
                Art    = $_.Group[0].Art
                Name   = $_.Group[0].Name
                Anzahl = $_.Count
                Dauer  = [math]::Round(($_.Group | Measure-Object Dauer -Average).Average, 1)
            }
        } | Sort-Object @{ Expression = { $_.Anzahl * $_.Dauer } } -Descending)
}

function Get-HangingServices {
    <# Dienste, die beim Herunterfahren nicht rechtzeitig reagiert haben (Dienststeuerungs-Manager 7011/7043). #>
    param([int]$Days = 30)
    $events = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; Id = 7011, 7043; StartTime = (Get-Date).AddDays(-$Days) } -ErrorAction SilentlyContinue)
    $names = foreach ($e in $events) {
        $n = if ($e.Id -eq 7011) { "$($e.Properties[1].Value)" } else { "$($e.Properties[0].Value)" }
        if ($n) { $n }
    }
    return @($names | Group-Object | Sort-Object Count -Descending | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Anzahl = $_.Count } })
}

function Set-ShutdownTimeouts {
    <# Setzt zu hohe Wartezeiten beim Herunterfahren auf die Windows-Standardwerte zurück (umkehrbar). #>
    param($Data)
    $done = @()
    foreach ($v in @($Data)) {
        Set-RegistryValueTracked -Path $v.Path -Name $v.Name -Value ([string]$v.Default) -Type String -Beschreibung "$($v.Name) von $($v.Current) auf $($v.Default) ms gesetzt (Herunterfahren)"
        $done += $v.Name
    }
    "Wartezeiten auf Windows-Standard gesetzt: $($done -join ', '). Wirksam ab dem nächsten Herunterfahren."
}

function Remove-StaleNetworkDrives {
    param($Drives)
    $ok = @()
    foreach ($d in @($Drives)) {
        try {
            Remove-SmbMapping -LocalPath $d.LocalPath -Force -UpdateProfile -ErrorAction Stop
            Register-Change -Beschreibung "Getrenntes Netzlaufwerk $($d.LocalPath) ($($d.RemotePath)) entfernt" -Typ 'Netzlaufwerk' -Daten @{ LocalPath = $d.LocalPath; RemotePath = $d.RemotePath }
            $ok += $d.LocalPath
        } catch { }
    }
    "Entfernt: $($ok -join ', '). Rückgängig über »Änderungen«."
}

function Invoke-ShutdownScan {
    $cat = 'Herunterfahren'
    Clear-CategoryFindings $cat
    Write-Title 'Herunterfahren & Neustart'

    Invoke-Check $cat 'Dauer der letzten Herunterfahrvorgänge (30 Tage)' {
        $m = Get-ShutdownMeasurements
        $source = if (@($m.Leistungsdiagnose).Count -ge 2) { @($m.Leistungsdiagnose) } else { @($m.Protokoll) }
        if (-not $source) {
            Add-Finding $cat Info 'Keine auswertbaren Herunterfahrvorgänge in den letzten 30 Tagen gefunden' `
                -Detail 'Nach dem nächsten Herunterfahren bzw. Neustart erneut prüfen.'
            return
        }
        $recent = @($source | Sort-Object Zeit -Descending | Select-Object -First 10)
        $avg = [math]::Round(($recent | Measure-Object Sekunden -Average).Average)
        $max = ($recent | Measure-Object Sekunden -Maximum).Maximum
        Set-Metric 'Herunterfahren' $avg
        $chart = @($recent | Sort-Object Zeit | ForEach-Object { [pscustomobject]@{ Label = $_.Zeit.ToString('dd.MM. HH:mm') + $(if ($_.Art -and $_.Art -ne 'Leistungsdiagnose') { " ($($_.Art))" }); Value = $_.Sekunden; Text = "$($_.Sekunden) s" } })
        $detail = "Durchschnitt der letzten $($recent.Count) Vorgänge: $avg s (längster: $max s). Üblich sind 5–20 Sekunden."
        if ($avg -ge 120) {
            Add-Finding $cat Kritisch "Herunterfahren dauert sehr lange (Ø $avg Sekunden)" -Detail $detail -Chart $chart
        } elseif ($avg -ge 40) {
            Add-Finding $cat Warnung "Herunterfahren dauert zu lange (Ø $avg Sekunden)" -Detail $detail -Chart $chart
        } else {
            Add-Finding $cat OK "Herunterfahren in Ø $avg Sekunden" -Detail $detail -Chart $chart
        }
    }

    Invoke-Check $cat 'Programme, Dienste und Treiber, die das Herunterfahren bremsen' {
        $delays = @(Get-ShutdownDelays)
        if ($delays) {
            $sev = if (($delays | Measure-Object Anzahl -Sum).Sum -ge 3) { 'Warnung' } else { 'Info' }
            Add-Finding $cat $sev "$($delays.Count) Verursacher für verzögertes Herunterfahren erkannt" `
                -Detail 'Laut Windows-Leistungsdiagnose. Betroffene Programme aktualisieren (Bereich »Software-Updates«), nicht benötigte aus dem Autostart nehmen oder deinstallieren; bei Geräten den Treiber aktualisieren.' `
                -Items ($delays | Select-Object -First 12 | ForEach-Object { '{0}: {1} – {2}× verzögert, Ø {3} s' -f $_.Art, $_.Name, $_.Anzahl, $_.Dauer }) `
                -Chart @($delays | Select-Object -First 8 | ForEach-Object { [pscustomobject]@{ Label = $_.Name; Value = $_.Anzahl * $_.Dauer; Text = "$($_.Anzahl)× · Ø $($_.Dauer) s" } })
        } else {
            Add-Finding $cat OK 'Windows hat keine Programme oder Dienste protokolliert, die das Herunterfahren verzögern'
        }
    }

    Invoke-Check $cat 'Dienste, die beim Herunterfahren hängen' {
        $hang = @(Get-HangingServices)
        if ($hang) {
            Add-Finding $cat Warnung "$($hang.Count) Dienst(e) reagierten beim Herunterfahren nicht rechtzeitig" `
                -Detail 'Windows wartet auf diese Dienste, bevor es ausschaltet. Zugehörige Software aktualisieren oder – falls nicht benötigt – deinstallieren.' `
                -Items ($hang | ForEach-Object { '{0} – {1}×' -f $_.Name, $_.Anzahl })
        }
    }

    Invoke-Check $cat 'Wartezeiten beim Herunterfahren' {
        $checks = @(
            @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control'; Name = 'WaitToKillServiceTimeout' }
            @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'WaitToKillAppTimeout' }
            @{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'HungAppTimeout' }
        )
        $tooHigh = foreach ($c in $checks) {
            $val = (Get-ItemProperty -Path $c.Path -Name $c.Name -ErrorAction SilentlyContinue).($c.Name)
            $default = $Script:ShutdownDefaults[$c.Name]
            if ($val -and [int]$val -gt $default) { [pscustomobject]@{ Path = $c.Path; Name = $c.Name; Current = [int]$val; Default = $default } }
        }
        $tooHigh = @($tooHigh)
        if ($tooHigh) {
            Add-Finding $cat Warnung 'Windows wartet beim Herunterfahren länger als üblich auf Programme und Dienste' `
                -Items ($tooHigh | ForEach-Object { '{0}: {1} ms (Standard: {2} ms)' -f $_.Name, $_.Current, $_.Default }) `
                -Detail 'Erhöhte Wartezeiten stammen oft von Software-Installationen oder »Tuning«-Tools.' `
                -FixLabel 'Wartezeiten auf Windows-Standard zurücksetzen' -FixData $tooHigh -Fix { param($d) Set-ShutdownTimeouts $d }
        } else {
            Add-Finding $cat OK 'Wartezeiten beim Herunterfahren entsprechen dem Windows-Standard'
        }
    }

    Invoke-Check $cat 'Auslagerungsdatei beim Herunterfahren löschen' {
        $mm = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
        $v = (Get-ItemProperty -Path $mm -Name ClearPageFileAtShutdown -ErrorAction SilentlyContinue).ClearPageFileAtShutdown
        if ($v -eq 1) {
            Add-Finding $cat Warnung 'Die Auslagerungsdatei wird bei jedem Herunterfahren überschrieben' `
                -Detail 'Das verlängert das Herunterfahren um bis zu mehrere Minuten. Nur abschalten, wenn keine Firmenrichtlinie diese Einstellung verlangt.' `
                -FixLabel 'Löschen der Auslagerungsdatei beim Herunterfahren abschalten' -RequiresReboot `
                -Fix { param($d) Set-RegistryValueTracked -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name ClearPageFileAtShutdown -Value 0 -Beschreibung 'Löschen der Auslagerungsdatei beim Herunterfahren abgeschaltet'; 'Abgeschaltet (wirksam nach dem nächsten Neustart).' }
        } else {
            Add-Finding $cat OK 'Die Auslagerungsdatei wird beim Herunterfahren nicht gelöscht'
        }
    }

    Invoke-Check $cat 'Ausstehende Updates' {
        if (Test-PendingReboot) {
            Add-Finding $cat Warnung 'Updates warten auf einen Neustart' `
                -Detail 'Ausstehende Updates werden beim Herunterfahren installiert und verlängern es deutlich. Einmal neu starten, damit sie abgeschlossen werden.' `
                -FixLabel 'Updates mit einem Neustart abschließen' -RequiresReboot `
                -Fix { param($d) $Script:RebootNeeded = $true; 'Neustart vorgemerkt – bitte im nächsten Schritt bestätigen.' }
        }
    }

    Invoke-Check $cat 'Getrennte Netzlaufwerke' {
        $maps = @(Get-SmbMapping -ErrorAction Stop | Where-Object { $_.Status -ne 'OK' })
        if ($maps) {
            Add-Finding $cat Info "$($maps.Count) Netzlaufwerk(e) sind nicht erreichbar" `
                -Detail 'Nicht erreichbare Netzlaufwerke verzögern Abmelden und Herunterfahren. Nicht mehr benötigte Verbindungen entfernen.' `
                -Items ($maps | ForEach-Object { '{0}  →  {1} ({2})' -f $_.LocalPath, $_.RemotePath, $_.Status }) `
                -FixLabel 'Nicht erreichbare Netzlaufwerke entfernen' `
                -FixData @($maps | ForEach-Object { [pscustomobject]@{ LocalPath = $_.LocalPath; RemotePath = $_.RemotePath } }) `
                -SelectLabels @($maps | ForEach-Object { '{0}  →  {1}' -f $_.LocalPath, $_.RemotePath }) `
                -Fix { param($d, $pre) Remove-StaleNetworkDrives $d }
        }
    }

    Invoke-Check $cat 'Skripte beim Herunterfahren' {
        $scripts = @(Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Group Policy\Scripts\Shutdown' -Recurse -ErrorAction SilentlyContinue |
                ForEach-Object { (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).Script } | Where-Object { $_ })
        if ($scripts) {
            Add-Finding $cat Info "$($scripts.Count) Skript(e) laufen beim Herunterfahren (Gruppenrichtlinie)" -Items $scripts `
                -Detail 'Bei Firmengeräten üblich. Bei privaten Geräten prüfen, woher die Skripte stammen.'
        }
    }

    Invoke-Check $cat 'Schnellstart' {
        $hb = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction SilentlyContinue).HiberbootEnabled
        $text = if ($hb -eq 1) {
            'Schnellstart ist aktiv: Beim Herunterfahren wird der Systemzustand gespeichert. Ein »Neustart« ist dagegen ein vollständiger Neustart – Updates und Treiberprobleme lassen sich damit besser beheben.'
        } else {
            'Schnellstart ist aus: Windows fährt jedes Mal vollständig herunter. Das ist zuverlässig, der nächste Start dauert aber etwas länger.'
        }
        Add-Finding $cat Info $(if ($hb -eq 1) { 'Schnellstart ist eingeschaltet' } else { 'Schnellstart ist ausgeschaltet' }) -Detail $text
    }

    Invoke-Check $cat 'Leistungsprotokoll für das Herunterfahren' {
        $log = Get-WinEvent -ListLog 'Microsoft-Windows-Diagnostics-Performance/Operational' -ErrorAction Stop
        if ($log -and $log.IsEnabled -eq $false) {
            Add-Finding $cat Warnung 'Das Windows-Leistungsprotokoll ist ausgeschaltet – Verursacher können nicht erkannt werden' `
                -FixLabel 'Leistungsprotokoll einschalten' `
                -Fix {
                param($d)
                $null = & wevtutil.exe sl 'Microsoft-Windows-Diagnostics-Performance/Operational' /e:true
                Register-Change -Beschreibung 'Windows-Leistungsprotokoll (Diagnostics-Performance) eingeschaltet' -Typ 'Protokoll' -NichtUmkehrbar
                'Protokoll eingeschaltet – nach den nächsten Herunterfahrvorgängen erneut prüfen.'
            }
        }
    }

    Invoke-Check $cat 'Ungewolltes Aufwachen aus dem Energiesparmodus' { Add-WakeFindings -Category $cat }

    Invoke-Check $cat 'Programme ohne Rückfrage beenden (optional)' {
        $auto = (Get-ItemProperty -Path 'HKCU:\Control Panel\Desktop' -Name AutoEndTasks -ErrorAction SilentlyContinue).AutoEndTasks
        if ("$auto" -ne '1') {
            Add-Finding $cat Info 'Optional: Hängende Programme beim Herunterfahren automatisch beenden' `
                -Detail 'Windows wartet dann nicht mehr auf die Rückfrage »Diese App verhindert das Herunterfahren«. Achtung: Ungespeicherte Daten in diesen Programmen gehen verloren.' `
                -FixLabel 'Programme beim Herunterfahren automatisch beenden' `
                -Fix { param($d) Set-RegistryValueTracked -Path 'HKCU:\Control Panel\Desktop' -Name AutoEndTasks -Value '1' -Type String -Beschreibung 'Programme beim Herunterfahren automatisch beenden (AutoEndTasks)'; 'Eingeschaltet – rückgängig über »Änderungen«.' }
        }
    }
}
