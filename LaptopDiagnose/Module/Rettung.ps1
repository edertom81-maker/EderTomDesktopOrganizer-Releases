<#
    Gelöschte Dateien retten (Oberfläche für das kostenlose Microsoft-Tool »Windows File Recovery«, winfr.exe) und
    Datenträger sicher löschen (freien Platz überschreiben, Laufwerk vollständig formatieren, ganzen Datenträger nullen).
    Sicher löschen ist für den Windows-Datenträger und Datenträger mit Auslagerungsdatei immer gesperrt.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:WinFrStoreUrl = 'ms-windows-store://pdp/?ProductId=9N26S50LN705'
$Script:RecoveryKinds = @(
    @{ Label = 'Fotos (JPG, PNG, HEIC, RAW)'; Patterns = @('*.jpg', '*.jpeg', '*.png', '*.heic', '*.cr2', '*.nef', '*.arw', '*.dng') }
    @{ Label = 'Dokumente (Word, Excel, PowerPoint, PDF)'; Patterns = @('*.docx', '*.doc', '*.xlsx', '*.xls', '*.pptx', '*.pdf', '*.txt') }
    @{ Label = 'Videos (MP4, MOV, AVI)'; Patterns = @('*.mp4', '*.mov', '*.avi', '*.mkv', '*.wmv') }
    @{ Label = 'Musik (MP3, WMA, M4A)'; Patterns = @('*.mp3', '*.wma', '*.m4a', '*.wav') }
    @{ Label = 'Archive (ZIP)'; Patterns = @('*.zip') }
    @{ Label = 'Eigenes Suchmuster (Feld »Suchmuster«)'; Patterns = @() }
)

#region Gelöschte Dateien retten

function Get-WinFrPath {
    $c = Get-Command winfr.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $p = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winfr.exe'
    if (Test-Path -LiteralPath $p) { return $p }
    return $null
}

function Get-RecoveryArguments {
    <# Befehlszeile für winfr: Modus nach Wahl bzw. Dateisystem (FAT/exFAT nur »Signatur«), Filter nach Dateiart. #>
    param([string]$Source, [string]$Dest, [int]$Kind, [int]$Mode, [string]$Pattern, [string]$FileSystem)
    if ($Kind -lt 0 -or $Kind -ge $Script:RecoveryKinds.Count) { throw 'Ungültige Auswahl – nichts geändert.' }
    $k = $Script:RecoveryKinds[$Kind]
    # 0 = automatisch, 1 = normal, 2 = gründlich, 3 = Signatur
    if ($Mode -eq 0) { $Mode = if ($FileSystem -match 'FAT') { 3 } else { 1 } }
    if ($FileSystem -match 'FAT' -and $Mode -lt 3) { $Mode = 3 }
    $a = @("$($Source):", "$($Dest)")
    $patterns = @($k.Patterns)
    if ($Kind -eq $Script:RecoveryKinds.Count - 1) {
        if (-not "$Pattern".Trim()) { throw 'Bitte ein Suchmuster angeben, z. B. »*Urlaub*« oder »\Users\Name\Documents\«.' }
        $patterns = @("$Pattern".Trim())
    }
    switch ($Mode) {
        1 { $a += '/regular'; foreach ($p in $patterns) { $a += @('/n', $p) } }
        2 { $a += '/extensive'; foreach ($p in $patterns) { $a += @('/n', $p) } }
        3 { $a += '/extensive'; foreach ($p in $patterns) { $a += @('/n', $p) } }   # gründliche Suche nach Dateisignaturen, auch für FAT/exFAT
    }
    $a += '/a'
    return [pscustomobject]@{ Arguments = $a; Mode = $Mode }
}

