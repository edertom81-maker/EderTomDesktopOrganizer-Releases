<#
    Partitionswerkzeuge für externe Datenträger und interne Zusatzlaufwerke: Übersicht als Leiste, Partition erstellen,
    Datenträger aufteilen, Partition löschen, Größe ändern (NTFS), Laufwerksbuchstaben und Namen ändern, in NTFS umwandeln.
    Der Windows-, Boot- und Systemdatenträger sowie Datenträger mit Auslagerungsdatei sind immer ausgeschlossen;
    jede Änderung prüft das unmittelbar vorher erneut (Assert-ExternalDisk -AllowInternal).
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:PartitionColors = @('#1570EF', '#0E9384', '#7A5AF8', '#DC6803', '#079455', '#C11574', '#3E4784', '#B54708')
$Script:FileSystemChoices = @('exFAT', 'NTFS', 'FAT32')
$Script:FileSystemChoiceLabels = @(
    'exFAT – Windows, Mac, Fernseher, Kameras (empfohlen für Austausch)'
    'NTFS – nur Windows, z. B. Sicherungen und interne Laufwerke'
    'FAT32 – Autoradios und ältere Geräte (bis 32 GB, Dateien max. 4 GB)'
)

#region Hilfsfunktionen

function Get-FreeDriveLetters {
    $used = @{}
    foreach ($d in [IO.DriveInfo]::GetDrives()) { $used["$($d.Name)".Substring(0, 1).ToUpperInvariant()] = $true }
    foreach ($p in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) { if ($p.Name.Length -eq 1) { $used[$p.Name.ToUpperInvariant()] = $true } }
    @([char[]](68..90) | ForEach-Object { "$_" } | Where-Object { -not $used.ContainsKey($_) })
}

function Get-DiskLabel {
    param($Disk)
    $kind = if ($Disk.IsInternal) { 'intern' } else { $Disk.Bus }
    '{0}: {1} ({2}) – {3}' -f "Datenträger $($Disk.Number)", $Disk.Name, $kind, (Format-Bytes $Disk.Size)
}

function Get-PartitionLabel {
    param($Disk, $Part, [switch]$IncludeContent)
    $head = if ($Part.Letter) { "$($Part.Letter):" } else { "Partition $($Part.PartitionNumber) (ohne Buchstaben)" }
    $fs = if ($Part.FileSystem) { $Part.FileSystem } else { 'RAW' }
    $lab = '{0}{1} – {2}, {3} (Datenträger {4}: {5})' -f $head, $(if ($Part.Label) { " »$($Part.Label)«" } else { '' }), $fs, (Format-Bytes $Part.Size), $Disk.Number, $Disk.Name
    if ($IncludeContent -and $Part.Letter) { $lab += " – $(Get-VolumeContentSummary $Part.Letter)" }
    return $lab
}

function Get-PartitionToken {
    param($Part, $Disk)
    if ($Part.Letter) { return $Part.Letter }
    return "$($Disk.Number)-$($Part.PartitionNumber)"
}

function Get-FreeAfter {
    <# Freier (nicht zugeordneter) Platz direkt hinter einer Partition. #>
    param($Disk, $Part)
    $next = @($Disk.Partitions | Where-Object { $_.Offset -gt $Part.Offset } | Sort-Object Offset | Select-Object -First 1)
    $end = if ($next) { $next[0].Offset } else { $Disk.Size - $(if ($Disk.Style -eq 'GPT') { 1MB } else { 0 }) }
    return [math]::Max([double]0, $end - ($Part.Offset + $Part.Size))
}

