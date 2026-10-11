<#
    Reparatur-Werkzeuge, Belastungstest, Speichertest und vorinstallierte Zusatzsoftware.
    Teil von LaptopDiagnose – Copyright 2026 by Eder Tom
#>

#region ---------- Reparaturen ----------

function Repair-WindowsUpdateComponents {
    $svcs = 'wuauserv', 'bits', 'cryptsvc', 'msiserver', 'UsoSvc'
    Stop-Service -Name $svcs -Force -ErrorAction SilentlyContinue
    $renamed = @()
    foreach ($p in (Join-Path $env:windir 'SoftwareDistribution'), (Join-Path $env:windir 'System32\catroot2')) {
        $bak = "$p.bak"
        if (Test-Path -LiteralPath $bak) { Remove-Item -LiteralPath $bak -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path -LiteralPath $p) {
            try { Rename-Item -LiteralPath $p -NewName ([IO.Path]::GetFileName($bak)) -ErrorAction Stop; $renamed += [IO.Path]::GetFileName($p) } catch { }
        }
    }
    foreach ($s in 'cryptsvc', 'bits', 'wuauserv', 'UsoSvc') { Start-Service -Name $s -ErrorAction SilentlyContinue }
    Register-Change -Beschreibung 'Windows-Update-Komponenten zurückgesetzt' -Typ 'Protokoll' -NichtUmkehrbar
    "Update-Dienste neu gestartet$(if ($renamed) { ', zurückgesetzt: ' + ($renamed -join ', ') }). Anschließend erneut nach Updates suchen."
}

function Repair-StoreApps {
    $pkg = Get-AppxPackage -Name 'Microsoft.WindowsStore' -ErrorAction Stop
    if (Get-Command Reset-AppxPackage -ErrorAction SilentlyContinue) { $pkg | Reset-AppxPackage -ErrorAction Stop }
    else { Start-Process -FilePath 'wsreset.exe' -Wait }
    Add-AppxPackage -DisableDevelopmentMode -Register (Join-Path $pkg.InstallLocation 'AppxManifest.xml') -ErrorAction SilentlyContinue
    Register-Change -Beschreibung 'Microsoft Store zurückgesetzt' -Typ 'Protokoll' -NichtUmkehrbar
    'Microsoft Store zurückgesetzt und neu registriert.'
}

function Repair-StartMenuSearch {
    foreach ($name in 'Microsoft.Windows.StartMenuExperienceHost', 'Microsoft.Windows.ShellExperienceHost', 'MicrosoftWindows.Client.CBS', 'Microsoft.Windows.Search') {
        foreach ($p in @(Get-AppxPackage -Name $name -ErrorAction SilentlyContinue)) {
            Add-AppxPackage -DisableDevelopmentMode -Register (Join-Path $p.InstallLocation 'AppxManifest.xml') -ErrorAction SilentlyContinue
        }
    }
    Restart-Service -Name WSearch -Force -ErrorAction SilentlyContinue
    Get-Process -Name StartMenuExperienceHost, SearchHost, SearchApp, ShellExperienceHost -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Register-Change -Beschreibung 'Startmenü und Windows-Suche repariert' -Typ 'Protokoll' -NichtUmkehrbar
    'Startmenü und Suche neu registriert und neu gestartet.'
}

function Clear-PrintQueue {
    Stop-Service -Name Spooler -Force -ErrorAction Stop
    $n = @(Get-ChildItem -LiteralPath (Join-Path $env:windir 'System32\spool\PRINTERS') -File -Force -ErrorAction SilentlyContinue).Count
    Get-ChildItem -LiteralPath (Join-Path $env:windir 'System32\spool\PRINTERS') -File -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Start-Service -Name Spooler -ErrorAction Stop
    Register-Change -Beschreibung 'Druckerwarteschlange geleert' -Typ 'Protokoll' -NichtUmkehrbar
    "Druckerwarteschlange geleert ($n Datei(en) entfernt), Druckdienst neu gestartet."
}

function Restart-AudioServices {
    Restart-Service -Name AudioEndpointBuilder -Force -ErrorAction Stop
    Start-Service -Name Audiosrv -ErrorAction SilentlyContinue
    'Audiodienste neu gestartet.'
}

function Restart-BluetoothService {
    Restart-Service -Name bthserv -Force -ErrorAction Stop
    'Bluetooth-Dienst neu gestartet.'
}