function Invoke-FileRecovery {
    param($Source, $Target, [int]$Kind, [int]$Mode, [string]$Pattern)
    $exe = Get-WinFrPath
    if (-not $exe) {
        Start-Process $Script:WinFrStoreUrl
        throw 'Windows File Recovery ist nicht installiert – der Microsoft Store wurde geöffnet. Nach der (kostenlosen) Installation erneut starten.'
    }
    if ($Source.Letter -eq $Target.Letter) { throw 'Gerettet wird immer auf ein ANDERES Laufwerk – sonst würden die gelöschten Daten überschrieben.' }
    $dest = Join-Path "$($Target.Letter):\" ('Gerettet_{0}_{1:yyyyMMdd_HHmm}' -f $Source.Letter, (Get-Date))
    $null = New-Item -ItemType Directory -Path $dest -Force
    $r = Get-RecoveryArguments -Source $Source.Letter -Dest $dest -Kind $Kind -Mode $Mode -Pattern $Pattern -FileSystem $Source.FileSystem
    $modeName = @('', 'normal', 'gründlich', 'Signatur')[$r.Mode]
    Write-Host "     › Suche nach gelöschten Dateien auf $($Source.Letter): ($modeName) – das kann je nach Größe lange dauern …" -ForegroundColor Gray
    Set-Cancelable $true
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $last = [datetime]::MinValue
    try {
        $wargs = @($r.Arguments)
        & $exe @wargs 2>&1 | ForEach-Object {
            $line = "$_".Trim()
            if ($line -and (([datetime]::UtcNow - $last).TotalSeconds -ge 10 -or $line -match 'Pass|Durchgang') -and $line -match '\d+\s*%|Pass|Durchgang') {
                $last = [datetime]::UtcNow
                Write-Host "     › Dateien retten: $line" -ForegroundColor Gray
            }
            if (Test-CancelRequested) { Get-Process -Name winfr -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; throw 'Abgebrochen – bereits gerettete Dateien bleiben im Zielordner.' }
        }
    } finally { Set-Cancelable $false }
    $files = @(Get-ChildItem -LiteralPath $dest -Recurse -File -Force -ErrorAction SilentlyContinue)
    $size = [double](($files | Measure-Object Length -Sum).Sum)
    $items = @(
        "Gesucht auf: $($Source.Label)"
        "Gerettet nach: $dest"
        "Gefunden: $($files.Count) Datei(en), $(Format-Bytes $size) in $(Format-Duration $sw.Elapsed.TotalSeconds) (Modus: $modeName)"
    ) + @($files | Sort-Object Length -Descending | Select-Object -First 15 | ForEach-Object { "  $($_.FullName)" })
    Remove-FindingByKey "Gerettet|$($Source.Letter)"
    $sev = if ($files.Count) { 'OK' } else { 'Info' }
    $detail = if ($files.Count) { 'Die Dateien liegen im Zielordner (Doppelklick auf eine Zeile öffnet den Ordner). Nicht jede gefundene Datei ist vollständig – Fotos und Dokumente einzeln öffnen und prüfen.' }
    else { 'Nichts gefunden. Den Modus »gründlich« versuchen (NTFS) bzw. bei Speicherkarten »Signatur«. Wurde das Laufwerk seit dem Löschen stark beschrieben, sind die Daten meist überschrieben.' }
    Add-Finding 'Extern' $sev "Dateien retten von $($Source.Letter): $($files.Count) Datei(en) gefunden" -Key "Gerettet|$($Source.Letter)" -Items $items -Detail $detail
    "$($files.Count) Datei(en) gerettet nach $dest."
}

#endregion

#region Sicher löschen

function Test-IsFlashDisk {
    param([int]$Number)
    $pd = Get-PhysicalDisk -ErrorAction SilentlyContinue | Where-Object { "$($_.DeviceId)" -eq "$Number" } | Select-Object -First 1
    $d = Get-Disk -Number $Number -ErrorAction SilentlyContinue
    $ssd = "$($pd.MediaType)" -eq 'SSD'
    $stick = ("$($d.BusType)" -in 'USB', 'SD', 'MMC') -and ("$($pd.MediaType)" -ne 'HDD')
    return [bool]($ssd -or $stick)
}