function Get-DiskBarChart {
    <# Abschnitte der Partitionsleiste in Reihenfolge der Partitionen, inklusive nicht zugeordneter Bereiche. #>
    param($Disk)
    $out = @()
    $cursor = [double]1MB
    $i = 0
    foreach ($p in @($Disk.Partitions | Sort-Object Offset)) {
        if ($p.Offset - $cursor -ge 16MB) { $out += [pscustomobject]@{ Label = 'Nicht zugeordnet'; Text = Format-Bytes ($p.Offset - $cursor); Value = $p.Offset - $cursor; Color = '#98A2B3' } }
        $sysPart = $p.Type -match 'System|Reserved|Recovery'
        $label = if ($p.Letter) { "$($p.Letter): $($p.Label)".Trim() } elseif ($sysPart) { $p.Type } else { "Partition $($p.PartitionNumber)" }
        $fs = if ($p.FileSystem) { $p.FileSystem } elseif ($sysPart) { '' } else { 'RAW' }
        $color = if ($sysPart) { '#667085' } else { $Script:PartitionColors[$i++ % $Script:PartitionColors.Count] }
        $out += [pscustomobject]@{ Label = $label; Text = ("$fs  $(Format-Bytes $p.Size)").Trim(); Value = $p.Size; Color = $color }
        $cursor = $p.Offset + $p.Size
    }
    $tail = $Disk.Size - $cursor - $(if ($Disk.Style -eq 'GPT') { 1MB } else { 0 })
    if ($tail -ge 16MB) { $out += [pscustomobject]@{ Label = 'Nicht zugeordnet'; Text = Format-Bytes $tail; Value = $tail; Color = '#98A2B3' } }
    if (-not $out -and $Disk.Size -gt 0) { $out += [pscustomobject]@{ Label = 'Nicht eingerichtet'; Text = Format-Bytes $Disk.Size; Value = $Disk.Size; Color = '#98A2B3' } }
    return $out
}

function Clear-DiskLayout {
    <# Alle Partitionen entfernen und den Datenträger leer initialisieren (MBR bis 2 TB, sonst GPT). #>
    param($Disk)
    if ($Disk.Style -ne 'RAW') {
        try { Clear-Disk -Number $Disk.Number -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop }
        catch { Get-Partition -DiskNumber $Disk.Number -ErrorAction SilentlyContinue | Remove-Partition -Confirm:$false -ErrorAction Stop }
    }
    $now = Get-Disk -Number $Disk.Number
    if ("$($now.PartitionStyle)" -eq 'RAW') { Initialize-Disk -Number $Disk.Number -PartitionStyle $(if ($Disk.Size -gt 2TB) { 'GPT' } else { 'MBR' }) -ErrorAction Stop }
}

function Get-CleanLabel {
    param([string]$Label, [string]$FileSystem)
    $max = @{ 'FAT32' = 11; 'exFAT' = 15; 'NTFS' = 32 }[$FileSystem]
    $l = ("$Label" -replace '[\\/:*?"<>|]', '').Trim()
    if ($FileSystem -eq 'FAT32') { $l = $l.ToUpperInvariant() }
    if ($max -and $l.Length -gt $max) { $l = $l.Substring(0, $max).Trim() }
    return $l
}

function New-FormattedPartition {
    param([int]$Disk, [double]$Size, [string]$FileSystem, [string]$Label, [string]$Letter)
    if ($FileSystem -eq 'FAT32' -and $Size -gt 32GB) { throw 'FAT32 lässt sich unter Windows nur bis 32 GB formatieren – exFAT oder NTFS wählen bzw. die Größe verringern.' }
    $args1 = @{ DiskNumber = $Disk; ErrorAction = 'Stop' }
    if ($Size -gt 0) { $args1.Size = [long]([math]::Floor($Size / 1MB) * 1MB) } else { $args1.UseMaximumSize = $true }
    if ($Letter) { $args1.DriveLetter = $Letter } else { $args1.AssignDriveLetter = $true }
    $part = New-Partition @args1
    $null = Format-Volume -Partition $part -FileSystem $FileSystem -NewFileSystemLabel (Get-CleanLabel $Label $FileSystem) -Force -Confirm:$false -ErrorAction Stop
    return Get-PartitionLetter (Get-Partition -DiskNumber $Disk -PartitionNumber $part.PartitionNumber)
}

#endregion

#region Werkzeug-Karten

function Add-PartitionOverviewFindings {
    <# Partitionsleisten der internen Zusatzlaufwerke (externe Datenträger zeigen sie in ihrer Übersichtskarte). #>
    param([string]$Category)
    foreach ($d in @(Get-ExternalDisks -IncludeInternal | Where-Object { $_.IsInternal })) {
        $items = @($d.Partitions | Sort-Object Offset | ForEach-Object { '{0,-18} {1,-8} {2,10}  {3}' -f $(if ($_.Letter) { "$($_.Letter):" } else { "Partition $($_.PartitionNumber)" }), $(if ($_.FileSystem) { $_.FileSystem } else { $_.Type }), (Format-Bytes $_.Size), $_.Label })
        Add-Finding $Category OK "Zusatzlaufwerk (intern): $($d.Name) – $(Format-Bytes $d.Size)" -Items $items -Chart (Get-DiskBarChart $d) -ChartStyle Leiste
    }
}