function Request-MemoryTest {
    $out = & bcdedit.exe /bootsequence '{memdiag}' 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "Speichertest konnte nicht geplant werden: $($out.Trim())" }
    $Script:RebootNeeded = $true
    Register-Change -Beschreibung 'Arbeitsspeicher-Test für den nächsten Neustart geplant' -Typ 'Protokoll' -NichtUmkehrbar
    'Der Arbeitsspeicher-Test läuft beim nächsten Neustart (ca. 10–20 Minuten). Das Ergebnis erscheint danach in der Fehlersuche.'
}

function New-PowerReport {
    param([ValidateSet('SleepStudy', 'Energy')][string]$Art)
    if (-not (Test-Path -LiteralPath $BerichtOrdner)) { $null = New-Item -ItemType Directory -Path $BerichtOrdner -Force }
    if ($Art -eq 'SleepStudy') {
        $out = Join-Path $BerichtOrdner ('Standby-Analyse_{0:yyyyMMdd_HHmm}.html' -f (Get-Date))
        $null = & powercfg.exe /sleepstudy /output $out 2>&1
    } else {
        Write-Host "     Energiebericht: 60 Sekunden Messung, bitte den $(Get-DeviceWord) nicht benutzen …" -ForegroundColor Gray
        $out = Join-Path $BerichtOrdner ('Energiebericht_{0:yyyyMMdd_HHmm}.html' -f (Get-Date))
        $null = & powercfg.exe /energy /output $out /duration 60 2>&1
    }
    if (-not (Test-Path -LiteralPath $out)) { throw 'Bericht konnte nicht erstellt werden (wird von diesem Gerät evtl. nicht unterstützt).' }
    if (-not $Unbeaufsichtigt) { Invoke-Item -LiteralPath $out }
    "Bericht gespeichert: $out"
}

#endregion

#region ---------- Belastungstest ----------

function Invoke-StressTest {
    <# Lastet alle Prozessorkerne für kurze Zeit aus und prüft, ob der Prozessor thermisch drosselt. #>
    param([int]$Seconds = 30)
    $readPerf = {
        $p = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" -ErrorAction SilentlyContinue
        $t = $null
        try {
            $z = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop |
                    ForEach-Object { [math]::Round($_.CurrentTemperature / 10 - 273.15) } | Where-Object { $_ -gt 0 -and $_ -lt 130 })
            if ($z) { $t = ($z | Measure-Object -Maximum).Maximum }
        } catch { }
        [pscustomobject]@{ Perf = [double]$p.PercentProcessorPerformance; Load = [double]$p.PercentProcessorTime; Temp = $t }
    }
    $onAc = $true
    $bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($bat -and $bat.BatteryStatus -eq 1) { $onAc = $false }
    $idle = & $readPerf

    $cores = [Environment]::ProcessorCount
    $workers = @()
    $code = "`$end = [DateTime]::UtcNow.AddSeconds($Seconds); `$x = 0.0; while ([DateTime]::UtcNow -lt `$end) { for (`$i = 0; `$i -lt 200000; `$i++) { `$x += [Math]::Sqrt(`$i) } }"
    Write-Host "     Belastungstest läuft $Seconds Sekunden auf $cores Threads …" -ForegroundColor Gray
    $samples = @()
    try {
        for ($i = 0; $i -lt $cores; $i++) {
            $ps = [powershell]::Create()
            $null = $ps.AddScript($code)
            $workers += @{ PS = $ps; Handle = $ps.BeginInvoke() }
        }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
            Start-Sleep -Seconds 2
            $samples += & $readPerf
        }
    } finally {
        foreach ($w in $workers) { try { $w.PS.Stop() } catch { }; $w.PS.Dispose() }
    }
    $late = @($samples | Select-Object -Last ([math]::Max(1, [math]::Floor($samples.Count / 2))))
    $perf = [math]::Round(($late | Measure-Object Perf -Average).Average)
    $load = [math]::Round(($late | Measure-Object Load -Average).Average)
    $temps = @($samples | Where-Object { $null -ne $_.Temp } | ForEach-Object { $_.Temp })
    # Viele Desktop-Mainboards melden über ACPI nur einen festen Platzhalterwert (z. B. 28 °C) – dann nicht auswerten
    if ($temps -and $null -ne $idle.Temp -and -not ($temps | Where-Object { $_ -ne $idle.Temp })) { $temps = @() }
    $maxTemp = if ($temps) { ($temps | Measure-Object -Maximum).Maximum }
    $rise = if ($maxTemp -and $null -ne $idle.Temp) { $maxTemp - $idle.Temp } else { 0 }
    $isLaptop = (Get-DeviceKind) -eq 'Laptop'
    $dust = if ($isLaptop) { 'Lüfter und Lüftungsschlitze reinigen (lassen), Laptop auf harter Unterlage betreiben.' } else { 'Gehäuse, CPU-Kühler und Lüfter entstauben, Lüfter auf Funktion prüfen; bei älteren PCs ggf. Wärmeleitpaste erneuern.' }

    $parts = @("Auslastung $load %, Leistung unter Last $perf % der Nennleistung")
    if ($null -ne $idle.Temp -and $maxTemp) { $parts += "Temperatur $($idle.Temp) → $maxTemp °C" }
    elseif (-not $temps) { $parts += 'Temperatur: kein auswertbarer Sensor (z. B. mit HWiNFO oder dem Hersteller-Tool prüfen)' }
    $verdict = if ($maxTemp -ge 95) { "Kritisch heiß – $dust" }
    elseif (-not $onAc) { 'Akkubetrieb: Drosselung ist hier normal. Für einen aussagekräftigen Test das Netzteil anschließen.' }
    elseif ($perf -lt 60) { "Starke Drosselung – Kühlung prüfen: $dust Energiesparplan kontrollieren." }
    elseif ($rise -ge 45 -or ($maxTemp -ge 88 -and -not $isLaptop)) { "Temperatur steigt unter Last stark an (+$rise °C) – Hinweis auf Staub oder schwache Kühlung: $dust" }
    elseif ($perf -lt 90) { if ($isLaptop) { 'Leichte Drosselung unter Dauerlast – für Laptops häufig normal.' } else { "Leichte Drosselung unter Dauerlast – bei Desktop-PCs ungewöhnlich: $dust" } }
    else { 'Volle Leistung unter Last – Kühlung arbeitet einwandfrei.' }
    Register-Change -Beschreibung 'Belastungstest durchgeführt' -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis "$($parts -join ', '). $verdict"
    "$($parts -join ', '). $verdict"
}

