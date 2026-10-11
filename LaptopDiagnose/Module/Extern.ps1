<#
    Externe Datenträger (USB-Sticks, externe Festplatten/SSDs, SD-Karten): prüfen, reparieren, Geschwindigkeits- und
    Echtheitstest, formatieren, sicher entfernen. Interne Laufwerke und das Systemlaufwerk werden nie angeboten –
    jede ändernde Aktion prüft das unmittelbar vorher erneut (Assert-ExternalDisk).
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:ExternalBusTypes = @('USB', 'SD', 'MMC', '1394')
$Script:CurrentFixOptions = $null
$Script:EchtBlocksPerFile = 1024   # 1-MB-Blöcke je Testdatei (1 GB – unter der FAT32-Grenze von 4 GB)

#region Erkennung

function Get-DriveRoot {
    param([string]$Letter)
    return "$($Letter):\"
}

function Get-PartitionLetter {
    param($Partition)
    $l = [string]$Partition.DriveLetter
    if ($l -match '^[A-Za-z]$') { return $l.ToUpperInvariant() }
    return ''
}

function Get-PageFileLetters {
    try { @(Get-CimInstance Win32_PageFileUsage -ErrorAction Stop | ForEach-Object { "$($_.Name)".Substring(0, 1).ToUpperInvariant() }) } catch { @() }
}

function Get-ExternalDisks {
    <#
        Externe Datenträger mit Partitionen und Volumes; mit -IncludeInternal zusätzlich interne Zusatzlaufwerke.
        Immer ausgeschlossen: Boot- und Systemdatenträger, der Datenträger mit Windows und Datenträger mit Auslagerungsdatei.
    #>
    param([switch]$IncludeInternal)
    $sys = "$env:SystemDrive".TrimEnd(':', '\').ToUpperInvariant()
    $pagefile = @(Get-PageFileLetters)
    $disks = @(Get-Disk -ErrorAction Stop | Where-Object {
            ("$($_.BusType)" -in $Script:ExternalBusTypes -or $IncludeInternal) -and -not $_.IsBoot -and -not $_.IsSystem })
    foreach ($d in $disks) {
        $parts = @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue)
        if ($parts | Where-Object { $l = Get-PartitionLetter $_; $l -and ($l -eq $sys -or $pagefile -contains $l) }) { continue }
        $vols = @(foreach ($p in $parts) {
                $v = $null
                try { $v = Get-Volume -Partition $p -ErrorAction Stop } catch { }
                [pscustomobject]@{
                    PartitionNumber = $p.PartitionNumber
                    Offset          = [double]$p.Offset
                    Letter          = Get-PartitionLetter $p
                    Size            = [double]$p.Size
                    Type            = "$($p.Type)"
                    IsHidden        = [bool]$p.IsHidden
                    FileSystem      = "$($v.FileSystem)"
                    Label           = "$($v.FileSystemLabel)"
                    Free            = [double]$v.SizeRemaining
                    VolSize         = [double]$v.Size
                    Health          = "$($v.HealthStatus)"
                }
            })
        [pscustomobject]@{
            Number     = [int]$d.Number
            Name       = ("$($d.FriendlyName)".Trim() -replace '\s+', ' ')
            Size       = [double]$d.Size
            Bus        = "$($d.BusType)"
            Style      = "$($d.PartitionStyle)"
            IsOffline  = [bool]$d.IsOffline
            IsReadOnly = [bool]$d.IsReadOnly
            Health     = "$($d.HealthStatus)"
            Status     = "$($d.OperationalStatus)"
            Partitions = $vols
            IsInternal = "$($d.BusType)" -notin $Script:ExternalBusTypes
            FreeExtent = [double]$d.LargestFreeExtent
            SectorSize = $(if ($d.LogicalSectorSize) { [int]$d.LogicalSectorSize } else { 512 })
        }
    }
}

function Assert-ExternalDisk {
    <# Sicherheitsnetz vor jeder Änderung: Der Datenträger muss (noch) ein externer, nicht-System-Datenträger sein. #>
    param([int]$Number, [string]$Letter, [switch]$AllowInternal)
    $d = @(Get-ExternalDisks -IncludeInternal:$AllowInternal) | Where-Object { $_.Number -eq $Number } | Select-Object -First 1
    if (-not $d) {
        $what = if ($AllowInternal) { 'ein bearbeitbarer Datenträger (Windows-, Boot- und Systemdatenträger sind gesperrt)' } else { 'ein externer Datenträger' }
        throw "Datenträger $Number ist nicht (mehr) $what – aus Sicherheitsgründen abgebrochen."
    }
    if ($Letter -and -not ($d.Partitions | Where-Object { $_.Letter -eq $Letter.TrimEnd(':').ToUpperInvariant() })) {
        throw "Laufwerk $($Letter): gehört nicht (mehr) zu diesem Datenträger – aus Sicherheitsgründen abgebrochen."
    }
    return $d
}

function Get-DataPartitions {
    <# Partitionen, die Daten enthalten können (ohne EFI, reservierte und Wiederherstellungspartitionen). #>
    param($Disk)
    @($Disk.Partitions | Where-Object { $_.Type -notmatch 'System|Reserved|Recovery|Unknown' -and $_.Size -ge 32MB })
}

function Get-VolumeContentSummary {
    param([string]$Letter)
    if (-not $Letter) { return '' }
    $names = @(Get-ChildItem -LiteralPath (Get-DriveRoot $Letter) -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notin 'System Volume Information', '$RECYCLE.BIN', 'desktop.ini', 'IndexerVolumeGuid' } | ForEach-Object { $_.Name })
    if (-not $names) { return 'leer' }
    $shown = ($names | Select-Object -First 5) -join ', '
    if ($names.Count -gt 5) { $shown += " … (+$($names.Count - 5))" }
    return "Inhalt: $shown"
}

function Get-ExternalTargets {
    <# Ziele für Werkzeuge: je Volume mit Laufwerksbuchstaben ein Eintrag, Datenträger ohne Buchstaben als Ganzes. #>
    param([switch]$WithLetterOnly, [switch]$IncludeContent)
    foreach ($d in @(Get-ExternalDisks)) {
        $lettered = @($d.Partitions | Where-Object { $_.Letter })
        foreach ($p in $lettered) {
            $fs = if ($p.FileSystem) { $p.FileSystem } else { 'RAW' }
            $label = '{0}: {1}{2} – {3}, {4}, {5} frei' -f $p.Letter, $d.Name, $(if ($p.Label) { " »$($p.Label)«" } else { '' }), (Format-Bytes $p.Size), $fs, (Format-Bytes $p.Free)
            if ($IncludeContent) { $label += " – $(Get-VolumeContentSummary $p.Letter)" }
            [pscustomobject]@{ Label = $label; Disk = $d.Number; Letter = $p.Letter; Size = [double]$p.Size; DiskSize = $d.Size; FileSystem = $p.FileSystem; Name = $d.Name; Token = $p.Letter }
        }
        if (-not $lettered -and -not $WithLetterOnly) {
            $label = 'Datenträger {0} (ohne Laufwerksbuchstaben): {1} – {2}' -f $d.Number, $d.Name, (Format-Bytes $d.Size)
            [pscustomobject]@{ Label = $label; Disk = $d.Number; Letter = ''; Size = $d.Size; DiskSize = $d.Size; FileSystem = ''; Name = $d.Name; Token = "$($d.Number)" }
        }
    }
}

