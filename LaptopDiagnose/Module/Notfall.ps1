<#
    Notfall-Starthilfe und Windows-Reparatur ohne Datenverlust:
    abgesicherter Modus mit Rückweg, Neustart in die Reparaturumgebung, Prüfung von Reparaturumgebung und Startkonfiguration,
    In-Place-Upgrade-Assistent (prüft Platz, Version, Sprache und Edition der Installationsdatei).
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:SafeModeExitFile = 'Abgesicherten Modus beenden.cmd'

function Get-SafeBootValue {
    <# Wert von »safeboot« im aktuellen Starteintrag (leer = normaler Start). #>
    $out = @(& bcdedit.exe /enum '{current}' 2>&1 | ForEach-Object { "$_" })
    foreach ($l in $out) { if ($l -match '^\s*safeboot\s+(\S+)') { return $Matches[1] } }
    return ''
}

function Get-WinReState {
    $out = @(& reagentc.exe /info 2>&1 | ForEach-Object { "$_" })
    $state = 'Unbekannt'
    foreach ($l in $out) {
        if ($l -match '(?i)(Windows RE.*(status|Status)|Status.*Windows RE)\s*:\s*(\S+)') {
            $state = if ($Matches[3] -match '(?i)^(enabled|aktiviert)') { 'Aktiv' } elseif ($Matches[3] -match '(?i)^(disabled|deaktiviert)') { 'Aus' } else { $Matches[3] }
        }
    }
    [pscustomobject]@{ State = $state; Output = $out }
}

function Get-SafeModeExitPath { Join-Path ([Environment]::GetFolderPath('Desktop')) $Script:SafeModeExitFile }

function New-SafeModeExitFile {
    $path = Get-SafeModeExitPath
    $lines = @(
        '@echo off'
        'rem PC Repair Pro: beendet den abgesicherten Modus und startet Windows normal neu.'
        'net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -Verb RunAs -FilePath ''%~f0''" & exit /b)'
        'bcdedit /deletevalue {current} safeboot'
        'bcdedit /deletevalue {current} safebootalternateshell >nul 2>&1'
        'del "%~f0" & shutdown /r /t 5 /c "Windows startet wieder normal."'
    )
    [IO.File]::WriteAllLines($path, [string[]]$lines, [Text.Encoding]::ASCII)
    return $path
}

function Clear-SafeBoot {
    $null = & bcdedit.exe /deletevalue '{current}' safeboot 2>&1
    $null = & bcdedit.exe /deletevalue '{current}' safebootalternateshell 2>&1
    $f = Get-SafeModeExitPath
    if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
}

