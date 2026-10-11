<#
    Erweiterte Sicherheit: Ransomware-Schutz, PUA-Schutz, SmartScreen, Konten, automatische Anmeldung, Gastkonto,
    Fernwartungsprogramme. Defender-Einstellungen werden nur angezeigt und über »Windows-Sicherheit« geändert
    (das Tool schreibt bewusst nicht selbst in die Defender-Konfiguration).
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:RemoteToolPattern = 'AnyDesk|TeamViewer|RustDesk|Splashtop|Chrome Remote Desktop|LogMeIn|ScreenConnect|ConnectWise Control|Supremo|Ammyy|UltraViewer|RemotePC|Zoho Assist|DWService|Remote Utilities|AeroAdmin|NoMachine|Parsec|Quick ?Assist'

function Test-DefenderIsActiveAv {
    $av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue | Where-Object { (([int]$_.productState -shr 12) -band 0xF) -eq 1 })
    return [bool]($av | Where-Object { $_.displayName -match 'Defender' }) -and -not ($av | Where-Object { $_.displayName -notmatch 'Defender' })
}

function Add-DefenderExtrasFindings {
    param([string]$Category)
    if (-not (Test-DefenderIsActiveAv)) {
        Add-Finding $Category OK 'Ransomware- und PUA-Schutz: wird vom installierten Virenschutz übernommen' -Detail 'Die Defender-Zusatzfunktionen sind nur aktiv, wenn Microsoft Defender der Virenschutz ist. Der installierte Virenschutz bringt eigene Schutzfunktionen mit – dort prüfen.'
        return
    }
    $p = Get-MpPreference -ErrorAction Stop
    $open = { param($d) Start-Process 'windowsdefender://ransomwareprotection'; 'Windows-Sicherheit geöffnet.' }
    if ([int]$p.EnableControlledFolderAccess -ne 1) {
        Add-Finding $Category Info 'Ransomware-Schutz (überwachter Ordnerzugriff) ist aus' `
            -Detail 'Schützt Dokumente, Bilder und Desktop vor Verschlüsselungstrojanern: Nur vertrauenswürdige Programme dürfen dort Dateien ändern. Manche Programme (z. B. ältere Spiele, Bildbearbeitung) müssen danach einmal freigegeben werden.' `
            -FixLabel 'Ransomware-Schutz in Windows-Sicherheit öffnen' -Fix $open
    } else { Add-Finding $Category OK 'Ransomware-Schutz (überwachter Ordnerzugriff) ist aktiv' }
    if ([int]$p.PUAProtection -ne 1) {
        Add-Finding $Category Warnung 'Schutz vor potenziell unerwünschten Apps (PUA) ist aus' `
            -Detail 'Blockiert Adware, Browser-Umleitungen und gebündelte »Zusatzangebote« in Installationsprogrammen. Einschalten unter »Windows-Sicherheit › App- und Browsersteuerung › Zuverlässigkeitsbasierter Schutz«.' `
            -FixLabel 'App- und Browsersteuerung öffnen' -Fix { param($d) Start-Process 'windowsdefender://appbrowser'; 'Windows-Sicherheit geöffnet.' }
    } else { Add-Finding $Category OK 'PUA-Schutz ist aktiv' }
}

function Add-SmartScreenFindings {
    param([string]$Category)
    $explorer = $null; $policy = $null; $edge = $null
    try { $explorer = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name SmartScreenEnabled -ErrorAction Stop).SmartScreenEnabled } catch { }
    try { $policy = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name EnableSmartScreen -ErrorAction Stop).EnableSmartScreen } catch { }
    try { $edge = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Edge\SmartScreenEnabled' -Name '(default)' -ErrorAction Stop).'(default)' } catch { }
    $off = @()
    if ("$explorer" -eq 'Off' -or "$policy" -eq '0') { $off += 'Apps und Dateien' }
    if ("$edge" -eq '0') { $off += 'Microsoft Edge' }
    if ($off) {
        Add-Finding $Category Warnung "SmartScreen ist ausgeschaltet ($($off -join ', '))" `
            -Detail 'SmartScreen warnt vor bekannten Schadprogrammen und Betrugsseiten, bevor sie ausgeführt bzw. geöffnet werden.' `
            -FixLabel 'App- und Browsersteuerung öffnen' -Fix { param($d) Start-Process 'windowsdefender://appbrowser'; 'Windows-Sicherheit geöffnet.' }
    } else { Add-Finding $Category OK 'SmartScreen ist eingeschaltet' }
}