function Test-CancelRequested {
    $s = Get-Variable -Name sync -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    return [bool]($s -and $s.Cancel)
}

function Set-Cancelable {
    param([bool]$On)
    $s = Get-Variable -Name sync -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($s) { $s.CanCancel = $On; if ($On) { $s.Cancel = $false } }
}

function Format-Duration {
    param([double]$Seconds)
    if ($Seconds -lt 90) { return "$([math]::Max(1, [math]::Round($Seconds))) Sek." }
    if ($Seconds -lt 5400) { return "$([math]::Round($Seconds / 60)) Min." }
    return '{0:N1} Std.' -f ($Seconds / 3600)
}

#endregion

#region Prüfen

function Get-DiskEventCounts {
    <# Fehler des Datenträgers aus dem System-Ereignisprotokoll (30 Tage). #>
    param([int]$Number, [string[]]$Letters)
    $res = @{ BadBlock = 0; Retry = 0; Removed = 0; FsError = 0 }
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'disk', 'Ntfs', 'Microsoft-Windows-Ntfs', 'exfat', 'fastfat'; StartTime = (Get-Date).AddDays(-30) } -ErrorAction SilentlyContinue)
    $diskPattern = "\\Device\\Harddisk$Number\\"
    foreach ($e in $ev) {
        $msg = "$($e.Message)"
        $mine = $msg.Contains($diskPattern) -or ($Letters | Where-Object { $msg -match "(?i)\b$($_):" })
        if (-not $mine) { continue }
        switch ($e.Id) {
            7 { $res.BadBlock++ }
            { $_ -in 51, 153 } { $res.Retry++ }
            157 { $res.Removed++ }
            { $_ -in 55, 98, 140, 50 } { $res.FsError++ }
        }
    }
    return $res
}

function Test-VolumeDirty {
    param([string]$Letter)
    $o = (& fsutil.exe dirty query "$($Letter):" 2>&1 | Out-String)
    if ($o -match '(?i)NOT Dirty|nicht fehlerhaft') { return $false }
    return [bool]($o -match '(?i)Dirty|fehlerhaft')
}

