<#
    Sicherheitsprüfung: Virenschutz, Firewall, Secure Boot, TPM, Verschlüsselung, Kernisolierung,
    Benutzerkontensteuerung, SMB1, Freigaben, Remotedesktop, pausierte Updates und veraltete Browser.
    Teil von LaptopDiagnose – Copyright 2026 by Eder Tom
#>

function Invoke-SecurityScan {
    $cat = 'Sicherheit'
    Clear-CategoryFindings $cat
    Write-Title 'Sicherheit'

    Invoke-Check $cat 'Datensicherung' { Add-BackupStatusFindings -Category $cat }
    Invoke-Check $cat 'Datenschutz-Einstellungen' { Add-PrivacyFindings -Category $cat }
    Invoke-Check $cat 'Browser-Erweiterungen' { Add-BrowserExtensionFindings -Category $cat }
    Invoke-Check $cat 'Browser-Entführer (Startseite, Suche, DNS, Hosts)' { Add-HijackFindings -Category $cat }

    Invoke-Check $cat 'Virenschutz' {
        $av = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntiVirusProduct -ErrorAction SilentlyContinue)
        $activeAv = @($av | Where-Object { (([int]$_.productState -shr 12) -band 0xF) -eq 1 })
        if (-not $activeAv) {
            Add-Finding $cat Kritisch 'Kein aktiver Virenschutz gefunden' `
                -Detail 'Den Echtzeitschutz bitte in der Windows-Sicherheit einschalten oder ein anderes Virenschutzprogramm aktivieren.' `
                -FixLabel 'Windows-Sicherheit (Viren- & Bedrohungsschutz) öffnen' `
                -Fix { param($d) Start-Process 'windowsdefender://threatsettings'; 'Windows-Sicherheit geöffnet – bitte dort den Echtzeitschutz einschalten.' }
        } else {
            foreach ($p in $activeAv) {
                $outdated = (([int]$p.productState -shr 4) -band 0xF) -ne 0
                if ($outdated -and $p.displayName -match 'Defender') {
                    Add-Finding $cat Warnung "Virenschutz »$($p.displayName)« ist nicht aktuell" `
                        -FixLabel 'Virendefinitionen aktualisieren' `
                        -Fix { param($d) Update-MpSignature -ErrorAction Stop; 'Defender-Signaturen aktualisiert.' }
                } elseif ($outdated) {
                    Add-Finding $cat Warnung "Virenschutz »$($p.displayName)« ist nicht aktuell" -Detail 'Bitte im Virenschutzprogramm ein Update starten.'
                } else {
                    Add-Finding $cat OK "Virenschutz aktiv und aktuell: $($p.displayName)"
                }
            }
        }
    }

    Invoke-Check $cat 'Firewall' {
        $thirdPartyFw = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName FirewallProduct -ErrorAction SilentlyContinue |
                Where-Object { (([int]$_.productState -shr 12) -band 0xF) -eq 1 })
        $off = @(Get-NetFirewallProfile -ErrorAction Stop | Where-Object { -not $_.Enabled })
        if ($off -and -not $thirdPartyFw) {
            Add-Finding $cat Kritisch ('Windows-Firewall ist deaktiviert für: ' + (($off | ForEach-Object { $_.Name }) -join ', ')) `
                -FixLabel 'Windows-Firewall für alle Profile aktivieren' -FixData @($off | ForEach-Object { $_.Name }) `
                -Fix {
                param($d)
                Set-NetFirewallProfile -Profile $d -Enabled True -ErrorAction Stop
                Register-Change -Beschreibung "Windows-Firewall aktiviert ($($d -join ', '))" -Typ 'Protokoll' -NichtUmkehrbar -Hinweis 'Sicherheitsrelevant – wird nicht automatisch zurückgenommen.'
                'Firewall aktiviert.'
            }
        } elseif ($thirdPartyFw) {
            Add-Finding $cat OK "Firewall aktiv: $(($thirdPartyFw | ForEach-Object { $_.displayName }) -join ', ')"
        } else {
            Add-Finding $cat OK 'Windows-Firewall ist für alle Netzwerkprofile aktiv'
        }
    }

    Invoke-Check $cat 'Secure Boot' {
        $sb = $null
        try { $sb = Confirm-SecureBootUEFI -ErrorAction Stop } catch { }
        if ($sb -eq $true) {
            Add-Finding $cat OK 'Secure Boot ist aktiv'
        } elseif ($sb -eq $false) {
            Add-Finding $cat Warnung 'Secure Boot ist ausgeschaltet' `
                -Detail 'Secure Boot schützt vor Schadsoftware, die sich vor Windows lädt. Einschalten im BIOS/UEFI-Setup (beim Start meist F2, F10 oder Entf) unter »Security« bzw. »Boot«.'
        } else {
            Add-Finding $cat Info 'Secure Boot wird nicht unterstützt oder konnte nicht geprüft werden (Legacy-BIOS?)'
        }
    }

    Invoke-Check $cat 'TPM-Sicherheitschip' {
        $tpm = Get-Tpm -ErrorAction Stop
        $ver = $null
        try { $ver = ((Get-CimInstance -Namespace root/cimv2/Security/MicrosoftTpm -ClassName Win32_Tpm -ErrorAction Stop).SpecVersion -split ',')[0].Trim() } catch { }
        if (-not $tpm.TpmPresent) {
            Add-Finding $cat Warnung 'Kein TPM-Sicherheitschip gefunden' -Detail 'TPM wird für Windows 11, BitLocker und Windows Hello benötigt. Ggf. im BIOS aktivieren (Intel PTT / AMD fTPM).'
        } elseif (-not $tpm.TpmReady) {
            Add-Finding $cat Warnung "TPM $ver ist vorhanden, aber nicht einsatzbereit" -Detail 'TPM im BIOS aktivieren bzw. in »tpm.msc« initialisieren.'
        } else {
            Add-Finding $cat OK "TPM $ver ist aktiv und einsatzbereit"
        }
    }

    Invoke-Check $cat 'Laufwerksverschlüsselung' {
        $drive = $env:SystemDrive
        $status = $null; $percent = $null; $isPro = $false
        if (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue) {
            try {
                $bl = Get-BitLockerVolume -MountPoint $drive -ErrorAction Stop
                $isPro = $true
                $status = "$($bl.ProtectionStatus)"
                $percent = $bl.EncryptionPercentage
            } catch { }
        }
        if (-not $status) {
            $vol = Get-CimInstance -Namespace root/cimv2/Security/MicrosoftVolumeEncryption -ClassName Win32_EncryptableVolume -Filter "DriveLetter='$drive'" -ErrorAction Stop
            $status = switch ([int]$vol.ProtectionStatus) { 1 { 'On' } 0 { 'Off' } default { 'Unknown' } }
        }
        if ($status -eq 'On') {
            Add-Finding $cat OK "Systemlaufwerk $drive ist verschlüsselt$(if ($percent) { " ($percent %)" })" `
                -Detail 'Tipp: Den Wiederherstellungsschlüssel sicher aufbewahren (z. B. im Microsoft-Konto unter account.microsoft.com/devices/recoverykey).'
        } else {
            $fixTarget = if ($isPro) { 'control.exe' } else { 'ms-settings:deviceencryption' }
            Add-Finding $cat Warnung "Systemlaufwerk $drive ist nicht verschlüsselt" `
                -Detail "Bei Verlust oder Diebstahl des $(if ((Get-DeviceKind) -eq 'Laptop') { 'Laptops' } else { 'PCs bzw. der Festplatte' }) sind alle Daten lesbar. Verschlüsselung (BitLocker/Geräteverschlüsselung) wird empfohlen – vorher den Wiederherstellungsschlüssel sichern." `
                -FixLabel 'Einstellungen zur Verschlüsselung öffnen' -FixData $fixTarget `
                -Fix { param($d) if ($d -eq 'control.exe') { Start-Process control.exe -ArgumentList '/name Microsoft.BitLockerDriveEncryption' } else { Start-Process $d }; 'Einstellungen geöffnet – Verschlüsselung dort einschalten.' }
        }
    }

    Invoke-Check $cat 'Kernisolierung (Speicherintegrität)' {
        $dg = Get-CimInstance -Namespace root/Microsoft/Windows/DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop
        if (@($dg.SecurityServicesRunning) -contains 2) {
            Add-Finding $cat OK 'Kernisolierung (Speicherintegrität) ist aktiv'
        } else {
            Add-Finding $cat Info 'Kernisolierung (Speicherintegrität) ist ausgeschaltet' `
                -Detail 'Schützt Windows vor manipulierten Treibern. Windows meldet beim Einschalten, falls ein Treiber nicht kompatibel ist.' `
                -FixLabel 'Einstellungen zur Kernisolierung öffnen' `
                -Fix { param($d) Start-Process 'windowsdefender://coreisolation'; 'Windows-Sicherheit geöffnet – »Speicherintegrität« dort einschalten.' }
        }
    }

    Invoke-Check $cat 'Benutzerkontensteuerung (UAC)' {
        $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        $p = Get-ItemProperty -Path $key -ErrorAction Stop
        if ($p.EnableLUA -eq 0) {
            Add-Finding $cat Kritisch 'Benutzerkontensteuerung (UAC) ist komplett ausgeschaltet' `
                -Detail 'Jedes Programm kann ohne Rückfrage Administratorrechte erhalten.' `
                -FixLabel 'Benutzerkontensteuerung einschalten' -RequiresReboot `
                -Fix { param($d) Set-RegistryValueTracked -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name EnableLUA -Value 1 -Beschreibung 'Benutzerkontensteuerung eingeschaltet' -NichtUmkehrbar; 'UAC eingeschaltet (wirksam nach Neustart).' }
        } elseif ($p.ConsentPromptBehaviorAdmin -eq 0) {
            Add-Finding $cat Warnung 'Benutzerkontensteuerung fragt nie nach' `
                -FixLabel 'Benutzerkontensteuerung auf Standardstufe setzen' `
                -Fix {
                param($d)
                $k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                Set-RegistryValueTracked -Path $k -Name ConsentPromptBehaviorAdmin -Value 5 -Beschreibung 'UAC auf Standardstufe gesetzt' -NichtUmkehrbar
                Set-RegistryValueTracked -Path $k -Name PromptOnSecureDesktop -Value 1 -Beschreibung 'UAC: sicherer Desktop eingeschaltet' -NichtUmkehrbar
                'Benutzerkontensteuerung auf Standardstufe gesetzt.'
            }
        } else {
            Add-Finding $cat OK 'Benutzerkontensteuerung ist aktiv'
        }
    }

    Invoke-Check $cat 'Veraltetes Netzwerkprotokoll SMB1' {
        $f = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction Stop
        if ("$($f.State)" -eq 'Enabled') {
            Add-Finding $cat Warnung 'Das unsichere Protokoll SMB1 ist aktiviert' `
                -Detail 'SMB1 wurde z. B. von der Schadsoftware WannaCry ausgenutzt. Nur sehr alte Netzlaufwerke benötigen es.' `
                -FixLabel 'SMB1 deaktivieren' -RequiresReboot `
                -Fix {
                param($d)
                $null = Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop
                Register-Change -Beschreibung 'SMB1-Protokoll deaktiviert' -Typ 'Feature' -Daten @{ Feature = 'SMB1Protocol'; Aktion = 'Deaktiviert' }
                'SMB1 deaktiviert (wirksam nach Neustart).'
            }
        } else {
            Add-Finding $cat OK 'SMB1 ist deaktiviert'
        }
    }

    Invoke-Check $cat 'Freigegebene Ordner' {
        $shares = @(Get-SmbShare -ErrorAction Stop | Where-Object { -not $_.Special -and $_.Name -notin 'print$', 'IPC$' })
        if ($shares) {
            Add-Finding $cat Info "$($shares.Count) Ordner sind im Netzwerk freigegeben" `
                -Detail 'In öffentlichen WLANs können Freigaben ein Risiko sein. Nicht benötigte Freigaben entfernen.' `
                -Items ($shares | ForEach-Object { '{0}  →  {1}' -f $_.Name, $_.Path }) `
                -FixLabel 'Freigaben verwalten öffnen' -Fix { param($d) Start-Process 'fsmgmt.msc'; 'Freigabenverwaltung geöffnet.' }
        } else {
            Add-Finding $cat OK 'Keine Ordner im Netzwerk freigegeben'
        }
    }

    Invoke-Check $cat 'Remotedesktop' {
        $ts = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -ErrorAction Stop
        if ($ts.fDenyTSConnections -eq 0) {
            Add-Finding $cat Info 'Remotedesktop ist eingeschaltet' `
                -Detail "Andere können sich über das Netzwerk an diesem $(Get-DeviceWord) anmelden. Ausschalten, wenn das nicht benötigt wird." `
                -FixLabel 'Remotedesktop ausschalten' `
                -Fix { param($d) Set-RegistryValueTracked -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 1 -Beschreibung 'Remotedesktop ausgeschaltet'; 'Remotedesktop ausgeschaltet.' }
        } else {
            Add-Finding $cat OK 'Remotedesktop ist ausgeschaltet'
        }
    }

    Invoke-Check $cat 'Pausierte Windows-Updates' {
        $key = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
        $p = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        $until = $null
        foreach ($n in 'PauseUpdatesExpiryTime', 'PauseQualityUpdatesEndTime', 'PauseFeatureUpdatesEndTime') {
            if ($p -and $p.$n) { try { $t = [datetime]$p.$n; if ($t -gt (Get-Date) -and (-not $until -or $t -gt $until)) { $until = $t } } catch { } }
        }
        if ($until) {
            Add-Finding $cat Warnung ('Windows-Updates sind pausiert bis {0:dd.MM.yyyy}' -f $until) `
                -Detail 'Während der Pause werden auch Sicherheitsupdates zurückgehalten.' `
                -FixLabel 'Pause aufheben' `
                -Fix {
                param($d)
                $k = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
                foreach ($n in 'PauseUpdatesExpiryTime', 'PauseUpdatesStartTime', 'PauseQualityUpdatesStartTime', 'PauseQualityUpdatesEndTime', 'PauseFeatureUpdatesStartTime', 'PauseFeatureUpdatesEndTime') {
                    Remove-ItemProperty -Path $k -Name $n -ErrorAction SilentlyContinue
                }
                Restart-Service -Name UsoSvc -Force -ErrorAction SilentlyContinue
                Register-Change -Beschreibung 'Pause der Windows-Updates aufgehoben' -Typ 'Protokoll' -NichtUmkehrbar
                'Pause aufgehoben – Updates werden wieder gesucht.'
            }
        } else {
            Add-Finding $cat OK 'Windows-Updates sind nicht pausiert'
        }
    }

    Invoke-Check $cat 'Browser und Mailprogramme aktuell' {
        if ($null -eq $Script:SoftwareUpdateCache) { $Script:SoftwareUpdateCache = @(Get-SoftwareUpdates) }
        $old = @($Script:SoftwareUpdateCache | Where-Object { $_.Name -match 'Chrome|Firefox|Edge|Brave|Opera|Vivaldi|Thunderbird|Outlook' })
        if ($old) {
            Add-Finding $cat Kritisch "$($old.Count) Browser/Mailprogramm(e) veraltet" `
                -Detail 'Browser sind das häufigste Einfallstor für Angriffe – Updates sofort installieren.' `
                -Items ($old | ForEach-Object { '{0}  {1} → {2}' -f $_.Name, $_.Version, $_.Available }) `
                -FixLabel 'Browser-Updates installieren' -FixData $old -Fix { param($d) Install-SoftwareUpdates $d }
        } else {
            Add-Finding $cat OK 'Browser und Mailprogramme sind aktuell (soweit über WinGet erkennbar)'
        }
    }

    Add-ExtendedSecurityFindings -Category $cat
}