function Add-EmergencyStartToolFindings {
    param([string]$Category)
    $spec = @{
        Text    = 'Windows startet beim nächsten Neustart im abgesicherten Modus – nur mit den nötigsten Treibern. Ideal, um einen fehlerhaften Treiber, ein Programm oder Schadsoftware zu entfernen, die den normalen Start verhindert.'
        Warning = 'Rückweg: Auf dem Desktop liegt danach »Abgesicherten Modus beenden« – Doppelklick, und Windows startet wieder normal. Alternativ hier unter »Änderungen« rückgängig machen.'
        Fields  = @(
            @{ Name = 'Modus'; Type = 'Auswahl'; Label = 'Art'; Items = @('Minimal (ohne Netzwerk)', 'Mit Netzwerk (Internet funktioniert)'); Default = 0 }
            @{ Name = 'Jetzt'; Type = 'Haken'; Label = 'Sofort neu starten (in 15 Sekunden)'; Default = $false }
        )
    }
    Add-Finding $Category Info 'Abgesicherter Modus (mit Rückweg)' -Silent -Repeatable -AskParams $spec `
        -Detail 'Stellt den nächsten Start auf den abgesicherten Modus um und legt eine Datei »Abgesicherten Modus beenden« auf den Desktop, mit der es per Doppelklick wieder zurückgeht.' `
        -FixLabel 'Abgesicherten Modus einschalten' -FixData @{ Spec = $spec } -Fix {
        param($d)
        $o = Resolve-FixParams $d.Spec
        $mode = @('minimal', 'network')[[int](Get-Choice @(0, 1) $o.Modus)]
        $out = & bcdedit.exe /set '{current}' safeboot $mode 2>&1
        if ($LASTEXITCODE -ne 0) { throw "bcdedit meldet einen Fehler: $($out -join ' ')" }
        $file = New-SafeModeExitFile
        Register-Change -Beschreibung "Abgesicherter Modus ($(if ($mode -eq 'network') { 'mit Netzwerk' } else { 'minimal' })) für den nächsten Start eingeschaltet" -Typ 'Abgesichert' -Daten @{ Datei = $file } `
            -Hinweis 'Rückgängig machen schaltet wieder auf normalen Start.'
        $Script:RebootNeeded = $true
        if ($o.Jetzt) { $null = & shutdown.exe /r /t 15 /c 'PC Repair Pro: Neustart in den abgesicherten Modus.' 2>&1; return 'Neustart in den abgesicherten Modus in 15 Sekunden.' }
        "Beim nächsten Neustart startet Windows im abgesicherten Modus. Rückweg: »$($Script:SafeModeExitFile)« auf dem Desktop."
    }
    $spec = @{
        Text    = 'Startet den PC in die Windows-Reparaturumgebung (blauer Bildschirm »Option auswählen«). Dort gibt es unter »Problembehandlung → Erweiterte Optionen«: Starthilfe, Systemwiederherstellung, Updates deinstallieren, Eingabeaufforderung, UEFI-Einstellungen und Starteinstellungen (abgesicherter Modus).'
        Warning = 'Der PC startet in 10 Sekunden neu – vorher alle Dateien speichern.'
        Fields  = @(@{ Name = 'Bestaetigung'; Type = 'Haken'; Label = 'Alles gespeichert – jetzt neu starten'; Default = $false })
    }
    Add-Finding $Category Info 'Neustart in die Reparaturumgebung' -Silent -Repeatable -AskParams $spec `
        -Detail 'Für den Fall, dass Windows nur noch fehlerhaft startet: Starthilfe, Systemwiederherstellung oder das letzte Update deinstallieren – alles ohne Installations-Stick.' `
        -FixLabel 'In die Reparaturumgebung neu starten' -FixData @{ Spec = $spec } -Fix {
        param($d)
        $o = Resolve-FixParams $d.Spec
        if (-not $o.Bestaetigung) { throw 'Bitte bestätigen, dass alles gespeichert ist – kein Neustart.' }
        $out = & shutdown.exe /r /o /t 10 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Neustart nicht möglich: $($out -join ' ')" }
        'Der PC startet in 10 Sekunden in die Reparaturumgebung.'
    }
}

function Add-BootHealthFindings {
    <# Prüfung im Fehler-Scan: Reparaturumgebung verfügbar, kein hängengebliebener abgesicherter Modus. #>
    param([string]$Category)
    $sb = Get-SafeBootValue
    if ($sb) {
        Add-Finding $Category Warnung "Windows ist dauerhaft auf den abgesicherten Modus eingestellt ($sb)" `
            -Detail 'Jeder Start erfolgt im abgesicherten Modus – mit eingeschränkten Treibern, ohne Autostart und oft ohne Netzwerk. Meist wurde vergessen, die Einstellung zurückzunehmen.' `
            -FixLabel 'Wieder normal starten' -Fix { param($d) Clear-SafeBoot; $Script:RebootNeeded = $true; Register-Change -Beschreibung 'Abgesicherten Modus beendet (normaler Start)' -Typ 'Protokoll' -NichtUmkehrbar; 'Ab dem nächsten Neustart startet Windows wieder normal.' } -RequiresReboot
    }
    $re = Get-WinReState
    switch ($re.State) {
        'Aktiv' { Add-Finding $Category OK 'Windows-Reparaturumgebung ist einsatzbereit' -Detail 'Bei Startproblemen öffnet Windows automatisch die Starthilfe.' }
        'Aus' {
            Add-Finding $Category Warnung 'Windows-Reparaturumgebung ist ausgeschaltet' `
                -Detail 'Startet Windows einmal nicht, gibt es weder Starthilfe noch Systemwiederherstellung oder »Update deinstallieren« – dann hilft nur noch ein Installations-Stick.' `
                -FixLabel 'Reparaturumgebung einschalten' -Fix {
                param($d)
                $out = & reagentc.exe /enable 2>&1
                if ($LASTEXITCODE -ne 0) { throw "Einschalten nicht möglich (oft fehlt die Datei Winre.wim): $($out -join ' ')" }
                Register-Change -Beschreibung 'Windows-Reparaturumgebung eingeschaltet' -Typ 'Protokoll' -NichtUmkehrbar
                'Reparaturumgebung ist wieder eingeschaltet.'
            }
        }
        default { Add-Finding $Category Info 'Zustand der Reparaturumgebung nicht ermittelbar' -Items @($re.Output | Select-Object -First 6) }
    }
    $boot = @(& bcdedit.exe /enum '{current}' 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE -ne 0) { Add-Finding $Category Warnung 'Startkonfiguration (BCD) nicht lesbar' -Items @($boot | Select-Object -First 4) -Detail 'Kann auf eine beschädigte Startkonfiguration hindeuten. Reparatur über »Neustart in die Reparaturumgebung« → Problembehandlung → Starthilfe.' }
    else { Add-Finding $Category OK 'Startkonfiguration (BCD) ist lesbar' }
}

function Get-InstallImageInfo {
    <# Liest Editionen, Build, Architektur und Sprache aus install.wim/install.esd des eingebundenen Abbilds. #>
    param([string]$Root)
    $img = @('install.wim', 'install.esd', 'install.swm') | ForEach-Object { Join-Path $Root "sources\$_" } | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $img) { throw 'Keine Windows-Installationsdatei gefunden (sources\install.wim/.esd fehlt) – ist das ein Windows-Abbild?' }
    $list = @(Get-WindowsImage -ImagePath $img -ErrorAction Stop)
    $details = @($list | ForEach-Object { Get-WindowsImage -ImagePath $img -Index $_.ImageIndex -ErrorAction SilentlyContinue })
    [pscustomobject]@{ Path = $img; Images = $details }
}

function Test-RepairInstallSource {
    <# Prüft, ob das Abbild zum installierten Windows passt; liefert Probleme und Hinweise. #>
    param($Info)
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cur = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $curBuild = [int]$os.BuildNumber
    $curArch = if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $curArch = 'arm64' }
    $curLang = try { ([Globalization.CultureInfo]::GetCultureInfo([int]$os.OSLanguage)).Name } catch { '' }
    $problems = @(); $notes = @()
    $imgs = @($Info.Images)
    $match = $imgs | Where-Object { "$($_.EditionId)" -eq "$($cur.EditionID)" } | Select-Object -First 1
    if (-not $match) { $problems += "Edition »$($cur.EditionID)« ist im Abbild nicht enthalten (enthalten: $(@($imgs | ForEach-Object { $_.EditionId }) -join ', '))."; $match = $imgs | Select-Object -First 1 }
    if ($match) {
        $archMap = @{ 0 = 'x86'; 9 = 'x64'; 12 = 'arm64' }
        $a = $archMap[[int]$match.Architecture]
        if ($a -and $a -ne $curArch) { $problems += "Architektur passt nicht: Abbild $a, installiert $curArch." }
        $b = 0; if ("$($match.Version)" -match '^\d+\.\d+\.(\d+)') { $b = [int]$Matches[1] }
        if ($b -and $b -lt $curBuild) { $problems += "Abbild ist älter (Build $b) als das installierte Windows (Build $curBuild) – Daten und Programme können damit nicht behalten werden." }
        elseif ($b) { $notes += "Version: Build $b (installiert $curBuild)" }
        $langs = @($match.Languages)
        if ($curLang -and $langs -and -not ($langs -contains $curLang)) { $problems += "Sprache passt nicht: Abbild $($langs -join ', '), installiert $curLang – »Persönliche Dateien und Apps behalten« wäre dann nicht möglich." }
        elseif ($langs) { $notes += "Sprache: $($langs -join ', ')" }
        $notes += "Edition: $($match.ImageName)"
    }
    [pscustomobject]@{ Problems = $problems; Notes = $notes }
}

function Add-RepairInstallToolFinding {
    param([string]$Category)
    $spec = @{
        Text   = 'Installiert Windows über sich selbst neu (In-Place-Upgrade): Systemdateien, Komponenten und Windows Update werden erneuert, persönliche Dateien, Programme und Einstellungen bleiben erhalten. Das hilft, wenn SFC/DISM nicht mehr weiterkommen. Dauer: 30–90 Minuten mit mehreren Neustarts.'
        Warning = 'Vorher eine Sicherung der wichtigsten Dateien machen und den Laptop ans Netzteil hängen. Die Installationsdatei muss dieselbe Sprache und Edition haben und mindestens so neu sein wie das installierte Windows.'
        Fields = @(
            @{ Name = 'Weg'; Type = 'Auswahl'; Label = 'Installationsdatei'; Items = @('Vorhandene ISO-Datei verwenden', 'Download-Seite von Microsoft öffnen (ISO herunterladen)'); Default = 0 }
            @{ Name = 'Datei'; Type = 'Datei'; Label = 'ISO-Datei (bei vorhandener ISO)'; Mode = 'Oeffnen'; Filter = 'Windows-Abbild (*.iso)|*.iso'; Default = '' }
        )
    }
    Add-Finding $Category Info 'Windows reparieren ohne Datenverlust (In-Place-Upgrade)' -Silent -Repeatable -AskParams $spec `
        -Detail 'Assistent für die Reparaturinstallation: prüft freien Platz, Version, Sprache und Edition der ISO-Datei und startet danach das Windows-Setup mit »Persönliche Dateien und Apps behalten«.' `
        -FixLabel 'Reparaturinstallation vorbereiten' -FixData @{ Spec = $spec } -Fix {
        param($d)
        $o = Resolve-FixParams $d.Spec
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $isWin11 = [int]$os.BuildNumber -ge 22000
        $page = if ($isWin11) { 'https://www.microsoft.com/de-de/software-download/windows11' } else { 'https://www.microsoft.com/de-de/software-download/windows10' }
        if ([int](Get-Choice @(0, 1) $o.Weg) -eq 1) {
            Start-Process $page
            return "Download-Seite geöffnet – dort »Datenträgerimage (ISO) herunterladen«, Sprache »Deutsch« wählen und danach diesen Assistenten mit der ISO-Datei erneut starten."
        }
        $sys = (Get-Volume -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction SilentlyContinue)
        if ($sys -and [double]$sys.SizeRemaining -lt 20GB) { throw "Zu wenig freier Platz auf $($env:SystemDrive): $(Format-Bytes ([double]$sys.SizeRemaining)) frei, mindestens 20 GB nötig. Vorher unter »Speicher« aufräumen." }
        $iso = "$($o.Datei)".Trim().Trim('"')
        if (-not (Test-Path -LiteralPath $iso -PathType Leaf)) { throw "ISO-Datei nicht gefunden: $iso" }
        $mounted = Mount-DiskImage -ImagePath $iso -PassThru -ErrorAction Stop
        $ok = $false
        try {
            $letter = ($mounted | Get-Volume -ErrorAction Stop | Select-Object -First 1).DriveLetter
            if (-not $letter) { throw 'Die ISO-Datei konnte nicht eingebunden werden.' }
            $root = "$($letter):\"
            $info = Get-InstallImageInfo -Root $root
            $check = Test-RepairInstallSource $info
            if ($check.Problems) { throw ("Diese ISO-Datei passt nicht für eine Reparatur ohne Datenverlust:`n- " + ($check.Problems -join "`n- ") + "`nPassende ISO: $page") }
            $setup = $root + 'setup.exe'
            Start-Process -FilePath $setup -ArgumentList '/auto upgrade /eula accept /showoobe none /dynamicupdate enable'
            $ok = $true
            Register-Change -Beschreibung "Reparaturinstallation (In-Place-Upgrade) gestartet mit $([IO.Path]::GetFileName($iso))" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis ($check.Notes -join '; ')
            "Windows-Setup gestartet ($($check.Notes -join ', ')). Es behält Dateien und Programme und startet den PC mehrmals neu."
        } finally {
            if (-not $ok) { Dismount-DiskImage -ImagePath $iso -ErrorAction SilentlyContinue | Out-Null }
        }
    }
}