#endregion

#region ---------- Vorinstallierte Zusatzsoftware ----------

$Script:BloatAppx = [ordered]@{
    'king.com.*'                              = 'Candy Crush & weitere King-Spiele'
    '*CandyCrush*'                            = 'Candy Crush'
    '*Disney*'                                = 'Disney+'
    '*TikTok*'                                = 'TikTok'
    'Facebook.*'                              = 'Facebook'
    '*Instagram*'                             = 'Instagram'
    '*PrimeVideo*'                            = 'Amazon Prime Video'
    'SpotifyAB.SpotifyMusic'                  = 'Spotify (vorinstalliert)'
    '*HiddenCity*'                            = 'Hidden City (Spiel)'
    '*MarchofEmpires*'                        = 'March of Empires (Spiel)'
    '*FarmVille*'                             = 'FarmVille (Spiel)'
    '*McAfee*'                                = 'McAfee (Testversion)'
    '*Norton*'                                = 'Norton (Testversion)'
    '*ExpressVPN*'                            = 'ExpressVPN (Testversion)'
    '*Booking*'                               = 'Booking.com'
    'Microsoft.MicrosoftSolitaireCollection'  = 'Microsoft Solitaire Collection (mit Werbung)'
    'Microsoft.MicrosoftOfficeHub'            = 'Office-Werbe-App (»Microsoft 365«)'
    'Microsoft.BingNews'                      = 'Microsoft News'
    'Microsoft.MixedReality.Portal'           = 'Mixed Reality-Portal'
    'Microsoft.Microsoft3DViewer'             = '3D-Viewer'
    'Microsoft.SkypeApp'                      = 'Skype (eingestellt)'
    'Clipchamp.Clipchamp'                     = 'Clipchamp'
    'Microsoft.549981C3F5F10'                 = 'Cortana'
}
$Script:BloatWin32 = 'McAfee|Norton|WildTangent|ExpressVPN|Booking\.com|Dashlane|Keeper Password|CyberLink.*Trial'

function Get-BloatwareApps {
    $found = @{}
    $installed = @(Get-AppxPackage -ErrorAction SilentlyContinue)
    foreach ($pattern in $Script:BloatAppx.Keys) {
        foreach ($p in $installed | Where-Object { $_.Name -like $pattern -and -not $_.IsFramework -and $_.SignatureKind -ne 'System' }) {
            if (-not $found.ContainsKey($p.Name)) { $found[$p.Name] = [pscustomobject]@{ Name = $p.Name; Label = $Script:BloatAppx[$pattern]; FullName = $p.PackageFullName } }
        }
    }
    return @($found.Values | Sort-Object Label)
}

