<#
    Spiele- und Grafikleistung: Spielmodus, hardwarebeschleunigte GPU-Planung, Hintergrundaufzeichnung der Game Bar,
    Energiemodus und visuelle Effekte. Empfehlungen werden nur nach Auswahl gesetzt und sind umkehrbar.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:PowerOverlayNames = @{
    '961cc777-2547-4f9d-8174-7d86181b8a7a' = 'Beste Energieeffizienz'
    '3af9b8d9-7c97-431d-ad78-34a8bfea439f' = 'Ausbalanciert (bessere Leistung)'
    '00000000-0000-0000-0000-000000000000' = 'Ausbalanciert'
    'ded574b5-45a0-4f42-8737-46345c09c238' = 'Beste Leistung'
}

function Get-DedicatedGpu {
    @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '(?i)NVIDIA|GeForce|Quadro|Radeon (RX|Pro)|Intel\(R\) Arc' } | ForEach-Object { $_.Name })
}

function Get-GamingSettingsCatalog {
    param([switch]$WithGpu)
    $list = @(
        @{ Key = 'Spielmodus'; Label = 'Spielmodus einschalten (Windows bevorzugt das laufende Spiel, keine Update-Neustarts währenddessen)'
            Values = @(@{ Path = 'HKCU:\Software\Microsoft\GameBar'; Name = 'AutoGameModeEnabled'; Good = 1; Default = 1 }) }
        @{ Key = 'Hintergrundaufzeichnung'; Label = 'Hintergrundaufzeichnung der Game Bar ausschalten (zeichnet ständig die letzten Minuten auf und kostet Bilder pro Sekunde)'
            Values = @(@{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'; Name = 'HistoricalCaptureEnabled'; Good = 0; Default = 0 }) }
    )
    if ($WithGpu) {
        $list += @{ Key = 'GpuPlanung'; Label = 'Hardwarebeschleunigte GPU-Planung einschalten (geringere Verzögerung; Neustart nötig)'; Reboot = $true
            Values = @(@{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'; Name = 'HwSchMode'; Good = 2; Default = $null }) }
    }
    $list
}

function Get-PowerOverlay {
    $p = $null
    try { $p = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' -ErrorAction Stop } catch { return $null }
    $ac = "$($p.ActiveOverlayAcPowerScheme)".ToLower(); $dc = "$($p.ActiveOverlayDcPowerScheme)".ToLower()
    if (-not $ac -and -not $dc) { return $null }
    [pscustomobject]@{ AC = $ac; DC = $dc
        ACName = $(if ($Script:PowerOverlayNames[$ac]) { $Script:PowerOverlayNames[$ac] } elseif ($ac) { 'Eigener Modus' } else { 'Ausbalanciert' })
        DCName = $(if ($Script:PowerOverlayNames[$dc]) { $Script:PowerOverlayNames[$dc] } elseif ($dc) { 'Eigener Modus' } else { 'Ausbalanciert' }) }
}

function Set-GamingSettings {
    param($Settings)
    $values = @(); $names = @(); $reboot = $false
    foreach ($s in @($Settings)) {
        foreach ($v in $s.Values) { $values += @{ Path = $v.Path; Name = $v.Name; Value = $v.Good } }
        $names += $s.Key
        if ($s.Reboot) { $reboot = $true }
    }
    if (-not $values) { return 'Nichts ausgewählt.' }
    Set-RegistryValuesTracked -Values $values -Beschreibung "Spiele und Grafik: $($names -join ', ')"
    "$(@($Settings).Count) Einstellung(en) gesetzt. Rückgängig über »Änderungen«." + $(if ($reboot) { ' Die GPU-Planung wirkt nach einem Neustart.' } else { '' })
}

function Add-GamingFindings {
    param([string]$Category)
    $gpu = @(Get-DedicatedGpu)
    $catalog = @(Get-GamingSettingsCatalog -WithGpu:([bool]$gpu))
    $open = @($catalog | Where-Object { -not (Test-PrivacySetting $_) })
    $items = @($catalog | ForEach-Object { '{0}  {1}' -f $(if (Test-PrivacySetting $_) { '✔' } else { '–' }), $_.Label })
    if ($gpu) { $items = @("Grafikkarte: $($gpu -join ', ')") + $items }
    if ($open) {
        Add-Finding $Category Info "Spiele und Grafik: $($open.Count) Empfehlung(en)" -Items $items `
            -Detail 'Diese Windows-Einstellungen bringen in Spielen und grafiklastigen Programmen mehr Leistung bzw. weniger Ruckler. Gesetzt wird nur, was im nächsten Schritt ausgewählt ist; alles ist über »Änderungen« umkehrbar.' `
            -SelectLabels @($open | ForEach-Object { $_.Label }) -SelectAllByDefault -FixData $open -FixLabel 'Ausgewählte Spiele-Einstellungen setzen' -Fix {
            param($d, $pre)
            if (-not $pre) {
                $all = @($d); for ($i = 0; $i -lt $all.Count; $i++) { Write-Host ('    {0,3}) {1}' -f ($i + 1), $all[$i].Label) }
                $sel = Read-Host '   Setzen: [A] alle, Nummern oder leer = keine'
                $d = if ($sel -match '^\s*(a|alle)\s*$') { $all } else { @((Read-Selection $sel $all.Count) | ForEach-Object { $all[$_] }) }
            }
            Set-GamingSettings $d
        }
    } else {
        Add-Finding $Category OK 'Spiele- und Grafikeinstellungen sind optimal' -Items $items
    }

    # Energiemodus (Windows 10/11: »Energiemodus« bzw. Leistungsregler)
    $ov = Get-PowerOverlay
    if ($ov -and $ov.AC -eq '961cc777-2547-4f9d-8174-7d86181b8a7a') {
        Add-Finding $Category Info "Energiemodus am Netzteil: $($ov.ACName)" -Items @("Netzbetrieb: $($ov.ACName)", "Akkubetrieb: $($ov.DCName)") `
            -Detail 'Auch am Netzteil drosselt Windows Prozessor und Grafik zugunsten des Stromverbrauchs. Für Spiele und anspruchsvolle Programme »Ausbalanciert« oder »Beste Leistung« wählen.' `
            -FixLabel 'Energiemodus in den Einstellungen öffnen' -Fix { param($d) Start-Process 'ms-settings:powersleep'; 'Einstellungen geöffnet.' }
    }

    # Visuelle Effekte bei wenig Arbeitsspeicher
    $ram = [double]0
    try { $ram = [double](Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory } catch { }
    $fx = $null
    try { $fx = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name VisualFXSetting -ErrorAction Stop).VisualFXSetting } catch { }
    if ($ram -gt 0 -and $ram -le 8.5GB -and "$fx" -ne '2') {
        Add-Finding $Category Info 'Visuelle Effekte: bei wenig Arbeitsspeicher auf Leistung stellen' `
            -Detail "Mit $(Format-Bytes $ram) Arbeitsspeicher kosten Animationen, Schatten und Transparenz spürbar Leistung. Im Dialog »Für optimale Leistung anpassen« wählen und z. B. »Kanten der Bildschirmschriftarten verfeinern« wieder anhaken." `
            -FixLabel 'Leistungsoptionen öffnen' -Fix { param($d) Start-Process 'SystemPropertiesPerformance.exe'; 'Leistungsoptionen geöffnet.' }
    }
}