function Add-AccountFindings {
    param([string]$Category)
    if (-not (Get-Command Get-LocalUser -ErrorAction SilentlyContinue)) { return }
    $users = @(Get-LocalUser -ErrorAction Stop)
    # Gastkonto (SID endet auf -501)
    $guest = $users | Where-Object { "$($_.SID)" -match '-501$' } | Select-Object -First 1
    if ($guest -and $guest.Enabled) {
        Add-Finding $Category Warnung 'Das Gastkonto ist aktiviert' -Detail 'Jeder kann sich ohne Kennwort anmelden und Netzwerkfreigaben sehen. Wird es nicht ausdrücklich gebraucht, sollte es deaktiviert sein.' `
            -FixLabel 'Gastkonto deaktivieren' -FixData @{ Sid = "$($guest.SID)"; Name = $guest.Name } -Fix {
            param($d)
            Disable-LocalUser -SID $d.Sid -ErrorAction Stop
            Register-Change -Beschreibung "Gastkonto »$($d.Name)« deaktiviert" -Typ 'Konto' -Daten @{ Sid = $d.Sid; Aktion = 'Deaktiviert' }
            'Gastkonto deaktiviert.'
        }
    }
    # Aktive lokale Konten ohne Kennwortpflicht bzw. ohne je gesetztes Kennwort
    $weak = @($users | Where-Object { $_.Enabled -and "$($_.SID)" -notmatch '-50[0-3]$' -and "$($_.PrincipalSource)" -eq 'Local' -and (-not $_.PasswordRequired -or -not $_.PasswordLastSet) })
    if ($weak) {
        Add-Finding $Category Warnung "$($weak.Count) lokale(s) Konto/Konten möglicherweise ohne Kennwort" -Items @($weak | ForEach-Object { "$($_.Name)$(if (-not $_.PasswordLastSet) { ' – Kennwort nie gesetzt' })" }) `
            -Detail 'Ohne Kennwort kann jeder mit Zugang zum Gerät auf alle Daten zugreifen. Kennwort oder Windows-Hello-PIN einrichten.' `
            -FixLabel 'Anmeldeoptionen öffnen' -Fix { param($d) Start-Process 'ms-settings:signinoptions'; 'Anmeldeoptionen geöffnet.' }
    }
    # Automatische Anmeldung (Kennwort steht dann oft im Klartext in der Registry)
    $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $auto = $null; $pw = $null
    try { $p = Get-ItemProperty -Path $wl -ErrorAction Stop; $auto = $p.AutoAdminLogon; $pw = $p.DefaultPassword } catch { }
    if ("$auto" -eq '1') {
        $detail = 'Windows meldet sich ohne Kennwortabfrage an – jeder, der das Gerät einschaltet, ist angemeldet.'
        if ($pw) { $detail += ' Das Kennwort ist dafür im Klartext in der Registry gespeichert.' }
        Add-Finding $Category Warnung 'Automatische Anmeldung ist eingeschaltet' -Detail $detail -FixLabel 'Automatische Anmeldung ausschalten' -FixData @{ HasPassword = [bool]$pw } -Fix {
            param($d)
            Set-RegistryValueTracked -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name AutoAdminLogon -Value '0' -Type String -Beschreibung 'Automatische Anmeldung ausgeschaltet'
            # Das gespeicherte Kennwort wird entfernt und bewusst NICHT im Änderungsprotokoll gesichert
            if ($d.HasPassword) { Remove-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultPassword -ErrorAction SilentlyContinue }
            'Automatische Anmeldung ausgeschaltet' + $(if ($d.HasPassword) { ' und gespeichertes Klartext-Kennwort entfernt.' } else { '.' })
        }
    }
}

function Add-RemoteToolFindings {
    param([string]$Category)
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    $installed = @(Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match $Script:RemoteToolPattern } | ForEach-Object { "$($_.DisplayName)" } | Select-Object -Unique)
    $services = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { "$($_.DisplayName) $($_.PathName)" -match $Script:RemoteToolPattern -and $_.StartMode -eq 'Auto' })
    $running = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'AnyDesk|TeamViewer|rustdesk|Splashtop|remoting_host|ScreenConnect|Supremo|AA_v3|UltraViewer|AeroAdmin' } | ForEach-Object { $_.ProcessName } | Select-Object -Unique)
    if (-not $installed -and -not $services -and -not $running) { Add-Finding $Category OK 'Keine Fernwartungsprogramme gefunden'; return }
    $items = @($installed | ForEach-Object { "installiert: $_" }) + @($services | ForEach-Object { "startet automatisch: $($_.DisplayName)" }) + @($running | ForEach-Object { "läuft gerade: $_" })
    $sev = if ($services -or $running) { 'Warnung' } else { 'Info' }
    Add-Finding $Category $sev 'Fernwartungsprogramm(e) gefunden' -Items $items `
        -Detail 'Mit diesen Programmen kann jemand aus der Ferne den Computer steuern. Das ist praktisch für Hilfe durch Bekannte – wird aber auch von Betrügern genutzt (»Microsoft-Support« am Telefon). Programme, die man nicht selbst installiert hat oder nicht mehr braucht, deinstallieren (Werkzeug »Programme deinstallieren« im Bereich Speicherfresser); ein dauerhaft startender Dienst ist nur nötig, wenn unbeaufsichtigter Zugriff gewollt ist.'
}

function Add-ExtendedSecurityFindings {
    param([string]$Category)
    Invoke-Check $Category 'Ransomware- und PUA-Schutz' { Add-DefenderExtrasFindings -Category $Category }
    Invoke-Check $Category 'SmartScreen' { Add-SmartScreenFindings -Category $Category }
    Invoke-Check $Category 'Benutzerkonten und Anmeldung' { Add-AccountFindings -Category $Category }
    Invoke-Check $Category 'Fernwartungsprogramme' { Add-RemoteToolFindings -Category $Category }
}