function Get-BloatwarePrograms {
    $activeAv = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue | ForEach-Object { $_.displayName })
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $apps = foreach ($k in $keys) { Get-ItemProperty -Path $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -and -not $_.SystemComponent } }
    return @($apps | Where-Object { $_.DisplayName -match $Script:BloatWin32 } |
            Where-Object { $n = $_.DisplayName; -not ($activeAv | Where-Object { $n -match [regex]::Escape(($_ -split ' ')[0]) }) } |
            Select-Object -ExpandProperty DisplayName -Unique)
}

function Remove-BloatwareApps {
    param($Apps)
    $ok = @(); $failed = @()
    foreach ($a in $Apps) {
        try {
            Get-AppxPackage -Name $a.Name -ErrorAction Stop | Remove-AppxPackage -ErrorAction Stop
            $ok += $a.Label
        } catch { $failed += $a.Label }
    }
    if ($ok) {
        Register-Change -Beschreibung "Vorinstallierte Apps entfernt: $($ok -join ', ')" -Typ 'Protokoll' -NichtUmkehrbar -Hinweis 'Bei Bedarf über den Microsoft Store neu installieren.'
    }
    $msg = "$($ok.Count) App(s) entfernt."
    if ($failed) { $msg += ' Nicht entfernbar: ' + ($failed -join ', ') }
    $msg
}

function Add-BloatwareFindings {
    param([string]$Category)
    $apps = @(Get-BloatwareApps)
    if ($apps) {
        Add-Finding $Category Info "$($apps.Count) vorinstallierte Zusatz-App(s) gefunden" `
            -Detail 'Werbe-Apps, Spiele und Testversionen belegen Speicher und laufen teils im Hintergrund. Im nächsten Schritt einzeln auswählen.' `
            -Items ($apps | ForEach-Object { $_.Label }) `
            -FixLabel 'Ausgewählte Zusatz-Apps entfernen' -FixData $apps -SelectLabels @($apps | ForEach-Object { $_.Label }) `
            -Fix { param($d, $pre) Remove-BloatwareApps $d }
    }
    $progs = @(Get-BloatwarePrograms)
    if ($progs) {
        Add-Finding $Category Info "$($progs.Count) vorinstallierte Testversion(en)/Zusatzprogramm(e)" -Items $progs `
            -Detail 'Diese Programme werden über die Windows-Einstellungen deinstalliert.' `
            -FixLabel 'Installierte Apps in den Einstellungen öffnen' -Fix { param($d) Start-Process 'ms-settings:appsfeatures'; 'Einstellungen geöffnet.' }
    }
}

#endregion

#region ---------- Werkzeug-Übersicht ----------