function Invoke-ExternalDriveScan {
    param([switch]$Tiefenpruefung)
    $cat = 'Extern'
    Clear-CategoryFindings $cat
    Write-Title 'Externe Datenträger'
    $disks = @()
    try { $disks = @(Get-ExternalDisks) } catch { Write-Host "     ✖ Datenträger konnten nicht gelesen werden: $($_.Exception.Message)" -ForegroundColor Red }
    Invoke-Check $cat 'Externe Datenträger: Übersicht' {
        if (-not $disks) {
            Add-Finding $cat OK 'Kein externer Datenträger angeschlossen' -Detail 'USB-Stick, externe Festplatte oder SD-Karte anstecken und »Datenträger prüfen« klicken. Partitionswerkzeuge und Klonen stehen für interne Zusatzlaufwerke trotzdem zur Verfügung.'
            return
        }
        foreach ($d in $disks) {
            $items = @("Anschluss: $($d.Bus)   Größe: $(Format-Bytes $d.Size)   Partitionsstil: $($d.Style)")
            foreach ($p in $d.Partitions) {
                $bl = ''
                if ($p.Letter -and (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
                    try {
                        $b = Get-BitLockerVolume -MountPoint "$($p.Letter):" -ErrorAction Stop
                        if ("$($b.LockStatus)" -eq 'Locked') { $bl = '  · BitLocker: gesperrt' }
                        elseif ("$($b.VolumeStatus)" -ne 'FullyDecrypted') { $bl = '  · BitLocker To Go: verschlüsselt' }
                    } catch { }
                }
                $lt = if ($p.Letter) { "$($p.Letter):" } else { '(ohne Buchstaben)' }
                $fs = if ($p.FileSystem) { $p.FileSystem } else { 'RAW / unbekannt' }
                $items += '{0,-18} {1,-8} {2,10}  frei {3,10}  {4}{5}' -f $lt, $fs, (Format-Bytes $p.Size), $(if ($p.VolSize) { Format-Bytes $p.Free } else { '–' }), $p.Label, $bl
            }
            $main = @($d.Partitions | Where-Object { $_.Letter } | Select-Object -First 1)
            $title = if ($main) { '{0} ({1}:) – {2}, {3}, {4} frei' -f $d.Name, $main[0].Letter, (Format-Bytes $d.Size), $(if ($main[0].FileSystem) { $main[0].FileSystem } else { 'RAW' }), (Format-Bytes $main[0].Free) }
            else { '{0} – {1}' -f $d.Name, (Format-Bytes $d.Size) }
            Add-Finding $cat OK $title -Items $items -Chart (Get-DiskBarChart $d) -ChartStyle Leiste
        }
    }
    Invoke-Check $cat 'Zusatzlaufwerke: Partitionen' { Add-PartitionOverviewFindings -Category $cat }
    if (-not $disks) {
        Invoke-Check $cat 'Partitionen und Klonen: Werkzeuge' { Add-PartitionToolFindings -Category $cat; Add-CloneToolFindings -Category $cat; Add-RecoveryToolFindings -Category $cat }
        return
    }

    Invoke-Check $cat 'Externe Datenträger: Zustand' {
        foreach ($d in $disks) {
            $letters = @($d.Partitions | Where-Object { $_.Letter } | ForEach-Object { $_.Letter })
            $pd = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { "$($_.DeviceId)" -eq "$($d.Number)" } | Select-Object -First 1
            $rel = $null
            if ($pd) { try { $rel = $pd | Get-StorageReliabilityCounter -ErrorAction Stop } catch { } }
            $ev = Get-DiskEventCounts -Number $d.Number -Letters $letters
            $items = @()
            if ($pd) { $items += "Zustand laut Windows: $($pd.HealthStatus)" }
            if ($rel) {
                if ($null -ne $rel.ReadErrorsUncorrected) { $items += "Nicht korrigierbare Lesefehler: $($rel.ReadErrorsUncorrected)" }
                if ($null -ne $rel.WriteErrorsUncorrected) { $items += "Nicht korrigierbare Schreibfehler: $($rel.WriteErrorsUncorrected)" }
                if ($rel.Temperature) { $items += "Temperatur: $($rel.Temperature) °C" }
                if ($null -ne $rel.Wear) { $items += "Abnutzung: $($rel.Wear) %" }
            } else { $items += 'Gesundheitswerte (SMART): vom Gerät bzw. USB-Gehäuse nicht übermittelt' }
            $items += "Ereignisprotokoll (30 Tage): $($ev.BadBlock) defekte Blöcke, $($ev.Retry) wiederholte Zugriffe, $($ev.FsError) Dateisystemfehler, $($ev.Removed)× unerwartet entfernt"
            $uncorr = [int]$rel.ReadErrorsUncorrected + [int]$rel.WriteErrorsUncorrected
            if ("$($pd.HealthStatus)" -eq 'Unhealthy' -or $ev.BadBlock -gt 0 -or $uncorr -gt 0) {
                Add-Finding $cat Kritisch "$($d.Name): Datenträger meldet Lese-/Schreibfehler" -Items $items `
                    -Detail 'Defekte Blöcke bzw. nicht korrigierbare Fehler sind ein Zeichen für einen beginnenden Ausfall. Wichtige Daten jetzt auf einen anderen Datenträger kopieren und den Datenträger danach nicht mehr für wichtige Daten verwenden.'
            } elseif ("$($pd.HealthStatus)" -eq 'Warning' -or $ev.Retry -ge 3 -or $ev.FsError -gt 0) {
                Add-Finding $cat Warnung "$($d.Name): wiederholte Zugriffsprobleme" -Items $items `
                    -Detail 'Häufige Wiederholungen oder Dateisystemfehler entstehen durch Wackelkontakte, schwache USB-Stromversorgung (Hub ohne Netzteil) oder Abziehen ohne »Sicher entfernen«. Anderes Kabel bzw. anderen Anschluss probieren und das Dateisystem prüfen.'
            } elseif ($ev.Removed -ge 3) {
                Add-Finding $cat Info "$($d.Name): $($ev.Removed)× ohne »Sicher entfernen« abgezogen" -Items $items `
                    -Detail 'Wird ein Datenträger während eines Schreibvorgangs abgezogen, können Dateien und das Dateisystem beschädigt werden. Vor dem Abziehen »Sicher entfernen« verwenden.'
            } else {
                Add-Finding $cat OK "$($d.Name): keine Fehler bekannt" -Items $items
            }
        }
    }

    Invoke-Check $cat 'Externe Datenträger: Dateisystem' {
        foreach ($d in $disks) {
            foreach ($p in @($d.Partitions | Where-Object { $_.Letter -and $_.FileSystem -match '^(NTFS|FAT32|FAT|exFAT|ReFS)$' })) {
                $dirty = Test-VolumeDirty $p.Letter
                $errors = $false; $note = ''
                if ($Tiefenpruefung -and -not $dirty) {
                    Write-Host "     Dateisystem von $($p.Letter): wird geprüft (nur lesen) …" -ForegroundColor Gray
                    $null = & chkdsk.exe "$($p.Letter):" 2>&1
                    if ($LASTEXITCODE -ne 0) { $errors = $true }
                    $note = ' (vollständig geprüft)'
                }
                if ($dirty -or $errors) {
                    $why = if ($dirty) { 'Windows hat das Laufwerk als fehlerhaft markiert – meist nach dem Abziehen ohne »Sicher entfernen«.' } else { 'Die Prüfung hat Fehler im Dateisystem gefunden.' }
                    Add-Finding $cat Warnung "Dateisystemfehler auf $($p.Letter): ($($d.Name))" `
                        -Detail "$why Die Reparatur trennt das Laufwerk kurz – vorher alle Dateien und Fenster auf dem Laufwerk schließen. Bei wichtigen Daten zuerst eine Kopie anlegen." `
                        -FixLabel "Dateisystem von $($p.Letter): reparieren" -FixData @{ Disk = $d.Number; Letter = $p.Letter } -Fix { param($x) Repair-ExternalVolume -Disk $x.Disk -Letter $x.Letter }
                } else {
                    Add-Finding $cat OK "Dateisystem von $($p.Letter): in Ordnung$note"
                }
            }
        }
        if (-not $Tiefenpruefung) { Write-Host '     (Vollständige Dateisystemprüfung: im Bereich »Externe Datenträger« auf »Datenträger prüfen« klicken)' -ForegroundColor DarkGray }
    }

    Invoke-Check $cat 'Externe Datenträger: Probleme' { Add-ExternalProblemFindings -Category $cat -Disks $disks }
    Invoke-Check $cat 'Externe Datenträger: Werkzeuge' { Add-ExternalToolFindings -Category $cat }
    Invoke-Check $cat 'Partitionen und Klonen: Werkzeuge' { Add-PartitionToolFindings -Category $cat; Add-CloneToolFindings -Category $cat; Add-RecoveryToolFindings -Category $cat }
}

function Invoke-ExternalDriveScanDetailed { Invoke-ExternalDriveScan -Tiefenpruefung }

function Add-ExternalProblemFindings {
    param([string]$Category, $Disks)
    # Schreibschutz per Windows-Einstellung (gilt für alle USB-Datenträger)
    $policy = $null
    try { $policy = (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies' -Name WriteProtect -ErrorAction Stop).WriteProtect } catch { }
    if ("$policy" -eq '1') {
        Add-Finding $Category Warnung 'Windows-Einstellung sperrt das Schreiben auf USB-Datenträger' `
            -Detail 'Der Registry-Wert »StorageDevicePolicies\WriteProtect« macht alle USB-Datenträger schreibgeschützt. Aufheben ist über »Änderungen« umkehrbar; danach den Datenträger einmal abziehen und neu anstecken.' `
            -FixLabel 'Schreibschutz-Einstellung aufheben' -Fix {
            param($x)
            Set-RegistryValuesTracked -Values @(@{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\StorageDevicePolicies'; Name = 'WriteProtect'; Value = 0 }) -Beschreibung 'USB-Schreibschutz (StorageDevicePolicies) aufgehoben'
            'Schreibschutz-Einstellung aufgehoben. Datenträger abziehen und neu anstecken.'
        }
    }
    $denyKey = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices'
    if (Test-Path $denyKey) {
        $deny = @(Get-ChildItem $denyKey -ErrorAction SilentlyContinue | ForEach-Object { Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue } | Where-Object { $_.Deny_Write -eq 1 -or $_.Deny_All -eq 1 -or $_.Deny_Read -eq 1 })
        if ($deny -or (Get-ItemProperty $denyKey -ErrorAction SilentlyContinue).Deny_All -eq 1) {
            Add-Finding $Category Info 'Gruppenrichtlinie beschränkt Wechseldatenträger' -Detail 'Eine Richtlinie (z. B. vom Arbeitgeber) verbietet das Lesen oder Schreiben auf Wechseldatenträgern. Das Tool ändert Richtlinien bewusst nicht – bei Firmengeräten die IT fragen.'
        }
    }

    foreach ($d in $Disks) {
        $fixData = @{ Disk = $d.Number }
        if ($d.IsOffline) {
            Add-Finding $Category Warnung "$($d.Name) ist offline" -Detail 'Windows hat den Datenträger offline geschaltet (z. B. wegen einer Signaturkollision mit einem anderen Datenträger). Er wird dann im Explorer nicht angezeigt.' `
                -FixLabel "$($d.Name) online schalten" -FixData $fixData -Fix {
                param($x)
                $null = Assert-ExternalDisk -Number $x.Disk
                Set-Disk -Number $x.Disk -IsOffline $false -ErrorAction Stop
                'Datenträger ist wieder online.'
            }
        }
        if ($d.IsReadOnly) {
            Add-Finding $Category Warnung "$($d.Name) ist schreibgeschützt" `
                -Detail 'Dateien lassen sich lesen, aber nicht speichern oder löschen. Ursache ist entweder ein Windows-Attribut (lässt sich aufheben) oder ein Schiebeschalter am Stick, an der SD-Karte bzw. am Adapter (Schalter auf »Unlock« stellen). Manche Sticks schalten sich bei einem Defekt dauerhaft schreibgeschützt.' `
                -FixLabel "Schreibschutz von $($d.Name) aufheben" -FixData $fixData -Fix {
                param($x)
                $null = Assert-ExternalDisk -Number $x.Disk
                try { Set-Disk -Number $x.Disk -IsReadOnly $false -ErrorAction Stop } catch { }
                $now = Get-Disk -Number $x.Disk -ErrorAction SilentlyContinue
                if ($now.IsReadOnly) { throw 'Der Schreibschutz bleibt bestehen – vermutlich ein Schiebeschalter am Datenträger bzw. Adapter oder der Speicher ist defekt (dann schaltet er sich dauerhaft schreibgeschützt).' }
                'Schreibschutz aufgehoben.'
            }
        }
        if ($d.Style -eq 'RAW') {
            Add-Finding $Category Warnung "$($d.Name) ist nicht eingerichtet" `
                -Detail 'Der Datenträger hat keine Partitionstabelle (neu, gelöscht oder beschädigt). Enthielt er wichtige Daten, zuerst ein Datenrettungsprogramm verwenden (z. B. das kostenlose TestDisk/PhotoRec). Sonst mit dem Werkzeug »Datenträger formatieren« und der Option »komplett neu einrichten« nutzbar machen.'
            continue
        }
        foreach ($p in @(Get-DataPartitions $d)) {
            $where = if ($p.Letter) { "$($p.Letter):" } else { "Partition $($p.PartitionNumber)" }
            if (-not $p.FileSystem -or $p.FileSystem -eq 'RAW') {
                Add-Finding $Category Kritisch "$where auf $($d.Name) ist nicht lesbar (Dateisystem »RAW«)" `
                    -Detail 'Windows erkennt das Dateisystem nicht und bietet an, das Laufwerk zu formatieren – NICHT formatieren, wenn die Daten gebraucht werden. Zuerst mit einem Datenrettungsprogramm (z. B. TestDisk/PhotoRec, kostenlos) auf einen anderen Datenträger retten. Sind die Daten nicht wichtig: Werkzeug »Datenträger formatieren«.'
                continue
            }
            if (-not $p.Letter -and -not $p.IsHidden) {
                Add-Finding $Category Warnung "Partition $($p.PartitionNumber) auf $($d.Name) hat keinen Laufwerksbuchstaben" `
                    -Detail 'Ohne Laufwerksbuchstaben erscheint das Laufwerk nicht im Explorer, obwohl es in Ordnung ist.' `
                    -FixLabel "Laufwerksbuchstaben für $($d.Name) zuweisen" -FixData @{ Disk = $d.Number; Partition = $p.PartitionNumber } -Fix {
                    param($x)
                    $null = Assert-ExternalDisk -Number $x.Disk
                    Add-PartitionAccessPath -DiskNumber $x.Disk -PartitionNumber $x.Partition -AssignDriveLetter -ErrorAction Stop
                    $l = Get-PartitionLetter (Get-Partition -DiskNumber $x.Disk -PartitionNumber $x.Partition)
                    "Laufwerksbuchstabe $($l): zugewiesen."
                }
            }
            if ($p.FileSystem -eq 'FAT32') {
                Add-Finding $Category Info "$where ($($d.Name)) nutzt FAT32 – keine Dateien über 4 GB" `
                    -Detail 'FAT32 kann keine Dateien speichern, die größer als 4 GB sind (z. B. lange Videos, ISO-Dateien). Für den Austausch mit Mac, Fernseher und Kamera ist exFAT besser, für reine Windows-Nutzung NTFS. Umstellen geht nur durch Formatieren – vorher die Daten sichern. Ältere Autoradios und Geräte brauchen allerdings FAT32.'
            }
        }
        $used = [double](($d.Partitions | Measure-Object Size -Sum).Sum)
        $unalloc = $d.Size - $used
        if ($d.Size -gt 0 -and $unalloc -gt [math]::Max([double]1GB, 0.1 * $d.Size)) {
            Add-Finding $Category Info "$($d.Name): $(Format-Bytes $unalloc) nicht nutzbar eingerichtet" `
                -Detail "Von $(Format-Bytes $d.Size) sind nur $(Format-Bytes $used) als Laufwerk eingerichtet – typisch nach dem Beschreiben mit einem Abbild (z. B. Linux- oder Windows-Installationsstick). Mit dem Werkzeug »Datenträger formatieren« und »komplett neu einrichten« wird wieder die volle Größe nutzbar (löscht alle Daten)."
        }
    }
}

#endregion

#region Reparieren

function Repair-ExternalVolume {
    param([int]$Disk, [string]$Letter)
    $null = Assert-ExternalDisk -Number $Disk -Letter $Letter
    Write-Host "     › Dateisystem von $($Letter): wird repariert (Laufwerk wird kurz getrennt) …" -ForegroundColor Gray
    # Antworten für mögliche Rückfragen (z. B. verlorene Ketten in Dateien umwandeln) – deutsch »J«, englisch »Y«
    $out = @('J', 'Y', 'J', 'Y') | & chkdsk.exe "$($Letter):" /f /x 2>&1
    $code = $LASTEXITCODE
    $tail = (@($out) | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Select-Object -Last 3) -join ' '
    switch ($code) {
        0 { "Keine Fehler gefunden bzw. Dateisystem von $($Letter): ist in Ordnung." }
        1 { "Fehler im Dateisystem von $($Letter): wurden behoben. Prüfen, ob alle Dateien vorhanden sind (gerettete Teile liegen ggf. im Ordner FOUND.000)." }
        default { throw "Reparatur nicht vollständig möglich (Code $code): $tail" }
    }
}

function Dismount-ExternalDrive {
    <# »Sicher entfernen«: Zwischenspeicher schreiben und über die Windows-Shell auswerfen. #>
    param([string]$Letter, [int]$Disk)
    $null = Assert-ExternalDisk -Number $Disk -Letter $Letter
    try { Write-VolumeCache -DriveLetter $Letter -ErrorAction Stop } catch { }
    $ejected = $false
    try {
        $shell = New-Object -ComObject Shell.Application
        $item = $shell.Namespace(17).ParseName("$($Letter):\")
        if ($item) {
            $verb = @($item.Verbs()) | Where-Object { ($_.Name -replace '&', '') -match '^(Auswerfen|Eject)$' } | Select-Object -First 1
            if ($verb) { $verb.DoIt() } else { $item.InvokeVerb('Eject') }
        }
    } catch { }
    for ($i = 0; $i -lt 16; $i++) {
        Start-Sleep -Milliseconds 500
        if (-not (Test-Path -LiteralPath (Get-DriveRoot $Letter))) { $ejected = $true; break }
    }
    if ($ejected) { return "$($Letter): kann jetzt abgezogen werden." }
    Start-Process -FilePath "$env:windir\System32\rundll32.exe" -ArgumentList 'shell32.dll,Control_RunDLL hotplug.dll'
    throw "$($Letter): wird noch verwendet (geöffnete Datei, Explorer-Fenster oder Programm). Diese schließen und erneut versuchen – das Fenster »Hardware sicher entfernen« wurde geöffnet."
}

#endregion

#region Geschwindigkeitstest

function Invoke-WinSatDisk {
    param([string]$Letter, [string[]]$Arguments)
    $out = (& winsat.exe disk -drive $Letter.ToLowerInvariant() @Arguments 2>&1 | Out-String)
    $m = [regex]::Matches($out, '(\d+(?:[.,]\d+)?)\s*MB/s')
    if ($m.Count) { return [double]($m[$m.Count - 1].Groups[1].Value -replace ',', '.') }
    return $null
}

function Measure-OwnSequential {
    <# Ersatzmessung ohne WinSAT: große Datei mit Durchschreiben schreiben und lesen (Lesewert kann durch Zwischenspeicher zu hoch sein). #>
    param([string]$Letter, [double]$Bytes)
    $path = Join-Path (Get-DriveRoot $Letter) 'PCRepairPro-Tempotest.tmp'
    $buf = New-Object byte[] (4MB)
    (New-Object Random).NextBytes($buf)
    $blocks = [math]::Max(4, [int]($Bytes / 4MB))
    try {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $fs = New-Object IO.FileStream($path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None, 4MB, [IO.FileOptions]::WriteThrough)
        try { for ($i = 0; $i -lt $blocks; $i++) { if (Test-CancelRequested) { throw 'Abgebrochen.' }; $fs.Write($buf, 0, $buf.Length) }; $fs.Flush($true) } finally { $fs.Dispose() }
        $w = $blocks * 4 / $sw.Elapsed.TotalSeconds
        $sw.Restart()
        $fs = New-Object IO.FileStream($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None, 4MB, [IO.FileOptions]::SequentialScan)
        try { while ($fs.Read($buf, 0, $buf.Length) -gt 0) { } } finally { $fs.Dispose() }
        $r = $blocks * 4 / $sw.Elapsed.TotalSeconds
        return [pscustomobject]@{ Write = [math]::Round($w, 1); Read = [math]::Round($r, 1) }
    } finally { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}

function Get-SpeedAssessment {
    param([double]$SeqRead, [double]$SeqWrite, $RanWrite, [string]$Bus)
    $lines = @()
    if ($SeqRead -gt 0 -and $SeqRead -lt 40 -and $Bus -eq 'USB') {
        $lines += 'Lesen unter 40 MB/s ist typisch für USB 2.0 oder einen einfachen Stick. Kann der Datenträger USB 3 (blauer Stecker), an einen USB-3-Anschluss (blau bzw. »SS«) direkt am Gerät statt an einen Hub stecken.'
    } elseif ($SeqRead -ge 400) { $lines += 'Sehr schnell – typisch für eine externe SSD an USB 3.1/3.2.' }
    elseif ($SeqRead -ge 100) { $lines += 'Gut – typisch für schnelle USB-3-Sticks, externe Festplatten oder SSDs.' }
    elseif ($SeqRead -ge 40) { $lines += 'Ordentlich – typisch für USB-3-Sticks der Einstiegsklasse.' }
    if ($SeqWrite -gt 0 -and $SeqWrite -lt 10) { $lines += 'Schreiben ist sehr langsam (unter 10 MB/s): Große Dateien zu kopieren dauert lange. Für Sicherungen besser eine externe Festplatte oder SSD verwenden.' }
    if ($null -ne $RanWrite -and $RanWrite -lt 1) { $lines += 'Kleine Dateien werden sehr langsam geschrieben (4K unter 1 MB/s) – ungeeignet für Programme, portable Apps oder viele kleine Dateien; als Dateiablage in Ordnung.' }
    if (-not $lines) { $lines += 'Keine Auffälligkeiten.' }
    return $lines
}

function Test-DriveSpeed {
    <# Ausführlicher Geschwindigkeitstest: sequenziell und 4K-zufällig, lesen und schreiben, mit mehreren Durchgängen. #>
    param($Target)
    $null = Assert-ExternalDisk -Number $Target.Disk -Letter $Target.Letter
    $L = $Target.Letter
    $vol = Get-Volume -DriveLetter $L -ErrorAction Stop
    if ([double]$vol.SizeRemaining -lt 300MB) { throw "Zu wenig freier Platz auf $($L): (mindestens 300 MB nötig)." }
    Set-Cancelable $true
    try {
        $tests = @(
            @{ Name = 'Sequenziell lesen'; Args = @('-seq', '-read', '-count', '3') }
            @{ Name = 'Sequenziell schreiben'; Args = @('-seq', '-write', '-count', '3') }
            @{ Name = '4K zufällig lesen'; Args = @('-ran', '-read', '-ransize', '4096', '-count', '3') }
            @{ Name = '4K zufällig schreiben'; Args = @('-ran', '-write', '-ransize', '4096', '-count', '3') }
        )
        $res = [ordered]@{}
        $i = 0
        foreach ($t in $tests) {
            if (Test-CancelRequested) { throw 'Abgebrochen.' }
            $i++
            Write-Host "     › Geschwindigkeitstest $($L): $($t.Name) ($i/4, je 3 Durchgänge) …" -ForegroundColor Gray
            $res[$t.Name] = if (Get-Command winsat.exe -ErrorAction SilentlyContinue) { Invoke-WinSatDisk $L $t.Args } else { $null }
        }
        $note = ''
        if ($null -eq $res['Sequenziell lesen'] -or $null -eq $res['Sequenziell schreiben']) {
            Write-Host "     › Ersatzmessung mit großer Testdatei …" -ForegroundColor Gray
            $size = [math]::Min([double]1GB, [double]$vol.SizeRemaining * 0.25)
            $own = Measure-OwnSequential -Letter $L -Bytes $size
            if ($null -eq $res['Sequenziell lesen']) { $res['Sequenziell lesen'] = $own.Read; $note = ' Lesewert aus eigener Messung (kann durch den Zwischenspeicher zu hoch ausfallen).' }
            if ($null -eq $res['Sequenziell schreiben']) { $res['Sequenziell schreiben'] = $own.Write }
        }
    } finally { Set-Cancelable $false }

    $chart = @($res.Keys | Where-Object { $null -ne $res[$_] } | ForEach-Object { [pscustomobject]@{ Label = $_; Value = [double]$res[$_]; Text = ('{0:N1} MB/s' -f $res[$_]) } })
    $assess = @(Get-SpeedAssessment -SeqRead ([double]$res['Sequenziell lesen']) -SeqWrite ([double]$res['Sequenziell schreiben']) -RanWrite $res['4K zufällig schreiben'] -Bus ((Get-ExternalDisks | Where-Object { $_.Number -eq $Target.Disk }).Bus))
    $items = @($res.Keys | ForEach-Object { '{0,-24} {1}' -f $_, $(if ($null -ne $res[$_]) { '{0:N1} MB/s' -f $res[$_] } else { 'nicht messbar' }) })
    $copy = if ($res['Sequenziell schreiben'] -gt 0) { ' Eine 4-GB-Datei zu kopieren dauert etwa ' + (Format-Duration (4096 / $res['Sequenziell schreiben'])) + '.' } else { '' }
    $sev = if ($assess -match 'USB 2.0|sehr langsam') { 'Info' } else { 'OK' }
    Remove-FindingByKey "Tempo|$L"
    Add-Finding 'Extern' $sev ("Geschwindigkeit {0}: ({1}): lesen {2:N0} MB/s, schreiben {3:N0} MB/s" -f $L, $Target.Name, $res['Sequenziell lesen'], $res['Sequenziell schreiben']) `
        -Key "Tempo|$L" -Chart $chart -Items $items -Detail (($assess -join ' ') + $copy + $note + ' Gemessen mit dem Windows-Leistungstest (WinSAT), je 3 Durchgänge; Testdateien wurden wieder gelöscht.')
    "Lesen $('{0:N1}' -f $res['Sequenziell lesen']) MB/s, Schreiben $('{0:N1}' -f $res['Sequenziell schreiben']) MB/s – siehe Karte »Geschwindigkeit $($L):«."
}

#endregion

#region Echtheitstest

function Set-BlockStamp {
    <# Kennzeichnet einen 1-MB-Block mit seiner laufenden Nummer und dem Prüfschlüssel (Anfang, Mitte, Ende). #>
    param([byte[]]$Buffer, [long]$Index, [long]$Seed)
    $stamp = [BitConverter]::GetBytes($Index -bxor $Seed)
    $idx = [BitConverter]::GetBytes($Index)
    foreach ($off in 0, 524288, 1048560) {
        [Buffer]::BlockCopy($idx, 0, $Buffer, $off, 8)
        [Buffer]::BlockCopy($stamp, 0, $Buffer, $off + 8, 8)
    }
}

function Test-BlockStamp {
    param([byte[]]$Buffer, [long]$Index, [long]$Seed)
    foreach ($off in 0, 524288, 1048560) {
        if ([BitConverter]::ToInt64($Buffer, $off) -ne $Index) { return $false }
        if ([BitConverter]::ToInt64($Buffer, $off + 8) -ne ($Index -bxor $Seed)) { return $false }
    }
    return $true
}

function Clear-BlockStamp {
    param([byte[]]$Buffer)
    foreach ($off in 0, 524288, 1048560) { [Array]::Clear($Buffer, $off, 16) }
}

function Test-DriveAuthenticity {
    <#
        Echtheitstest wie H2testw: freien Platz mit gekennzeichneten Testdaten füllen, Laufwerk aushängen (leert den
        Zwischenspeicher) und alles zurücklesen. Gefälschte Sticks überschreiben ab ihrer echten Größe ältere Daten
        oder verwerfen sie – das fällt beim Vergleich auf. Vorhandene Dateien bleiben unberührt.
    #>
    param($Target)
    $null = Assert-ExternalDisk -Number $Target.Disk -Letter $Target.Letter
    $L = $Target.Letter
    $vol = Get-Volume -DriveLetter $L -ErrorAction Stop
    $usedBefore = [double]$vol.Size - [double]$vol.SizeRemaining
    $total = [long](([double]$vol.SizeRemaining - 32MB) / 1MB)
    if ($total -lt 16) { throw "Zu wenig freier Platz auf $($L): für den Echtheitstest." }
    $dir = Join-Path (Get-DriveRoot $L) 'PCRepairPro-Echtheitstest'
    $perFile = [long]$Script:EchtBlocksPerFile
    $seed = [long](Get-Random -Minimum 1 -Maximum 2147483647) * 2654435761L
    $base = New-Object byte[] (1MB)
    (New-Object Random([int]($seed % 2147483647))).NextBytes($base)
    $md5 = [Security.Cryptography.MD5]::Create()
    $ref = [byte[]]$base.Clone(); Clear-BlockStamp $ref
    $baseHash = [Convert]::ToBase64String($md5.ComputeHash($ref))
    $buf = New-Object byte[] (1MB)
    $written = 0L; $writeError = $null; $bad = 0L; $firstBad = -1L; $checked = 0L; $canceled = $false
    $sw = [Diagnostics.Stopwatch]::StartNew()
    Set-Cancelable $true
    try {
        $null = New-Item -ItemType Directory -Path $dir -Force
        # Phase 1: schreiben
        $lastReport = [datetime]::MinValue
        $files = [math]::Ceiling($total / $perFile)
        for ($f = 0; $f -lt $files -and -not $writeError; $f++) {
            $path = Join-Path $dir ('{0:D5}.h2w' -f ($f + 1))
            $fs = New-Object IO.FileStream($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None, 1MB, [IO.FileOptions]::WriteThrough)
            try {
                for ($b = 0; $b -lt $perFile -and $written -lt $total; $b++) {
                    if (Test-CancelRequested) { $canceled = $true; throw 'Abgebrochen.' }
                    [Buffer]::BlockCopy($base, 0, $buf, 0, $buf.Length)
                    Set-BlockStamp $buf $written $seed
                    try { $fs.Write($buf, 0, $buf.Length) } catch { $writeError = $_.Exception.Message; break }
                    $written++
                    if (([datetime]::UtcNow - $lastReport).TotalSeconds -ge 15) {
                        $lastReport = [datetime]::UtcNow
                        $rate = $written / [math]::Max(0.1, $sw.Elapsed.TotalSeconds)
                        $rest = ($total - $written) / [math]::Max(0.01, $rate) + $total / [math]::Max(0.01, $rate * 2)
                        Write-Host ("     › Echtheitstest {0}: schreiben {1} % ({2:N1} MB/s) – noch ca. {3}" -f $L, [math]::Floor(100 * $written / $total), $rate, (Format-Duration $rest)) -ForegroundColor Gray
                    }
                }
                try { $fs.Flush($true) } catch { if (-not $writeError) { $writeError = $_.Exception.Message } }
            } finally { $fs.Dispose() }
        }
        $writeSeconds = $sw.Elapsed.TotalSeconds
        # Zwischenspeicher verwerfen: Laufwerk aushängen (wird beim nächsten Zugriff automatisch wieder eingehängt)
        $cacheNote = ''
        $null = & fsutil.exe volume dismount "$($L):" 2>&1
        if ($LASTEXITCODE -ne 0) { $cacheNote = ' Hinweis: Das Laufwerk ließ sich zwischendurch nicht aushängen – bei Datenträgern, die kleiner als der Arbeitsspeicher sind, kann ein Teil aus dem Zwischenspeicher gelesen worden sein. Für ein sicheres Ergebnis vor dem Test alle Fenster auf dem Laufwerk schließen.' }
        Start-Sleep -Seconds 2
        # Phase 2: lesen und vergleichen
        $sw.Restart(); $lastReport = [datetime]::MinValue
        foreach ($file in @(Get-ChildItem -LiteralPath $dir -Filter '*.h2w' | Sort-Object Name)) {
            # Jede Datei beginnt bei einer festen Blocknummer – ein Lesefehler verschiebt so nicht die Prüfung der folgenden Dateien
            $idx = ([long]$file.BaseName - 1) * $perFile
            $end = [math]::Min($written, $idx + $perFile)
            $fs = New-Object IO.FileStream($file.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None, 1MB, [IO.FileOptions]::SequentialScan)
            try {
                while ($idx -lt $end) {
                    if (Test-CancelRequested) { $canceled = $true; throw 'Abgebrochen.' }
                    $n = 0
                    try { while ($n -lt $buf.Length) { $r = $fs.Read($buf, $n, $buf.Length - $n); if ($r -le 0) { break }; $n += $r } } catch { $n = -1 }
                    if ($n -eq 0) { break }
                    $ok = ($n -eq $buf.Length) -and (Test-BlockStamp $buf $idx $seed)
                    if ($ok) { Clear-BlockStamp $buf; $ok = ([Convert]::ToBase64String($md5.ComputeHash($buf)) -eq $baseHash) }
                    if (-not $ok) { $bad++; if ($firstBad -lt 0) { $firstBad = $idx } }
                    $idx++; $checked++
                    if ($n -lt 0) { break }
                    if (([datetime]::UtcNow - $lastReport).TotalSeconds -ge 15) {
                        $lastReport = [datetime]::UtcNow
                        $rate = $checked / [math]::Max(0.1, $sw.Elapsed.TotalSeconds)
                        Write-Host ("     › Echtheitstest {0}: prüfen {1} % ({2:N1} MB/s) – noch ca. {3}" -f $L, [math]::Floor(100 * $checked / [math]::Max(1, $written)), $rate, (Format-Duration (($written - $checked) / [math]::Max(0.01, $rate)))) -ForegroundColor Gray
                    }
                }
            } finally { $fs.Dispose() }
        }
        # Blöcke, die gar nicht mehr lesbar waren (Datei kürzer), zählen ebenfalls als fehlerhaft
        if ($checked -lt $written) { $bad += ($written - $checked); if ($firstBad -lt 0) { $firstBad = $checked } }
        $readSeconds = $sw.Elapsed.TotalSeconds
    } catch {
        if (-not $canceled) { throw }
    } finally {
        Set-Cancelable $false
        $md5.Dispose()
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Remove-FindingByKey "Echt|$L"
    if ($canceled) {
        Add-Finding 'Extern' Info "Echtheitstest $($L): abgebrochen" -Key "Echt|$L" -Detail "Abgebrochen nach $(Format-Bytes ($written * 1MB)) geschriebenen und $(Format-Bytes ($checked * 1MB)) geprüften Testdaten. Die Testdateien wurden gelöscht."
        return 'Echtheitstest abgebrochen – Testdateien gelöscht.'
    }
    $items = @(
        "Bereits belegt (nicht getestet): $(Format-Bytes $usedBefore)"
        "Testdaten geschrieben: $(Format-Bytes ($written * 1MB)) in $(Format-Duration $writeSeconds) ($('{0:N1}' -f ($written / [math]::Max(0.1, $writeSeconds))) MB/s)"
        "Testdaten geprüft: $(Format-Bytes ($checked * 1MB)) in $(Format-Duration $readSeconds) ($('{0:N1}' -f ($checked / [math]::Max(0.1, $readSeconds))) MB/s)"
        "Fehlerhafte Daten: $(Format-Bytes ($bad * 1MB))"
    )
    if ($writeError) { $items += "Schreibfehler: $writeError" }
    if ($bad -gt 0) {
        $real = $usedBefore + $firstBad * 1MB
        Add-Finding 'Extern' Kritisch ("Echtheitstest {0}: Fehler ab {1} – gefälschte Kapazität oder defekter Speicher" -f $L, (Format-Bytes $real)) -Key "Echt|$L" -Items $items `
            -Detail "Ab etwa $(Format-Bytes $real) stimmen die gelesenen Daten nicht mit den geschriebenen überein. Bei einem neuen, billigen Datenträger ist das fast immer eine Fälschung: Die angezeigte Größe ($(Format-Bytes $Target.Size)) ist vorgetäuscht, echt nutzbar sind nur etwa $(Format-Bytes $real). Dateien jenseits dieser Grenze gehen verloren. Den Datenträger reklamieren bzw. nicht für wichtige Daten verwenden.$cacheNote"
        return "Fehler ab ca. $(Format-Bytes $real) – Datenträger ist gefälscht oder defekt."
    }
    if ($writeError -and $written -lt $total * 0.95) {
        Add-Finding 'Extern' Warnung "Echtheitstest $($L): Schreiben vorzeitig abgebrochen" -Key "Echt|$L" -Items $items -Detail "Nach $(Format-Bytes ($written * 1MB)) trat ein Schreibfehler auf. Das kann auf einen Defekt hindeuten; die geschriebenen Daten waren fehlerfrei.$cacheNote"
        return 'Schreibfehler während des Tests – siehe Karte.'
    }
    Add-Finding 'Extern' OK ("Echtheitstest {0}: bestanden – {1} fehlerfrei geschrieben und gelesen" -f $L, (Format-Bytes ($written * 1MB))) -Key "Echt|$L" -Items $items `
        -Detail "Der freie Platz hält, was er verspricht. Geprüft wurde nur der freie Bereich; der bereits belegte Teil ($(Format-Bytes $usedBefore)) blieb unberührt.$cacheNote"
    "Bestanden: $(Format-Bytes ($written * 1MB)) fehlerfrei."
}

#endregion

#region Formatieren

function Format-ExternalDrive {
    <# Formatiert ein externes Laufwerk bzw. richtet den ganzen Datenträger neu ein. Nicht umkehrbar. #>
    param($Target, [hashtable]$Options)
    if (-not $Options) { throw 'Keine Formatier-Optionen angegeben.' }
    $fsName = "$($Options.FileSystem)"
    if ($fsName -notin 'exFAT', 'FAT32', 'NTFS') { throw "Unbekanntes Dateisystem »$fsName«." }
    if ("$($Options.Confirm)".Trim().TrimEnd(':').ToUpperInvariant() -ne "$($Target.Token)".ToUpperInvariant()) {
        throw 'Bestätigung stimmt nicht mit dem gewählten Laufwerk überein – nichts geändert.'
    }
    $disk = Assert-ExternalDisk -Number $Target.Disk -Letter $Target.Letter
    $reinit = [bool]$Options.Reinit -or -not $Target.Letter
    $size = if ($reinit) { $disk.Size } else { $Target.Size }
    if ($fsName -eq 'FAT32' -and $size -gt 32GB) { throw 'FAT32 lässt sich unter Windows nur bis 32 GB formatieren – bitte exFAT wählen.' }
    $max = @{ 'FAT32' = 11; 'exFAT' = 15; 'NTFS' = 32 }[$fsName]
    $label = ("$($Options.Label)" -replace '[\\/:*?"<>|]', '').Trim()
    if ($fsName -eq 'FAT32') { $label = $label.ToUpperInvariant() }
    if ($label.Length -gt $max) { $label = $label.Substring(0, $max).Trim() }
    $full = [bool]$Options.Full
    $how = if ($full) { 'vollständig (überschreibt und prüft jeden Sektor – kann sehr lange dauern)' } else { 'schnell' }
    Write-Host "     › $($Target.Name) wird $how mit $fsName formatiert …" -ForegroundColor Gray
    if ($reinit) {
        if ($disk.Style -ne 'RAW') {
            try { Clear-Disk -Number $disk.Number -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop }
            catch {
                # Manche Wechseldatenträger unterstützen Clear-Disk nicht – dann die Partitionen einzeln entfernen
                Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue | Remove-Partition -Confirm:$false -ErrorAction Stop
            }
        }
        $style = if ($disk.Size -gt 2TB) { 'GPT' } else { 'MBR' }
        $now = Get-Disk -Number $disk.Number
        if ("$($now.PartitionStyle)" -eq 'RAW') { Initialize-Disk -Number $disk.Number -PartitionStyle $style -ErrorAction Stop }
        $part = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
        $null = Format-Volume -Partition $part -FileSystem $fsName -NewFileSystemLabel $label -Full:$full -Force -Confirm:$false -ErrorAction Stop
        $letter = Get-PartitionLetter (Get-Partition -DiskNumber $disk.Number -PartitionNumber $part.PartitionNumber)
    } else {
        $null = Format-Volume -DriveLetter $Target.Letter -FileSystem $fsName -NewFileSystemLabel $label -Full:$full -Force -Confirm:$false -ErrorAction Stop
        $letter = $Target.Letter
    }
    $what = if ($reinit) { "komplett neu eingerichtet ($(Format-Bytes $disk.Size))" } else { 'formatiert' }
    Register-Change -Beschreibung "Externer Datenträger $what`: $($Target.Name) → $fsName »$label«$(if ($letter) { " ($($letter):)" })" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis 'Alle vorherigen Daten wurden gelöscht.'
    "$($Target.Name) $what mit $fsName$(if ($letter) { " als $($letter):" })."
}

#endregion

#region Werkzeug-Karten

function Read-ConsoleTarget {
    param($Targets, [string]$Prompt)
    $all = @($Targets)
    for ($i = 0; $i -lt $all.Count; $i++) { Write-Host ('    {0,3}) {1}' -f ($i + 1), $all[$i].Label) }
    @((Read-Selection (Read-Host "   $Prompt") $all.Count) | ForEach-Object { $all[$_] })
}

function Add-ExternalToolFindings {
    param([string]$Category)
    $withLetter = @(Get-ExternalTargets -WithLetterOnly | Where-Object { $_.FileSystem })
    $all = @(Get-ExternalTargets -IncludeContent)
    $disks = @(Get-ExternalDisks)
    if (-not $all) { return }

    if ($withLetter) {
        Add-Finding $Category Info 'Geschwindigkeitstest (ausführlich)' -Silent -Repeatable `
            -Detail 'Misst Lesen und Schreiben großer Dateien sowie vieler kleiner Blöcke (4K) in je 3 Durchgängen und ordnet das Ergebnis ein (z. B. »läuft nur mit USB-2.0-Geschwindigkeit«). Dauert je Laufwerk 1–5 Minuten; vorhandene Dateien bleiben unberührt.' `
            -SelectLabels @($withLetter | ForEach-Object { $_.Label }) -FixData $withLetter -FixLabel 'Geschwindigkeit der ausgewählten Laufwerke messen' -Fix {
            param($d, $pre)
            if (-not $pre) { $d = Read-ConsoleTarget $d 'Messen: Nummern oder leer = keine'; if (-not $d) { return 'Nichts ausgewählt.' } }
            (@($d) | ForEach-Object { Test-DriveSpeed $_ }) -join ' '
        }
        Add-Finding $Category Info 'Echtheitstest (gefälschte Kapazität erkennen)' -Silent -Repeatable `
            -Detail 'Füllt den freien Platz mit Testdaten, liest sie zurück und vergleicht (wie das bekannte H2testw). Erkennt gefälschte Sticks und Karten, die mehr Speicher vortäuschen, sowie defekten Speicher. Vorhandene Dateien bleiben unberührt; für eine vollständige Prüfung den Datenträger vorher leeren. Dauert je nach Größe und Geschwindigkeit bis zu mehreren Stunden – abbrechen jederzeit möglich.' `
            -SelectLabels @($withLetter | ForEach-Object { $_.Label }) -FixData $withLetter -FixLabel 'Echtheit der ausgewählten Laufwerke prüfen' -Fix {
            param($d, $pre)
            if (-not $pre) { $d = Read-ConsoleTarget $d 'Prüfen: Nummern oder leer = keine (abbrechen mit Strg+C)'; if (-not $d) { return 'Nichts ausgewählt.' } }
            (@($d) | ForEach-Object { Test-DriveAuthenticity $_ }) -join ' '
        }
    }

    Add-Finding $Category Info 'Datenträger formatieren' -Silent -Repeatable -AskFormat `
        -Detail 'Formatiert einen externen Datenträger mit exFAT (Austausch mit Mac, Fernseher, Kamera), FAT32 (bis 32 GB, für Autoradios und ältere Geräte) oder NTFS (nur Windows, Sicherungen). Option »komplett neu einrichten« löscht alle Partitionen und macht wieder die volle Größe nutzbar. ACHTUNG: Formatieren löscht alle Daten endgültig – vorher wird der Inhalt angezeigt und der Laufwerksbuchstabe muss zur Bestätigung eingetippt werden.' `
        -SelectLabels @($all | ForEach-Object { $_.Label }) -FixData $all -FixLabel 'Datenträger formatieren (löscht alle Daten)' -Fix {
        param($d, $pre)
        $opt = $Script:CurrentFixOptions
        if (-not $pre -or -not $opt) {
            $t = @(Read-ConsoleTarget $d 'Formatieren: EINE Nummer oder leer = abbrechen') | Select-Object -First 1
            if (-not $t) { return 'Abgebrochen.' }
            $rec = if ($t.Size -le 32GB) { 'exFAT (Autoradio/ältere Geräte: FAT32)' } else { 'exFAT' }
            $fs = (Read-Host "   Dateisystem exFAT / FAT32 / NTFS (Empfehlung: $rec)").Trim()
            if (-not $fs) { $fs = 'exFAT' }
            $lbl = Read-Host '   Name des Laufwerks (leer = ohne Namen)'
            $full = Read-YesNo 'Vollständig formatieren (prüft jeden Sektor, dauert lange)?' $false
            $re = if ($t.Letter) { Read-YesNo 'Komplett neu einrichten (alle Partitionen löschen, volle Größe nutzen)?' $false } else { $true }
            Write-Host "   ACHTUNG: Alle Daten auf $($t.Label) werden ENDGÜLTIG gelöscht." -ForegroundColor Red
            $c = Read-Host "   Zur Bestätigung $(if ($t.Letter) { 'den Laufwerksbuchstaben' } else { 'die Datenträgernummer' }) »$($t.Token)« eintippen"
            $opt = @{ FileSystem = $fs; Label = $lbl; Full = $full; Reinit = $re; Confirm = $c }
            $d = @($t)
        }
        Format-ExternalDrive -Target @($d)[0] -Options $opt
    }

    $ejectTargets = @($disks | Where-Object { $_.Partitions | Where-Object { $_.Letter } } | ForEach-Object {
            $d = $_; $ls = @($d.Partitions | Where-Object { $_.Letter } | ForEach-Object { "$($_.Letter):" })
            [pscustomobject]@{ Label = "$($ls -join ', ') $($d.Name)"; Disk = $d.Number; Letter = @($d.Partitions | Where-Object { $_.Letter })[0].Letter }
        })
    if ($ejectTargets) {
        Add-Finding $Category Info 'Sicher entfernen' -Silent -Repeatable `
            -Detail 'Schreibt noch offene Daten auf den Datenträger und meldet ihn ab, damit er gefahrlos abgezogen werden kann.' `
            -SelectLabels @($ejectTargets | ForEach-Object { $_.Label }) -SelectAllByDefault -FixData $ejectTargets -FixLabel 'Ausgewählte Datenträger sicher entfernen' -Fix {
            param($d, $pre)
            if (-not $pre) { $d = Read-ConsoleTarget $d 'Entfernen: Nummern oder leer = keine'; if (-not $d) { return 'Nichts ausgewählt.' } }
            (@($d) | ForEach-Object { Dismount-ExternalDrive -Letter $_.Letter -Disk $_.Disk }) -join ' '
        }
    }
}

#endregion