function Invoke-SecureWipe {
    param($Target, [int]$Method)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $flash = Test-IsFlashDisk $Target.Disk.Number
    switch ($Method) {
        0 {
            # Freien Platz überschreiben – vorhandene Dateien bleiben, Reste gelöschter Dateien werden unlesbar
            $null = Assert-ExternalDisk -Number $Target.Disk.Number -Letter $Target.Letter -AllowInternal
            Write-Host "     › Freier Platz auf $($Target.Letter): wird überschrieben (3 Durchgänge: Nullen, Einsen, Zufall) …" -ForegroundColor Gray
            Set-Cancelable $true
            try {
                & cipher.exe "/w:$($Target.Letter):\" 2>&1 | ForEach-Object {
                    $line = "$_".Trim()
                    if ($line -match '0x00|0xFF|Zufall|random') { Write-Host "     › Sicher löschen: $line" -ForegroundColor Gray }
                    if (Test-CancelRequested) { Get-Process -Name cipher -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; throw 'Abgebrochen.' }
                }
            } finally { Set-Cancelable $false }
            $what = "freier Platz auf $($Target.Letter): dreifach überschrieben (cipher /w)"
        }
        1 {
            # Laufwerk vollständig formatieren – Windows überschreibt dabei jeden Sektor mit Nullen
            $null = Assert-ExternalDisk -Number $Target.Disk.Number -Letter $Target.Letter -AllowInternal
            $fs = if ($Target.Part.FileSystem -in 'NTFS', 'exFAT', 'FAT32') { $Target.Part.FileSystem } else { 'exFAT' }
            if ($fs -eq 'FAT32' -and $Target.Part.Size -gt 32GB) { $fs = 'exFAT' }
            Write-Host "     › $($Target.Letter): wird vollständig formatiert und dabei überschrieben (dauert lange) …" -ForegroundColor Gray
            $null = Format-Volume -DriveLetter $Target.Letter -FileSystem $fs -NewFileSystemLabel (Get-CleanLabel $Target.Part.Label $fs) -Full -Force -Confirm:$false -ErrorAction Stop
            $what = "Laufwerk $($Target.Letter): vollständig formatiert und mit Nullen überschrieben ($fs)"
        }
        2 {
            # Ganzen Datenträger nullen (inklusive aller Partitionen), danach eine leere exFAT-Partition anlegen
            $disk = Assert-ExternalDisk -Number $Target.Disk.Number -AllowInternal
            Write-Host "     › Datenträger $($disk.Number) ($($disk.Name)) wird komplett mit Nullen überschrieben (kann Stunden dauern) …" -ForegroundColor Gray
            if ($disk.Style -eq 'RAW') { Initialize-Disk -Number $disk.Number -PartitionStyle MBR -ErrorAction Stop }
            Clear-Disk -Number $disk.Number -RemoveData -RemoveOEM -ZeroOutEntireDisk -Confirm:$false -ErrorAction Stop
            Initialize-Disk -Number $disk.Number -PartitionStyle $(if ($disk.Size -gt 2TB) { 'GPT' } else { 'MBR' }) -ErrorAction SilentlyContinue
            $l = New-FormattedPartition -Disk $disk.Number -Size 0 -FileSystem 'exFAT' -Label 'LEER'
            $what = "Datenträger $($disk.Name) ($(Format-Bytes $disk.Size)) vollständig mit Nullen überschrieben, danach leer mit exFAT eingerichtet$(if ($l) { " ($($l):)" })"
        }
    }
    $dur = Format-Duration $sw.Elapsed.TotalSeconds
    Register-Change -Beschreibung "Sicher gelöscht: $what" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis "Dauer $dur"
    $items = @(
        "Datum: $(Get-Date -Format 'dd.MM.yyyy HH:mm')"
        "Datenträger: $($Target.Disk.Name) (Nummer $($Target.Disk.Number), $(Format-Bytes $Target.Disk.Size))"
        "Verfahren: $what"
        "Dauer: $dur"
    )
    $note = if ($flash) { ' Hinweis: Bei SSDs, USB-Sticks und Speicherkarten verteilt der Speicher-Controller Daten intern um – Überschreiben erreicht nicht garantiert jede Speicherzelle. Für den Verkauf einer SSD zusätzlich »Secure Erase« bzw. »Sanitize« im Programm des Herstellers verwenden (z. B. Samsung Magician, WD Dashboard, Crucial Storage Executive).' } else { '' }
    Remove-FindingByKey "Gelöscht|$($Target.Disk.Number)|$($Target.Letter)"
    Add-Finding 'Extern' OK "Sicher gelöscht: $($Target.Disk.Name)$(if ($Target.Letter -and $Method -lt 2) { " ($($Target.Letter):)" })" -Key "Gelöscht|$($Target.Disk.Number)|$($Target.Letter)" -Items $items `
        -Detail ("Nachweis für Verkauf oder Weitergabe – erscheint auch im Bericht.$note")
    "$what – Dauer $dur."
}

#endregion

#region Werkzeug-Karten

function Add-RecoveryToolFindings {
    param([string]$Category)
    # Quelle: alle Laufwerke mit Buchstaben (auch Windows-Laufwerk – es wird dort nur gelesen); Ziel: ein anderes Laufwerk
    $volumes = @()
    try { $volumes = @(Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and $_.FileSystem -and "$($_.DriveType)" -ne 'CD-ROM' } | Sort-Object DriveLetter) } catch { }
    $all = @(foreach ($v in $volumes) {
            $l = "$($v.DriveLetter)".ToUpperInvariant()
            [pscustomobject]@{ Letter = $l; FileSystem = "$($v.FileSystem)"; Label = ('{0}: {1} – {2}, {3}, frei {4}' -f $l, $(if ($v.FileSystemLabel) { "»$($v.FileSystemLabel)«" } else { '' }), $v.FileSystem, (Format-Bytes $v.Size), (Format-Bytes $v.SizeRemaining)) }
        })
    if ($all.Count -ge 2) {
        $spec = @{
            Text   = 'Sucht gelöschte Dateien mit dem kostenlosen Microsoft-Tool »Windows File Recovery« (wird bei Bedarf aus dem Microsoft Store installiert) und speichert sie auf einem ANDEREN Laufwerk. Wichtig: Auf das betroffene Laufwerk bis dahin nichts mehr speichern – sonst werden die gelöschten Daten überschrieben.'
            Fields = @(
                @{ Name = 'Quelle'; Type = 'Auswahl'; Label = 'Laufwerk, auf dem die Dateien gelöscht wurden'; Items = @($all | ForEach-Object { $_.Label }); Default = 0 }
                @{ Name = 'Ziel'; Type = 'Auswahl'; Label = 'Gerettete Dateien speichern auf'; Items = @($all | ForEach-Object { $_.Label }); Default = 1 }
                @{ Name = 'Art'; Type = 'Auswahl'; Label = 'Was soll gesucht werden?'; Items = @($Script:RecoveryKinds | ForEach-Object { $_.Label }); Default = 0 }
                @{ Name = 'Muster'; Type = 'Text'; Label = 'Suchmuster (nur bei »Eigenes Suchmuster«, z. B. *Urlaub* oder \Users\Name\Documents\)'; Default = '' }
                @{ Name = 'Modus'; Type = 'Auswahl'; Label = 'Suchmodus'; Items = @('Automatisch (empfohlen)', 'Normal – kürzlich gelöscht (NTFS)', 'Gründlich – länger her, formatiert oder beschädigt', 'Signatur – Speicherkarten, Kameras, FAT/exFAT'); Default = 0 }
            )
        }
        Add-Finding $Category Info 'Gelöschte Dateien retten' -Silent -Repeatable -AskParams $spec `
            -Detail 'Holt versehentlich gelöschte Fotos, Dokumente, Videos oder Musik zurück – von Festplatte, SSD, USB-Stick oder Speicherkarte. Gespeichert wird immer auf einem anderen Laufwerk. Je früher, desto besser die Chancen. Mit Fortschritt und Abbrechen.' `
            -FixLabel 'Gelöschte Dateien suchen und retten' -FixData @{ Targets = $all; Spec = $spec } -Fix {
            param($d)
            $o = Resolve-FixParams $d.Spec
            Invoke-FileRecovery -Source (Get-Choice $d.Targets $o.Quelle) -Target (Get-Choice $d.Targets $o.Ziel) -Kind ([int]$o.Art) -Mode ([int]$o.Modus) -Pattern $o.Muster
        }
    }

    # Sicher löschen: Laufwerke auf bearbeitbaren Datenträgern (nie Windows- oder Auslagerungsdatenträger)
    $vols = @(Get-VolumeTargets)
    $disks = @(Get-ExternalDisks -IncludeInternal)
    if ($disks) {
        $entries = @()
        foreach ($v in $vols) { $entries += [pscustomobject]@{ Label = $v.Label; Token = $v.Letter; Disk = $v.Disk; Part = $v.Part; Letter = $v.Letter } }
        foreach ($dk in $disks) { $entries += [pscustomobject]@{ Label = "GANZER $(Get-DiskLabel $dk)"; Token = "$($dk.Number)"; Disk = $dk; Part = $null; Letter = '' } }
        $spec = @{
            Text    = 'Macht Daten unwiederherstellbar – z. B. vor Verkauf oder Weitergabe. »Freien Platz überschreiben« lässt vorhandene Dateien stehen und vernichtet nur Reste bereits gelöschter Dateien. Die anderen Verfahren löschen ALLES. Der Windows-Datenträger lässt sich hier nicht löschen (dafür Windows »Diesen PC zurücksetzen« mit »Laufwerk bereinigen«).'
            Warning = 'ACHTUNG: »Vollständig formatieren« und »Ganzen Datenträger überschreiben« löschen alle Daten endgültig – auch Datenrettungsprogramme können sie danach nicht mehr herstellen.'
            Fields  = @(
                @{ Name = 'Ziel'; Type = 'Auswahl'; Label = 'Laufwerk bzw. ganzer Datenträger'; Items = @($entries | ForEach-Object { $_.Label }); Tokens = @($entries | ForEach-Object { $_.Token }); Default = 0 }
                @{ Name = 'Verfahren'; Type = 'Auswahl'; Label = 'Verfahren'; Items = @('Freien Platz überschreiben (Dateien bleiben erhalten)', 'Laufwerk vollständig formatieren und überschreiben (alles weg)', 'Ganzen Datenträger mit Nullen überschreiben, alle Partitionen (alles weg)'); Default = 0 }
                @{ Name = 'Bestaetigung'; Type = 'Bestaetigung'; Label = 'Zur Bestätigung den Laufwerksbuchstaben bzw. die Datenträgernummer'; From = 'Ziel' }
            )
        }
        Add-Finding $Category Info 'Datenträger sicher löschen' -Silent -Repeatable -AskParams $spec `
            -Detail 'Überschreibt Daten, damit sie sich auch mit Datenrettungsprogrammen nicht wiederherstellen lassen. Mit Nachweis (Datum, Datenträger, Verfahren) im Bericht. Für SSDs zusätzlich »Secure Erase« des Herstellers empfohlen.' `
            -FixLabel 'Datenträger sicher löschen' -FixData @{ Targets = $entries; Spec = $spec } -Fix {
            param($d)
            $o = Resolve-FixParams $d.Spec
            $t = Get-Choice $d.Targets $o.Ziel
            Test-ParamConfirmation $o.Bestaetigung $t.Token
            $m = [int]$o.Verfahren
            if (-not $t.Letter -and $m -lt 2) { throw 'Für einen ganzen Datenträger nur »Ganzen Datenträger mit Nullen überschreiben« möglich – oder ein einzelnes Laufwerk wählen.' }
            if ($t.Letter -and $m -eq 2) { throw 'Zum Überschreiben des ganzen Datenträgers den Eintrag »GANZER Datenträger …« wählen.' }
            Invoke-SecureWipe -Target $t -Method $m
        }
    }
}

#endregion