function Invoke-ToolsScan {
    $cat = 'Werkzeuge'
    Clear-CategoryFindings $cat
    Write-Title 'Reparatur-Werkzeuge'
    Write-Step 'Werkzeuge werden vorbereitet'

    $wuSev = 'Info'
    $wuDetail = 'Hilft, wenn Updates hängen, mit Fehlern abbrechen oder die Suche nicht endet.'
    if ($Script:WindowsUpdateFailed) { $wuSev = 'Warnung'; $wuDetail = 'Die Update-Suche ist fehlgeschlagen. ' + $wuDetail }
    Add-Finding $cat $wuSev 'Windows Update reparieren' -Detail $wuDetail -FixLabel 'Update-Komponenten zurücksetzen' -Fix { param($d) Repair-WindowsUpdateComponents }

    Add-Finding $cat Info 'Systemdateien prüfen und reparieren' -Detail 'SFC und DISM prüfen alle Windows-Dateien und ersetzen beschädigte (ca. 15–30 Minuten).' `
        -FixLabel 'Systemdateien prüfen und reparieren' -Fix { param($d) Repair-SystemFiles }

    Add-Finding $cat Info 'Startmenü oder Windows-Suche funktionieren nicht' -FixLabel 'Startmenü und Suche reparieren' -Fix { param($d) Repair-StartMenuSearch }
    Add-Finding $cat Info 'Microsoft Store lädt nicht oder Apps aktualisieren sich nicht' -FixLabel 'Microsoft Store zurücksetzen' -Fix { param($d) Repair-StoreApps }

    $stuck = @()
    try {
        $stuck = @(Get-Printer -ErrorAction Stop | ForEach-Object { Get-PrintJob -PrinterName $_.Name -ErrorAction SilentlyContinue } |
                Where-Object { "$($_.JobStatus)" -match 'Error|Fehler|Blocked' -or $_.SubmittedTime -lt (Get-Date).AddHours(-1) })
    } catch { }
    $prSev = if ($stuck) { 'Warnung' } else { 'Info' }
    Add-Finding $cat $prSev $(if ($stuck) { "$($stuck.Count) Druckauftrag/-aufträge hängen fest" } else { 'Drucker druckt nicht / Warteschlange hängt' }) `
        -FixLabel 'Druckerwarteschlange leeren' -Fix { param($d) Clear-PrintQueue }

    $audio = Get-Service -Name Audiosrv -ErrorAction SilentlyContinue
    $auSev = if ($audio -and $audio.Status -ne 'Running') { 'Warnung' } else { 'Info' }
    Add-Finding $cat $auSev $(if ($auSev -eq 'Warnung') { 'Der Windows-Audiodienst läuft nicht – kein Ton' } else { 'Kein Ton oder Audio-Aussetzer' }) `
        -FixLabel 'Audiodienste neu starten' -Fix { param($d) Restart-AudioServices }

    if (Get-Service -Name bthserv -ErrorAction SilentlyContinue) {
        Add-Finding $cat Info 'Bluetooth-Geräte verbinden sich nicht' -FixLabel 'Bluetooth-Dienst neu starten' -Fix { param($d) Restart-BluetoothService }
    }

    Add-Finding $cat Info 'Netzwerkprobleme trotz WLAN-Verbindung' -FixLabel 'Netzwerkstack zurücksetzen (Verbindung wird kurz getrennt)' -RequiresReboot -Fix { param($d) Reset-NetworkStack }
    Add-Finding $cat Info 'Arbeitsspeicher (RAM) auf Fehler testen' -Detail 'Der Test läuft beim nächsten Neustart vor Windows und dauert ca. 10–20 Minuten.' `
        -FixLabel 'Arbeitsspeicher-Test planen' -RequiresReboot -Fix { param($d) Request-MemoryTest }
    Add-Finding $cat Info 'Belastungstest: Lüfter, Temperatur und Drosselung prüfen' -Detail 'Lastet den Prozessor 30 Sekunden voll aus. Netzteil anschließen für ein aussagekräftiges Ergebnis.' `
        -FixLabel 'Belastungstest starten (30 Sekunden)' -Fix { param($d) Invoke-StressTest -Seconds 30 }
    Add-Finding $cat Info 'Energiebericht: Was verhindert Energiesparen und verkürzt die Akkulaufzeit?' `
        -FixLabel 'Energiebericht erstellen (60 Sekunden)' -Fix { param($d) New-PowerReport -Art Energy }
    Add-Finding $cat Info 'Standby-Analyse: Was verbraucht im zugeklappten Zustand Akku?' `
        -FixLabel 'Standby-Analyse erstellen' -Fix { param($d) New-PowerReport -Art SleepStudy }
    Add-Finding $cat Info 'Komponentenspeicher (WinSxS) von alten Update-Versionen bereinigen' `
        -FixLabel 'Komponentenspeicher bereinigen (DISM, ca. 5–15 Min.)' `
        -Fix { param($d) $c = Invoke-Native 'dism.exe' '/Online /Cleanup-Image /StartComponentCleanup'; Register-Change -Beschreibung 'Komponentenspeicher bereinigt' -Typ 'Protokoll' -NichtUmkehrbar; "DISM beendet (Exitcode $c)." }

    $defender = Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue |
        Where-Object { $_.displayName -match 'Defender' -and (([int]$_.productState -shr 12) -band 0xF) -eq 1 }
    if ($defender) {
        Add-Finding $cat Info 'Schnellscan mit Microsoft Defender' -FixLabel 'Defender-Schnellscan ausführen (ca. 2–10 Min.)' `
            -Fix { param($d) Start-MpScan -ScanType QuickScan -ErrorAction Stop; $t = Get-MpThreatDetection -ErrorAction SilentlyContinue | Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddHours(-1) }; if ($t) { "Scan abgeschlossen – $(@($t).Count) Bedrohung(en) erkannt, siehe Windows-Sicherheit." } else { 'Scan abgeschlossen – keine Bedrohungen gefunden.' } }
    }
    Add-FileToolFindings -Category $cat
    Add-DriverBackupToolFinding -Category $cat
    Add-Finding $cat Info 'Wiederherstellungspunkt jetzt erstellen' -FixLabel 'Systemwiederherstellungspunkt erstellen' -Fix { param($d) New-RestorePoint; 'Wiederherstellungspunkt angelegt (sofern Windows es zulässt).' }
}

#endregion