function Add-PartitionToolFindings {
    param([string]$Category)
    $disks = @(Get-ExternalDisks -IncludeInternal)
    if (-not $disks) { return }
    $letters = @(Get-FreeDriveLetters)
    $fsField = { param($name, $label, $def) @{ Name = $name; Type = 'Auswahl'; Label = $label; Items = $Script:FileSystemChoiceLabels; Default = $def } }

    # Partition erstellen
    $withFree = @($disks | Where-Object { $_.FreeExtent -ge 16MB -or $_.Style -eq 'RAW' })
    if ($withFree) {
        $spec = @{
            Text   = 'Legt im freien (nicht zugeordneten) Bereich eine neue Partition an und formatiert sie. Vorhandene Partitionen bleiben unberührt.'
            Fields = @(
                @{ Name = 'Ziel'; Type = 'Auswahl'; Label = 'Datenträger'; Items = @($withFree | ForEach-Object { "$(Get-DiskLabel $_) – frei: $(Format-Bytes $(if ($_.Style -eq 'RAW') { $_.Size } else { $_.FreeExtent }))" }); Default = 0 }
                @{ Name = 'Groesse'; Type = 'Zahl'; Label = 'Größe in GB (leer = ganzer freier Bereich)'; Default = '' }
                (& $fsField 'Dateisystem' 'Dateisystem' 0)
                @{ Name = 'Name'; Type = 'Text'; Label = 'Name'; Default = '' }
                @{ Name = 'Buchstabe'; Type = 'Auswahl'; Label = 'Laufwerksbuchstabe'; Items = @('automatisch') + @($letters | ForEach-Object { "$($_):" }); Default = 0 }
            )
        }
        Add-Finding $Category Info 'Partition erstellen' -Silent -Repeatable -AskParams $spec `
            -Detail 'Nutzt freien Platz auf einem Datenträger für eine neue Partition (z. B. nach dem Verkleinern oder auf einem neuen Laufwerk).' `
            -FixLabel 'Neue Partition anlegen' -FixData @{ Targets = $withFree; Spec = $spec; Letters = $letters } -Fix {
            param($d)
            $o = Resolve-FixParams $d.Spec
            $t = (Get-Choice $d.Targets $o.Ziel)
            $disk = Assert-ExternalDisk -Number $t.Number -AllowInternal
            if ($disk.Style -eq 'RAW') { Clear-DiskLayout $disk; $free = $disk.Size - 2MB } else { $free = $disk.FreeExtent }
            $size = if ("$($o.Groesse)".Trim()) { ConvertTo-GBValue $o.Groesse } else { 0 }
            if ($size -gt $free) { throw "Nur $(Format-Bytes $free) frei – kleinere Größe wählen." }
            $fs = $Script:FileSystemChoices[[int]$o.Dateisystem]
            $letter = if ([int]$o.Buchstabe -gt 0) { (Get-Choice $d.Letters ([int]$o.Buchstabe - 1)) } else { '' }
            if ($size -eq 0 -and $fs -eq 'FAT32' -and $free -gt 32GB) { $size = 32GB - 1MB }
            $l = New-FormattedPartition -Disk $disk.Number -Size $size -FileSystem $fs -Label $o.Name -Letter $letter
            Register-Change -Beschreibung "Partition erstellt auf $($disk.Name): $fs »$($o.Name)«$(if ($l) { " ($($l):)" })" -Typ 'Protokoll' -NichtUmkehrbar
            "Neue Partition $(if ($l) { "$($l): " })mit $fs angelegt."
        }
    }

    # Datenträger aufteilen
    $spec = @{
        Text    = 'Richtet den Datenträger neu mit zwei Partitionen ein – z. B. 32 GB FAT32 fürs Autoradio und den Rest als exFAT.'
        Warning = 'ACHTUNG: ALLE Daten auf dem gewählten Datenträger werden endgültig gelöscht.'
        Fields  = @(
            @{ Name = 'Ziel'; Type = 'Auswahl'; Label = 'Datenträger'; Items = @($disks | ForEach-Object { Get-DiskLabel $_ }); Tokens = @($disks | ForEach-Object { "$($_.Number)" }); Default = 0 }
            @{ Name = 'Groesse1'; Type = 'Zahl'; Label = 'Größe der ersten Partition in GB'; Default = '32' }
            (& $fsField 'Fs1' 'Dateisystem der ersten Partition' 2)
            @{ Name = 'Name1'; Type = 'Text'; Label = 'Name der ersten Partition'; Default = 'AUTO' }
            (& $fsField 'Fs2' 'Dateisystem der zweiten Partition (Rest)' 0)
            @{ Name = 'Name2'; Type = 'Text'; Label = 'Name der zweiten Partition'; Default = 'DATEN' }
            @{ Name = 'Bestaetigung'; Type = 'Bestaetigung'; Label = 'Zur Bestätigung die Datenträgernummer'; From = 'Ziel' }
        )
    }
    Add-Finding $Category Info 'Datenträger aufteilen' -Silent -Repeatable -AskParams $spec `
        -Detail 'Teilt einen Datenträger in zwei Laufwerke auf. ACHTUNG: löscht alle Daten auf dem Datenträger – vorher wird die Datenträgernummer zur Bestätigung abgefragt.' `
        -FixLabel 'Datenträger in zwei Partitionen aufteilen (löscht alle Daten)' -FixData @{ Targets = $disks; Spec = $spec } -Fix {
        param($d)
        $o = Resolve-FixParams $d.Spec
        $t = (Get-Choice $d.Targets $o.Ziel)
        Test-ParamConfirmation $o.Bestaetigung "$($t.Number)"
        $disk = Assert-ExternalDisk -Number $t.Number -AllowInternal
        $s1 = ConvertTo-GBValue $o.Groesse1
        if ($s1 -ge $disk.Size - 64MB) { throw "Die erste Partition muss kleiner als der Datenträger ($(Format-Bytes $disk.Size)) sein." }
        $fs1 = $Script:FileSystemChoices[[int]$o.Fs1]; $fs2 = $Script:FileSystemChoices[[int]$o.Fs2]
        if ($fs1 -eq 'FAT32' -and $s1 -gt 32GB) { throw 'FAT32 ist unter Windows nur bis 32 GB möglich.' }
        if ($fs2 -eq 'FAT32' -and ($disk.Size - $s1) -gt 32GB) { throw 'Der Rest ist größer als 32 GB – für die zweite Partition exFAT oder NTFS wählen.' }
        Write-Host "     › $($disk.Name) wird neu eingerichtet …" -ForegroundColor Gray
        Clear-DiskLayout $disk
        $l1 = New-FormattedPartition -Disk $disk.Number -Size $s1 -FileSystem $fs1 -Label $o.Name1
        $l2 = New-FormattedPartition -Disk $disk.Number -Size 0 -FileSystem $fs2 -Label $o.Name2
        Register-Change -Beschreibung "Datenträger aufgeteilt: $($disk.Name) → $(Format-Bytes $s1) $fs1 ($($l1):) + Rest $fs2 ($($l2):)" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis 'Alle vorherigen Daten wurden gelöscht.'
        "Aufgeteilt: $($l1): ($fs1, $(Format-Bytes $s1)) und $($l2): ($fs2)."
    }

    # Partition löschen
    $parts = @(foreach ($dk in $disks) { foreach ($p in @(Get-DataPartitions $dk)) { [pscustomobject]@{ Disk = $dk; Part = $p } } })
    if ($parts) {
        $spec = @{
            Text    = 'Löscht eine Partition samt Inhalt. Der Platz wird danach als »nicht zugeordnet« angezeigt und kann für eine neue Partition oder zum Vergrößern genutzt werden.'
            Warning = 'ACHTUNG: Alle Daten auf der gewählten Partition werden endgültig gelöscht.'
            Fields  = @(
                @{ Name = 'Ziel'; Type = 'Auswahl'; Label = 'Partition'; Items = @($parts | ForEach-Object { Get-PartitionLabel $_.Disk $_.Part -IncludeContent }); Tokens = @($parts | ForEach-Object { Get-PartitionToken $_.Part $_.Disk }); Default = 0 }
                @{ Name = 'Bestaetigung'; Type = 'Bestaetigung'; Label = 'Zur Bestätigung den Laufwerksbuchstaben bzw. die Kennung'; From = 'Ziel' }
            )
        }
        Add-Finding $Category Info 'Partition löschen' -Silent -Repeatable -AskParams $spec `
            -Detail 'Entfernt eine Partition. Vorher wird der Inhalt angezeigt und der Laufwerksbuchstabe muss zur Bestätigung eingetippt werden.' `
            -FixLabel 'Partition löschen (löscht deren Daten)' -FixData @{ Targets = $parts; Spec = $spec } -Fix {
            param($d)
            $o = Resolve-FixParams $d.Spec
            $t = (Get-Choice $d.Targets $o.Ziel)
            Test-ParamConfirmation $o.Bestaetigung (Get-PartitionToken $t.Part $t.Disk)
            $disk = Assert-ExternalDisk -Number $t.Disk.Number -Letter $t.Part.Letter -AllowInternal
            $now = Get-Partition -DiskNumber $disk.Number -PartitionNumber $t.Part.PartitionNumber -ErrorAction Stop
            if ([double]$now.Size -ne $t.Part.Size) { throw 'Die Partition hat sich seit der Prüfung verändert – bitte »Datenträger prüfen« und erneut versuchen.' }
            Remove-Partition -DiskNumber $disk.Number -PartitionNumber $t.Part.PartitionNumber -Confirm:$false -ErrorAction Stop
            Register-Change -Beschreibung "Partition gelöscht: $(Get-PartitionLabel $t.Disk $t.Part)" -Typ 'Protokoll' -NichtUmkehrbar
            "Partition $(Get-PartitionToken $t.Part $t.Disk) gelöscht."
        }
    }

    # Größe ändern (nur NTFS)
    $ntfs = @($parts | Where-Object { $_.Part.FileSystem -eq 'NTFS' })
    if ($ntfs) {
        $spec = @{
            Text   = 'Verkleinert eine NTFS-Partition (der frei werdende Platz wird »nicht zugeordnet«) oder vergrößert sie in direkt dahinter liegenden freien Platz. Die Daten bleiben erhalten; vor dem Verkleinern wird das Dateisystem geprüft. Wichtige Daten trotzdem vorher sichern.'
            Fields = @(
                @{ Name = 'Ziel'; Type = 'Auswahl'; Label = 'Partition'; Items = @($ntfs | ForEach-Object { "$(Get-PartitionLabel $_.Disk $_.Part) – dahinter frei: $(Format-Bytes (Get-FreeAfter $_.Disk $_.Part))" }); Default = 0 }
                @{ Name = 'Groesse'; Type = 'Zahl'; Label = 'Neue Größe in GB'; Default = '' }
            )
        }
        Add-Finding $Category Info 'Partitionsgröße ändern (NTFS)' -Silent -Repeatable -AskParams $spec `
            -Detail 'Vergrößern oder Verkleinern ohne Datenverlust. Windows kann das nur bei NTFS – exFAT- und FAT32-Partitionen lassen sich nur durch Löschen und neu Anlegen in der Größe ändern (oder vorher »In NTFS umwandeln«, nur FAT32).' `
            -FixLabel 'Größe der Partition ändern' -FixData @{ Targets = $ntfs; Spec = $spec } -Fix {
            param($d)
            $o = Resolve-FixParams $d.Spec
            $t = (Get-Choice $d.Targets $o.Ziel)
            $disk = Assert-ExternalDisk -Number $t.Disk.Number -Letter $t.Part.Letter -AllowInternal
            $new = ConvertTo-GBValue $o.Groesse
            $range = Get-PartitionSupportedSize -DiskNumber $disk.Number -PartitionNumber $t.Part.PartitionNumber -ErrorAction Stop
            if ($new -lt $range.SizeMin -or $new -gt $range.SizeMax) {
                throw "Möglich sind $(Format-Bytes $range.SizeMin) bis $(Format-Bytes $range.SizeMax) (Untergrenze durch belegte und unverschiebbare Daten, Obergrenze durch den freien Platz direkt dahinter)."
            }
            if ($new -lt $t.Part.Size -and $t.Part.Letter) {
                Write-Host "     › Dateisystem von $($t.Part.Letter): wird vor dem Verkleinern geprüft …" -ForegroundColor Gray
                $null = & chkdsk.exe "$($t.Part.Letter):" 2>&1
                if ($LASTEXITCODE -ne 0) { throw "Das Dateisystem von $($t.Part.Letter): hat Fehler – zuerst »Dateisystem reparieren«, dann erneut versuchen." }
            }
            Resize-Partition -DiskNumber $disk.Number -PartitionNumber $t.Part.PartitionNumber -Size ([long]([math]::Floor($new / 1MB) * 1MB)) -ErrorAction Stop
            Register-Change -Beschreibung "Partitionsgröße geändert: $(Get-PartitionToken $t.Part $t.Disk) von $(Format-Bytes $t.Part.Size) auf $(Format-Bytes $new)" -Typ 'Protokoll' -NichtUmkehrbar
            "Größe von $(Format-Bytes $t.Part.Size) auf $(Format-Bytes $new) geändert."
        }
    }

    # Laufwerksbuchstabe und Name
    $fsParts = @($parts | Where-Object { $_.Part.FileSystem })
    if ($fsParts) {
        $spec = @{
            Text   = 'Ändert den Laufwerksbuchstaben oder entfernt ihn (das Laufwerk erscheint dann nicht mehr im Explorer). Programme, die feste Pfade auf dieses Laufwerk verwenden, finden ihre Dateien danach unter Umständen nicht mehr. Rückgängig über »Änderungen«.'
            Fields = @(
                @{ Name = 'Ziel'; Type = 'Auswahl'; Label = 'Partition'; Items = @($fsParts | ForEach-Object { Get-PartitionLabel $_.Disk $_.Part }); Default = 0 }
                @{ Name = 'Buchstabe'; Type = 'Auswahl'; Label = 'Neuer Laufwerksbuchstabe'; Items = @($letters | ForEach-Object { "$($_):" }) + @('Buchstaben entfernen'); Default = 0 }
            )
        }
        Add-Finding $Category Info 'Laufwerksbuchstaben ändern' -Silent -Repeatable -AskParams $spec `
            -Detail 'Weist einer Partition einen anderen Laufwerksbuchstaben zu oder entfernt ihn. Umkehrbar über »Änderungen«.' `
            -FixLabel 'Laufwerksbuchstaben ändern' -FixData @{ Targets = $fsParts; Spec = $spec; Letters = $letters } -Fix {
            param($d)
            $o = Resolve-FixParams $d.Spec
            $t = (Get-Choice $d.Targets $o.Ziel)
            $disk = Assert-ExternalDisk -Number $t.Disk.Number -Letter $t.Part.Letter -AllowInternal
            $i = [int]$o.Buchstabe
            if ($i -lt 0 -or $i -gt $d.Letters.Count) { throw 'Ungültige Auswahl – nichts geändert.' }
            $new = if ($i -lt $d.Letters.Count) { $d.Letters[$i] } else { '' }
            $old = $t.Part.Letter
            if ($old) { Remove-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $t.Part.PartitionNumber -AccessPath "$($old):\" -ErrorAction Stop }
            if ($new) { Add-PartitionAccessPath -DiskNumber $disk.Number -PartitionNumber $t.Part.PartitionNumber -AccessPath "$($new):\" -ErrorAction Stop }
            Register-Change -Beschreibung "Laufwerksbuchstabe: $(if ($old) { "$($old):" } else { 'ohne' }) → $(if ($new) { "$($new):" } else { 'entfernt' }) ($($disk.Name))" -Typ 'Laufwerksbuchstabe' -Daten @{ Disk = $disk.Number; Partition = $t.Part.PartitionNumber; Previous = $old; New = $new }
            if ($new) { "Laufwerksbuchstabe ist jetzt $($new):. Rückgängig über »Änderungen«." } else { 'Laufwerksbuchstabe entfernt. Rückgängig über »Änderungen«.' }
        }

        $spec = @{
            Text   = 'Ändert den angezeigten Namen eines Laufwerks. FAT32 erlaubt höchstens 11 Zeichen (Großbuchstaben), exFAT 15 und NTFS 32 Zeichen.'
            Fields = @(
                @{ Name = 'Ziel'; Type = 'Auswahl'; Label = 'Partition'; Items = @($fsParts | ForEach-Object { Get-PartitionLabel $_.Disk $_.Part }); Default = 0 }
                @{ Name = 'Name'; Type = 'Text'; Label = 'Neuer Name'; Default = '' }
            )
        }
        Add-Finding $Category Info 'Laufwerk umbenennen' -Silent -Repeatable -AskParams $spec `
            -Detail 'Gibt einem Laufwerk einen neuen Namen (wird im Explorer und auf anderen Geräten angezeigt). Umkehrbar über »Änderungen«.' `
            -FixLabel 'Laufwerk umbenennen' -FixData @{ Targets = $fsParts; Spec = $spec } -Fix {
            param($d)
            $o = Resolve-FixParams $d.Spec
            $t = (Get-Choice $d.Targets $o.Ziel)
            $disk = Assert-ExternalDisk -Number $t.Disk.Number -Letter $t.Part.Letter -AllowInternal
            $name = Get-CleanLabel $o.Name $t.Part.FileSystem
            Get-Partition -DiskNumber $disk.Number -PartitionNumber $t.Part.PartitionNumber -ErrorAction Stop | Get-Volume -ErrorAction Stop | Set-Volume -NewFileSystemLabel $name -ErrorAction Stop
            Register-Change -Beschreibung "Laufwerk umbenannt: »$($t.Part.Label)« → »$name« ($(Get-PartitionToken $t.Part $t.Disk))" -Typ 'Volumename' -Daten @{ Disk = $disk.Number; Partition = $t.Part.PartitionNumber; Previous = $t.Part.Label }
            "Neuer Name: »$name«. Rückgängig über »Änderungen«."
        }
    }

    # In NTFS umwandeln (nur FAT/FAT32 – convert.exe kann kein exFAT)
    $fat = @($parts | Where-Object { $_.Part.FileSystem -match '^FAT(32)?$' -and $_.Part.Letter })
    if ($fat) {
        $spec = @{
            Text   = 'Wandelt FAT32 ohne Datenverlust in NTFS um: danach sind Dateien über 4 GB möglich. Nur in diese Richtung möglich – Mac, Fernseher, Autoradio und Kameras können NTFS meist nur lesen oder gar nicht verwenden.'
            Fields = @(@{ Name = 'Ziel'; Type = 'Auswahl'; Label = 'Laufwerk'; Items = @($fat | ForEach-Object { Get-PartitionLabel $_.Disk $_.Part }); Default = 0 })
        }
        Add-Finding $Category Info 'In NTFS umwandeln (ohne Datenverlust)' -Silent -Repeatable -AskParams $spec `
            -Detail 'Wandelt ein FAT32-Laufwerk mit dem Windows-Befehl »convert« in NTFS um; die Dateien bleiben erhalten. exFAT lässt sich so nicht umwandeln. Nicht umkehrbar (zurück nur durch Formatieren).' `
            -FixLabel 'Laufwerk in NTFS umwandeln' -FixData @{ Targets = $fat; Spec = $spec } -Fix {
            param($d)
            $o = Resolve-FixParams $d.Spec
            $t = (Get-Choice $d.Targets $o.Ziel)
            $null = Assert-ExternalDisk -Number $t.Disk.Number -Letter $t.Part.Letter -AllowInternal
            Write-Host "     › $($t.Part.Letter): wird in NTFS umgewandelt (Laufwerk wird kurz getrennt) …" -ForegroundColor Gray
            # convert fragt nach dem aktuellen Namen des Laufwerks – er wird über die Eingabe übergeben
            $out = @("$($t.Part.Label)", 'J', 'Y') | & convert.exe "$($t.Part.Letter):" /FS:NTFS /X 2>&1
            if ($LASTEXITCODE -ne 0) { throw "Umwandlung nicht möglich: $((@($out) | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Select-Object -Last 2) -join ' ')" }
            Register-Change -Beschreibung "In NTFS umgewandelt: $(Get-PartitionLabel $t.Disk $t.Part)" -Typ 'Protokoll' -NichtUmkehrbar
            "$($t.Part.Letter): ist jetzt NTFS – die Dateien sind erhalten."
        }
    }
}

#endregion
