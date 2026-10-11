<#
    Drucker-Diagnose: Druckwarteschlangen-Dienst, Drucker offline bzw. mit Fehler, hängende Druckaufträge,
    automatisch wechselnder Standarddrucker, generische Treiber und Fehler im Druck-Ereignisprotokoll.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:VirtualPrinters = 'Microsoft Print to PDF|Microsoft XPS Document Writer|OneNote|Fax|An OneNote senden|Send To OneNote|Adobe PDF|PDF24|PDFCreator'

function Add-PrinterFindings {
    param([string]$Category)
    $spooler = Get-Service -Name Spooler -ErrorAction SilentlyContinue
    if ($spooler -and $spooler.Status -ne 'Running') {
        Add-Finding $Category Warnung 'Die Druckwarteschlange (Spooler) läuft nicht' `
            -Detail 'Ohne diesen Dienst kann nicht gedruckt werden, und Drucker werden oft gar nicht angezeigt.' `
            -FixLabel 'Druckwarteschlange starten' -Fix {
            param($d)
            Set-Service -Name Spooler -StartupType Automatic -ErrorAction SilentlyContinue
            Start-Service -Name Spooler -ErrorAction Stop
            'Druckwarteschlange gestartet.'
        }
        return
    }
    $printers = @(Get-Printer -ErrorAction SilentlyContinue)
    $real = @($printers | Where-Object { $_.Name -notmatch $Script:VirtualPrinters -and "$($_.PortName)" -notmatch '^(PORTPROMPT:|nul:|FILE:)' })
    if (-not $real) { Add-Finding $Category OK 'Kein (physischer) Drucker eingerichtet'; return }

    # Offline bzw. mit Fehler
    $wmi = @{}
    foreach ($w in @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue)) { $wmi[$w.Name] = $w }
    $bad = @($real | Where-Object { "$($_.PrinterStatus)" -match 'Offline|Error|PaperJam|PaperOut|TonerLow|NoToner|DoorOpen|NotAvailable|UserIntervention' -or $wmi[$_.Name].WorkOffline })
    foreach ($p in $bad) {
        $offline = [bool]$wmi[$p.Name].WorkOffline
        $status = if ($offline) { 'auf »Offline verwenden« gestellt' } else { "$($p.PrinterStatus)" }
        Add-Finding $Category Warnung "Drucker »$($p.Name)«: $status" `
            -Detail 'Häufige Ursachen: Drucker ausgeschaltet oder im Energiesparmodus, WLAN-Drucker hat eine neue Adresse bekommen, Papier/Toner leer. Drucker einschalten und prüfen; »Offline verwenden« wird zurückgesetzt und die Druckwarteschlange neu gestartet.' `
            -FixLabel "Drucker »$($p.Name)« wieder online schalten" -FixData $p.Name -Fix {
            param($name)
            $w = Get-CimInstance Win32_Printer -Filter "Name='$($name -replace "'", "''")'" -ErrorAction Stop
            if ($w.WorkOffline) { Set-CimInstance -InputObject $w -Property @{ WorkOffline = $false } -ErrorAction Stop }
            Restart-Service -Name Spooler -Force -ErrorAction Stop
            "Drucker »$name« online geschaltet, Druckwarteschlange neu gestartet."
        }
    }

    # Hängende Druckaufträge (älter als 30 Minuten oder mit Fehler)
    $stuck = @(foreach ($p in $real) {
            foreach ($j in @(Get-PrintJob -PrinterName $p.Name -ErrorAction SilentlyContinue)) {
                if ("$($j.JobStatus)" -match 'Error|Blocked|Deleting' -or ($j.SubmittedTime -and $j.SubmittedTime -lt (Get-Date).AddMinutes(-30))) {
                    [pscustomobject]@{ Printer = $p.Name; Id = $j.Id; Doc = $j.DocumentName; Time = $j.SubmittedTime; Status = "$($j.JobStatus)" }
                }
            }
        })
    if ($stuck) {
        Add-Finding $Category Warnung "$($stuck.Count) hängende(r) Druckauftrag/Druckaufträge" -Items @($stuck | ForEach-Object { '{0}: {1} ({2:dd.MM. HH:mm}) {3}' -f $_.Printer, $_.Doc, $_.Time, $_.Status }) `
            -Detail 'Ein hängender Auftrag blockiert alle folgenden. Die Aufträge werden gelöscht und die Druckwarteschlange neu gestartet; danach erneut drucken.' `
            -FixLabel 'Hängende Druckaufträge löschen' -FixData $stuck -Fix {
            param($d)
            foreach ($j in @($d)) { Remove-PrintJob -PrinterName $j.Printer -ID $j.Id -ErrorAction SilentlyContinue }
            Stop-Service -Name Spooler -Force -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath (Join-Path $env:windir 'System32\spool\PRINTERS') -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Start-Service -Name Spooler -ErrorAction Stop
            "$(@($d).Count) Auftrag/Aufträge gelöscht, Druckwarteschlange neu gestartet."
        }
    }

    # Standarddrucker wechselt automatisch (Windows verwaltet den Standarddrucker)
    $legacy = $null
    try { $legacy = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows' -Name LegacyDefaultPrinterMode -ErrorAction Stop).LegacyDefaultPrinterMode } catch { }
    $default = @($wmi.Values | Where-Object { $_.Default }) | Select-Object -First 1
    if ("$legacy" -ne '1' -and $real.Count -ge 2) {
        Add-Finding $Category Info "Windows wechselt den Standarddrucker automatisch (zurzeit: $(if ($default) { $default.Name } else { 'keiner' }))" `
            -Detail 'Mit »Windows verwaltet Standarddrucker« wird jeweils der zuletzt benutzte Drucker am aktuellen Ort zum Standard – deshalb druckt es manchmal plötzlich auf dem falschen Drucker. Ausschalten (umkehrbar), dann den gewünschten Standarddrucker einmal festlegen.' `
            -FixLabel 'Automatischen Standarddrucker-Wechsel ausschalten' -Fix {
            param($d)
            Set-RegistryValuesTracked -Values @(@{ Path = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Windows'; Name = 'LegacyDefaultPrinterMode'; Value = 1 }) -Beschreibung 'Automatischen Standarddrucker-Wechsel ausgeschaltet'
            Start-Process 'ms-settings:printers'
            'Automatischer Wechsel ausgeschaltet – in den geöffneten Einstellungen den gewünschten Drucker als Standard festlegen. Rückgängig über »Änderungen«.'
        }
    }

    # Generische Treiber (funktionieren, aber oft ohne Duplex, Fächer, Tintenstand)
    $generic = @($real | Where-Object { $_.DriverName -match 'Microsoft IPP Class Driver|Microsoft PCL6 Class Driver|Microsoft PS Class Driver|Generic|Universal Print Class Driver|Microsoft enhanced Point and Print' })
    if ($generic) {
        Add-Finding $Category Info "$($generic.Count) Drucker mit allgemeinem Windows-Treiber" -Items @($generic | ForEach-Object { "$($_.Name): $($_.DriverName)" }) `
            -Detail 'Der allgemeine Treiber druckt, bietet aber oft keine Einstellungen für Duplex, Papierfächer, Druckqualität oder Tintenstand. Bei Bedarf den Treiber des Herstellers installieren (Support-Seite von HP, Canon, Epson, Brother …).'
    }

    # Fehler im Druck-Ereignisprotokoll (7 Tage)
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-PrintService/Admin'; Level = 2; StartTime = (Get-Date).AddDays(-7) } -MaxEvents 50 -ErrorAction SilentlyContinue)
    if ($ev.Count -ge 3) {
        Add-Finding $Category Info "$($ev.Count) Druckfehler in den letzten 7 Tagen" -Items @($ev | Select-Object -First 8 | ForEach-Object { '{0:dd.MM. HH:mm}  {1}' -f $_.TimeCreated, ("$($_.Message)" -split "`r?`n")[0] })
    }

    if (-not $bad -and -not $stuck) {
        Add-Finding $Category OK "Drucker in Ordnung ($($real.Count) eingerichtet$(if ($default) { ", Standard: $($default.Name)" }))" -Items @($real | ForEach-Object { "$($_.Name) – $($_.PrinterStatus)" })
    }
}
