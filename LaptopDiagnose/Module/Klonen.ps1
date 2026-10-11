<#
    Datenträger klonen:
      A) Kopie auf Dateiebene (Robocopy) mit anschließendem Vergleich,
      B) Assistent »Windows auf neue SSD umziehen« (Hersteller-Programm oder Systemabbild mit Windows-Bordmitteln),
      C) 1:1-Klon Sektor für Sektor, auch als Abbilddatei (.img) und zurück; Lesefehler werden übersprungen.
    Der laufende Windows-Datenträger ist als Ziel immer gesperrt und für A/C auch als Quelle.
    Für C wird ein kleiner Hilfscode für den direkten Datenträgerzugriff erst beim Start geladen (Windows PowerShell
    kann von sich aus nicht auf Sektoren zugreifen) – Virenscanner können darauf reagieren.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:CloneChunk = 4MB

#region Hilfsfunktionen

function Get-VolumeTargets {
    <# Laufwerke mit Buchstaben und Dateisystem auf bearbeitbaren Datenträgern (extern und interne Zusatzlaufwerke). #>
    foreach ($d in @(Get-ExternalDisks -IncludeInternal)) {
        foreach ($p in @($d.Partitions | Where-Object { $_.Letter -and $_.FileSystem })) {
            [pscustomobject]@{ Disk = $d; Part = $p; Letter = $p.Letter; Used = [math]::Max([double]0, $p.VolSize - $p.Free); Label = Get-PartitionLabel $d $p }
        }
    }
}

function Get-VolumeUsed {
    param([string]$Letter)
    $v = Get-Volume -DriveLetter $Letter -ErrorAction Stop
    return [math]::Max([double]0, [double]$v.Size - [double]$v.SizeRemaining)
}

function Write-CloneProgress {
    param([string]$What, [double]$Done, [double]$Total, $Stopwatch)
    $rate = $Done / [math]::Max(0.1, $Stopwatch.Elapsed.TotalSeconds)
    $rest = if ($rate -gt 0) { ($Total - $Done) / $rate } else { 0 }
    Write-Host ("     › {0}: {1} % ({2} von {3}, {4:N1} MB/s) – noch ca. {5}" -f $What, [math]::Floor(100 * $Done / [math]::Max(1, $Total)), (Format-Bytes $Done), (Format-Bytes $Total), ($rate / 1MB), (Format-Duration $rest)) -ForegroundColor Gray
}

#endregion

#region A) Kopie auf Dateiebene

function Copy-DriveFiles {
    param($Source, $Target, [bool]$Prepare, [bool]$Mirror)
    if ($Source.Letter -eq $Target.Letter) { throw 'Quelle und Ziel müssen verschiedene Laufwerke sein.' }
    $null = Assert-ExternalDisk -Number $Source.Disk.Number -Letter $Source.Letter -AllowInternal
    $null = Assert-ExternalDisk -Number $Target.Disk.Number -Letter $Target.Letter -AllowInternal
    $S = $Source.Letter; $T = $Target.Letter
    $used = Get-VolumeUsed $S
    $tv = Get-Volume -DriveLetter $T -ErrorAction Stop
    $cap = if ($Prepare -or $Mirror) { [double]$tv.Size } else { [double]$tv.SizeRemaining }
    if ($used -gt $cap) { throw "Auf $($T): ist zu wenig Platz: nötig $(Format-Bytes $used), verfügbar $(Format-Bytes $cap)." }
    $note = ''
    if ($Prepare) {
        $fs = $Source.Part.FileSystem
        if ($fs -eq 'FAT32' -and [double]$tv.Size -gt 32GB) { $fs = 'exFAT'; $note = ' Das Ziel ist größer als 32 GB und wurde deshalb mit exFAT statt FAT32 formatiert.' }
        Write-Host "     › $($T): wird mit $fs formatiert …" -ForegroundColor Gray
        $null = Format-Volume -DriveLetter $T -FileSystem $fs -NewFileSystemLabel (Get-CleanLabel $Source.Part.Label $fs) -Force -Confirm:$false -ErrorAction Stop
    }
    $log = Join-Path $env:TEMP ('PCRepairPro_Kopie_{0:yyyyMMdd_HHmmss}.log' -f (Get-Date))
    $mode = if ($Mirror -or $Prepare) { '/MIR' } else { '/E' }
    # Laufwerkswurzeln ohne Anführungszeichen: »"E:\"« würde den Backslash als Escape des Anführungszeichens deuten
    $common = @("$($S):\", "$($T):\", $mode, '/COPY:DAT', '/DCOPY:DAT', '/R:1', '/W:1', '/XJ', '/XD', '"System Volume Information"', '"$RECYCLE.BIN"', '/NP', '/NDL', '/NFL', '/BYTES')
    $baseT = Get-VolumeUsed $T
    Set-Cancelable $true
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $p = Start-Process -FilePath 'robocopy.exe' -ArgumentList ($common + @('/MT:8', "/LOG:`"$log`"")) -NoNewWindow -PassThru
        $last = [datetime]::MinValue
        while (-not $p.HasExited) {
            Start-Sleep -Milliseconds 1000
            if (Test-CancelRequested) { try { $p.Kill() } catch { }; throw 'Abgebrochen – bereits kopierte Dateien bleiben auf dem Ziel.' }
            if (([datetime]::UtcNow - $last).TotalSeconds -ge 15) {
                $last = [datetime]::UtcNow
                $done = [math]::Max([double]0, (Get-VolumeUsed $T) - $(if ($Prepare) { 0 } else { $baseT }))
                Write-CloneProgress "Kopieren $($S): → $($T):" ([math]::Min($done, $used)) $used $sw
            }
        }
        $p.WaitForExit()
        $code = $p.ExitCode
    } finally { Set-Cancelable $false }
    $seconds = $sw.Elapsed.TotalSeconds
    if ($code -ge 8) {
        $tail = (Get-Content -LiteralPath $log -Tail 6 -ErrorAction SilentlyContinue | Where-Object { "$_".Trim() }) -join ' '
        throw "Kopieren mit Fehlern beendet (Robocopy-Code $code). Protokoll: $log. $tail"
    }
    # Vergleich: Robocopy im Nur-Auflisten-Modus – bleibt nichts zu kopieren, sind beide Laufwerke gleich
    Write-Host "     › Vergleich $($S): ↔ $($T): …" -ForegroundColor Gray
    $verifyArgs = @($common | ForEach-Object { $_.Trim('"') }) + @('/L', '/NJH', '/NJS')
    $null = & robocopy.exe @verifyArgs 2>&1
    $same = ($LASTEXITCODE -band 1) -eq 0
    $items = @(
        "Quelle: $($Source.Label)"
        "Ziel: $($Target.Label)"
        "Datenmenge: $(Format-Bytes $used) in $(Format-Duration $seconds) ($('{0:N1}' -f ($used / 1MB / [math]::Max(1, $seconds))) MB/s)"
        "Vergleich: $(if ($same) { 'alle Dateien der Quelle sind auf dem Ziel vorhanden und gleich' } else { 'Unterschiede gefunden – siehe Protokoll' })"
        "Protokoll: $log"
    )
    Remove-FindingByKey "Kopie|$S|$T"
    $sev = if ($same -and $code -lt 4) { 'OK' } else { 'Warnung' }
    Add-Finding 'Extern' $sev "Kopie $($S): → $($T): $(if ($sev -eq 'OK') { 'erfolgreich und geprüft' } else { 'mit Abweichungen' })" -Key "Kopie|$S|$T" -Items $items `
        -Detail ("Kopiert mit Robocopy (Ordnerstruktur, Zeitstempel und Attribute bleiben erhalten). Das Ziel ist nicht bootfähig – für ein startfähiges Windows »Windows auf neue SSD umziehen« verwenden.$note" + $(if (-not $same) { ' Einzelne Dateien konnten nicht kopiert werden (z. B. gesperrt oder Lesefehler) – Details im Protokoll.' } else { '' }))
    "$(Format-Bytes $used) kopiert$(if ($same) { ' und geprüft' } else { ' – mit Abweichungen, siehe Karte' })."
}

#endregion

#region B) Windows auf neue SSD umziehen

function Get-SsdVendorTool {
    param([string]$Name)
    switch -Regex ($Name) {
        'Samsung' { return [pscustomobject]@{ Vendor = 'Samsung'; Tool = 'Samsung Data Migration'; Url = 'https://semiconductor.samsung.com/consumer-storage/support/tools/' } }
        'WD|Western Digital|SanDisk' { return [pscustomobject]@{ Vendor = 'Western Digital / SanDisk'; Tool = 'Acronis True Image for Western Digital'; Url = 'https://www.westerndigital.com/support' } }
        'Crucial|Micron|CT\d{3,4}' { return [pscustomobject]@{ Vendor = 'Crucial'; Tool = 'Acronis True Image for Crucial'; Url = 'https://www.crucial.com/support/ssd' } }
        'Kingston' { return [pscustomobject]@{ Vendor = 'Kingston'; Tool = 'Acronis True Image for Kingston'; Url = 'https://www.kingston.com/en/support/technical/acronis-download' } }
        'Seagate' { return [pscustomobject]@{ Vendor = 'Seagate'; Tool = 'DiscWizard'; Url = 'https://www.seagate.com/support/downloads/discwizard/' } }
    }
    return $null
}

function Get-SystemDiskUsage {
    $sys = "$env:SystemDrive".TrimEnd(':', '\')
    $used = Get-VolumeUsed $sys
    # Windows-Datenträger: zusätzlich EFI-, Reserviert- und Wiederherstellungspartitionen (ca. 1–2 GB)
    return $used + 2GB
}

function Invoke-SystemMigration {
    param($Target, [int]$Way, $ImageTarget)
    $disk = Assert-ExternalDisk -Number $Target.Number -AllowInternal
    $need = Get-SystemDiskUsage
    if ($disk.Size -lt $need) { throw "Die neue SSD ($(Format-Bytes $disk.Size)) ist zu klein: Windows belegt mit allen Dateien ca. $(Format-Bytes $need)." }
    $vendor = Get-SsdVendorTool $disk.Name
    $steps = @()
    if ($Way -eq 0) {
        if ($vendor) {
            Start-Process $vendor.Url
            $steps += "1. Auf der geöffneten Seite »$($vendor.Tool)« herunterladen und installieren (kostenlos für $($vendor.Vendor)-SSDs)."
        } else {
            $steps += '1. Für diese SSD wurde kein Hersteller-Programm erkannt. Viele Hersteller bieten auf ihrer Support-Seite ein kostenloses Umzugsprogramm an; sonst Weg 2 (Systemabbild) wählen.'
        }
        $steps += @(
            "2. Im Programm als Quelle das Windows-Laufwerk ($($env:SystemDrive)) und als Ziel »$($disk.Name)« wählen und das Klonen starten."
            '3. Danach den Computer ausschalten, die neue SSD einbauen bzw. im BIOS/UEFI als Startlaufwerk wählen und starten.'
            '4. Erst wenn Windows von der neuen SSD einwandfrei startet, das alte Laufwerk löschen oder weiterverwenden.'
        )
        $title = "Umzug auf $($disk.Name): $(if ($vendor) { "mit $($vendor.Tool)" } else { 'Anleitung' })"
    } else {
        if (-not $ImageTarget) { throw 'Für das Systemabbild ein Ziellaufwerk wählen.' }
        if ($ImageTarget.Disk.Number -eq $disk.Number) { throw 'Das Systemabbild darf nicht auf der neuen SSD gespeichert werden – sie wird bei der Wiederherstellung überschrieben.' }
        $free = [double](Get-Volume -DriveLetter $ImageTarget.Letter -ErrorAction Stop).SizeRemaining
        if ($free -lt $need) { throw "Auf $($ImageTarget.Letter): ist zu wenig Platz für das Systemabbild (nötig ca. $(Format-Bytes $need), frei $(Format-Bytes $free))." }
        if ($ImageTarget.Part.FileSystem -ne 'NTFS') { throw "Ein Systemabbild braucht ein NTFS-Laufwerk – $($ImageTarget.Letter): ist $($ImageTarget.Part.FileSystem). Mit »In NTFS umwandeln« oder »Datenträger formatieren« vorbereiten." }
        Write-Host "     › Systemabbild wird auf $($ImageTarget.Letter): erstellt (dauert je nach Datenmenge 15–90 Minuten) …" -ForegroundColor Gray
        Set-Cancelable $true
        try {
            & wbadmin.exe start backup "-backupTarget:$($ImageTarget.Letter):" "-include:$($env:SystemDrive)" -allCritical -quiet 2>&1 | ForEach-Object {
                $line = "$_".Trim()
                if ($line -match '\(\d+%\)|\d+ ?%') { Write-Host "     › Systemabbild: $line" -ForegroundColor Gray }
                if (Test-CancelRequested) { $null = & wbadmin.exe stop job -quiet 2>&1; throw 'Abgebrochen.' }
            }
            if ($LASTEXITCODE -ne 0) { throw "Das Systemabbild konnte nicht erstellt werden (Code $LASTEXITCODE). Windows Home unterstützt Systemabbilder nicht immer – dann Weg 1 (Hersteller-Programm) wählen." }
        } finally { Set-Cancelable $false }
        Register-Change -Beschreibung "Systemabbild für den SSD-Umzug erstellt auf $($ImageTarget.Letter):" -Typ 'Protokoll' -NichtUmkehrbar
        $steps += @(
            "1. Systemabbild liegt auf $($ImageTarget.Letter): im Ordner »WindowsImageBackup« – dieses Laufwerk aufbewahren."
            '2. Windows-Installationsstick erstellen (Media Creation Tool von microsoft.com/software-download).'
            "3. Computer ausschalten, die neue SSD ($($disk.Name)) einbauen; das alte Laufwerk möglichst abklemmen."
            "4. Vom Installationsstick starten › »Computerreparaturoptionen« › »Problembehandlung« › »Systemimage-Wiederherstellung« und das Abbild von $($ImageTarget.Letter): wählen."
            '5. Nach dem ersten Start den übrigen Platz mit »Partitionsgröße ändern« bzw. der Datenträgerverwaltung nutzen.'
        )
        $title = "Systemabbild für den Umzug auf $($disk.Name) erstellt"
    }
    Remove-FindingByKey 'SsdUmzug'
    Add-Finding 'Extern' Info $title -Key 'SsdUmzug' -Items $steps -Detail "Windows belegt ca. $(Format-Bytes $need); die neue SSD hat $(Format-Bytes $disk.Size). Vor dem Umzug eine Datensicherung der wichtigsten Dateien anlegen."
    "Anleitung siehe Karte »$title«."
}

#endregion

#region C) 1:1-Klon Sektor für Sektor

$Script:RawDiskSource = @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class PcrpRawDisk
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(SafeFileHandle handle, uint code, IntPtr inBuffer, uint inSize, IntPtr outBuffer, uint outSize, out uint returned, IntPtr overlapped);

    const uint GenericRead = 0x80000000, GenericWrite = 0x40000000, ShareReadWrite = 3, OpenExisting = 3;
    const uint LockVolumeCode = 0x00090018, DismountVolumeCode = 0x00090020;

    public static FileStream OpenDisk(int number, bool write)
    {
        SafeFileHandle h = CreateFile(@"\\.\PhysicalDrive" + number, write ? (GenericRead | GenericWrite) : GenericRead, ShareReadWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (h.IsInvalid) throw new IOException("Datenträger " + number + " lässt sich nicht öffnen (Fehler " + Marshal.GetLastWin32Error() + ").");
        return new FileStream(h, write ? FileAccess.ReadWrite : FileAccess.Read, 1, false);
    }

    public static SafeFileHandle LockVolume(string letter)
    {
        SafeFileHandle h = CreateFile(@"\\.\" + letter + ":", GenericRead | GenericWrite, ShareReadWrite, IntPtr.Zero, OpenExisting, 0, IntPtr.Zero);
        if (h.IsInvalid) throw new IOException("Laufwerk " + letter + ": lässt sich nicht öffnen.");
        uint r;
        if (!DeviceIoControl(h, LockVolumeCode, IntPtr.Zero, 0, IntPtr.Zero, 0, out r, IntPtr.Zero))
        {
            h.Dispose();
            throw new IOException("Laufwerk " + letter + ": wird noch verwendet – alle Dateien, Fenster und Programme darauf schließen.");
        }
        DeviceIoControl(h, DismountVolumeCode, IntPtr.Zero, 0, IntPtr.Zero, 0, out r, IntPtr.Zero);
        return h;
    }
}
'@

function Initialize-RawDisk {
    if ('PcrpRawDisk' -as [type]) { return }
    Write-Host '     › Hilfscode für den direkten Datenträgerzugriff wird geladen (Virenscanner können darauf reagieren) …' -ForegroundColor Gray
    Add-Type -TypeDefinition $Script:RawDiskSource -ErrorAction Stop
}

function Open-RawSource {
    param([int]$Disk, [string]$File)
    if ($File) { return New-Object IO.FileStream($File, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read, 1MB, [IO.FileOptions]::SequentialScan) }
    return [PcrpRawDisk]::OpenDisk($Disk, $false)
}

function Open-RawTarget {
    param([int]$Disk, [string]$File)
    if ($File) { return New-Object IO.FileStream($File, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None, 1MB, [IO.FileOptions]::WriteThrough) }
    return [PcrpRawDisk]::OpenDisk($Disk, $true)
}

function Read-ChunkTolerant {
    <# Liest einen Abschnitt; bei Lesefehlern sektorweise weiter, unlesbare Sektoren werden mit Nullen gefüllt. #>
    param($Stream, [byte[]]$Buffer, [long]$Offset, [int]$Length, [int]$Sector, $BadList)
    try {
        $Stream.Position = $Offset
        $n = 0
        while ($n -lt $Length) { $r = $Stream.Read($Buffer, $n, $Length - $n); if ($r -le 0) { throw 'Ende' }; $n += $r }
        return 0
    } catch {
        $bad = 0
        for ($o = 0; $o -lt $Length; $o += $Sector) {
            try { $Stream.Position = $Offset + $o; if ($Stream.Read($Buffer, $o, $Sector) -ne $Sector) { throw 'kurz' } }
            catch { [Array]::Clear($Buffer, $o, $Sector); $bad++; if ($BadList.Count -lt 50) { $BadList.Add($Offset + $o) } }
        }
        return $bad
    }
}

function Invoke-RawCopy {
    <#
        Kopiert Sektor für Sektor: Datenträger → Datenträger, Datenträger → Datei oder Datei → Datenträger.
        Ziel-Laufwerke werden vorher gesperrt und ausgehängt (bzw. der Ziel-Datenträger offline geschaltet).
    #>
    param([int]$SourceDisk = -1, [string]$SourceFile, [int]$TargetDisk = -1, [string]$TargetFile, [bool]$Verify = $true)
    Initialize-RawDisk
    $src = $null; $tgt = $null; $tDisk = $null; $sDisk = $null
    if ($SourceDisk -ge 0) { $sDisk = Assert-ExternalDisk -Number $SourceDisk -AllowInternal }
    if ($TargetDisk -ge 0) { $tDisk = Assert-ExternalDisk -Number $TargetDisk -AllowInternal }
    if ($sDisk -and $tDisk -and $sDisk.Number -eq $tDisk.Number) { throw 'Quelle und Ziel müssen verschiedene Datenträger sein.' }
    $size = if ($sDisk) { [long]$sDisk.Size } else { [long](Get-Item -LiteralPath $SourceFile -ErrorAction Stop).Length }
    $sector = if ($sDisk) { $sDisk.SectorSize } elseif ($tDisk) { $tDisk.SectorSize } else { 512 }
    if ($tDisk -and $tDisk.Size -lt $size) { throw "Das Ziel ($(Format-Bytes $tDisk.Size)) ist kleiner als die Quelle ($(Format-Bytes $size)) – ein 1:1-Klon braucht ein mindestens gleich großes Ziel." }
    if ($TargetFile) {
        $root = [IO.Path]::GetPathRoot($TargetFile)
        if ($sDisk -and ($sDisk.Partitions | Where-Object { $_.Letter -and $root -like "$($_.Letter):*" })) { throw 'Die Abbilddatei darf nicht auf dem Quell-Datenträger liegen.' }
        $free = [double](New-Object IO.DriveInfo($root)).AvailableFreeSpace
        if ($free -lt $size) { throw "Auf $root ist zu wenig Platz für die Abbilddatei (nötig $(Format-Bytes $size), frei $(Format-Bytes $free))." }
    }
    if ($SourceFile -and $tDisk -and ($tDisk.Partitions | Where-Object { $_.Letter -and $SourceFile -like "$($_.Letter):*" })) { throw 'Die Abbilddatei liegt auf dem Ziel-Datenträger – sie würde beim Zurückschreiben überschrieben.' }

    $locks = New-Object System.Collections.Generic.List[object]
    $wentOffline = $false; $sourceLocked = $true
    $bad = 0L; $badList = New-Object System.Collections.Generic.List[long]; $badChunks = @{}
    $mismatch = 0L; $canceled = $false; $copied = 0L
    Set-Cancelable $true
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        # Ziel vorbereiten: Laufwerke sperren und aushängen, damit Windows nicht dazwischen schreibt
        if ($tDisk) {
            if ($tDisk.IsInternal) { try { Set-Disk -Number $tDisk.Number -IsOffline $true -ErrorAction Stop; $wentOffline = $true } catch { } }
            if (-not $wentOffline) { foreach ($p in @($tDisk.Partitions | Where-Object { $_.Letter })) { $locks.Add([PcrpRawDisk]::LockVolume($p.Letter)) } }
        }
        # Quelle möglichst sperren, damit sich während des Kopierens nichts ändert (sonst wird trotzdem gelesen)
        if ($sDisk) { foreach ($p in @($sDisk.Partitions | Where-Object { $_.Letter })) { try { $locks.Add([PcrpRawDisk]::LockVolume($p.Letter)) } catch { $sourceLocked = $false } } }

        $src = Open-RawSource -Disk $SourceDisk -File $SourceFile
        $tgt = Open-RawTarget -Disk $(if ($tDisk) { $tDisk.Number } else { -1 }) -File $TargetFile
        $buf = New-Object byte[] ($Script:CloneChunk)
        $last = [datetime]::MinValue
        for ($pos = 0L; $pos -lt $size; $pos += $Script:CloneChunk) {
            if (Test-CancelRequested) { $canceled = $true; break }
            $len = [int][math]::Min([long]$Script:CloneChunk, $size - $pos)
            if ($sDisk) { $b = Read-ChunkTolerant $src $buf $pos $len $sector $badList; if ($b) { $bad += $b; $badChunks[$pos] = $true } }
            else { $src.Position = $pos; $n = 0; while ($n -lt $len) { $r = $src.Read($buf, $n, $len - $n); if ($r -le 0) { break }; $n += $r } }
            $tgt.Position = $pos
            $tgt.Write($buf, 0, $len)
            $copied = $pos + $len
            if (([datetime]::UtcNow - $last).TotalSeconds -ge 15) { $last = [datetime]::UtcNow; Write-CloneProgress 'Klonen' $copied $size $sw }
        }
        $tgt.Flush()
        $copySeconds = $sw.Elapsed.TotalSeconds
        # Vergleich: Abschnitt für Abschnitt die Prüfsummen von Quelle und Ziel
        if ($Verify -and -not $canceled) {
            $tgt.Dispose(); $tgt = $null
            $chk = if ($TargetFile) { New-Object IO.FileStream($TargetFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read, 1MB) } else { [PcrpRawDisk]::OpenDisk($tDisk.Number, $false) }
            $md5 = [Security.Cryptography.MD5]::Create()
            $buf2 = New-Object byte[] ($Script:CloneChunk)
            $sw.Restart(); $last = [datetime]::MinValue
            try {
                for ($pos = 0L; $pos -lt $size; $pos += $Script:CloneChunk) {
                    if (Test-CancelRequested) { $canceled = $true; break }
                    if ($badChunks.ContainsKey($pos)) { continue }
                    $len = [int][math]::Min([long]$Script:CloneChunk, $size - $pos)
                    foreach ($pair in @(@($src, $buf), @($chk, $buf2))) {
                        $pair[0].Position = $pos; $n = 0
                        while ($n -lt $len) { $r = $pair[0].Read($pair[1], $n, $len - $n); if ($r -le 0) { break }; $n += $r }
                    }
                    if ([Convert]::ToBase64String($md5.ComputeHash($buf, 0, $len)) -ne [Convert]::ToBase64String($md5.ComputeHash($buf2, 0, $len))) { $mismatch++ }
                    if (([datetime]::UtcNow - $last).TotalSeconds -ge 15) { $last = [datetime]::UtcNow; Write-CloneProgress 'Vergleichen' ($pos + $len) $size $sw }
                }
            } finally { $chk.Dispose(); $md5.Dispose() }
        }
    } finally {
        Set-Cancelable $false
        if ($src) { $src.Dispose() }
        if ($tgt) { $tgt.Dispose() }
        foreach ($l in $locks) { try { $l.Dispose() } catch { } }
        if ($wentOffline) { try { Set-Disk -Number $tDisk.Number -IsOffline $false -ErrorAction Stop } catch { } }
        if ($tDisk) { try { Update-Disk -Number $tDisk.Number -ErrorAction SilentlyContinue } catch { } }
    }
    return [pscustomobject]@{
        Size = $size; Copied = $copied; Seconds = $copySeconds; Bad = $bad; BadList = $badList.ToArray(); Mismatch = $mismatch
        Verified = ($Verify -and -not $canceled); Canceled = $canceled; SourceLocked = $sourceLocked; Sector = $sector
    }
}

function Add-RawCopyResult {
    param($Result, [string]$What, [string]$Key, [string]$ExtraNote)
    $r = $Result
    $items = @(
        "Kopiert: $(Format-Bytes $r.Copied) von $(Format-Bytes $r.Size) in $(Format-Duration $r.Seconds) ($('{0:N1}' -f ($r.Copied / 1MB / [math]::Max(1, $r.Seconds))) MB/s)"
        "Unlesbare Sektoren: $($r.Bad)$(if ($r.Bad) { " (mit Nullen gefüllt; erste Positionen: $((@($r.BadList) | Select-Object -First 5 | ForEach-Object { Format-Bytes $_ }) -join ', '))" })"
        "Vergleich: $(if ($r.Verified) { if ($r.Mismatch) { "$($r.Mismatch) abweichende Abschnitte" } else { 'Quelle und Ziel sind identisch' } } else { 'nicht durchgeführt' })"
    )
    if (-not $r.SourceLocked) { $items += 'Hinweis: Die Quelle ließ sich nicht sperren (geöffnete Dateien) – Änderungen während des Kopierens können fehlen.' }
    $sev = if ($r.Canceled) { 'Info' } elseif ($r.Mismatch -or $r.Bad) { 'Warnung' } else { 'OK' }
    $state = if ($r.Canceled) { 'abgebrochen' } elseif ($r.Mismatch) { 'mit Abweichungen' } elseif ($r.Bad) { "mit $($r.Bad) unlesbaren Sektoren" } else { 'erfolgreich' }
    Remove-FindingByKey $Key
    Add-Finding 'Extern' $sev "$($What): $state" -Key $Key -Items $items -Detail $ExtraNote
    "$What $state."
}

#endregion

#region Werkzeug-Karten

function Add-CloneToolFindings {
    param([string]$Category)
    $vols = @(Get-VolumeTargets)
    $disks = @(Get-ExternalDisks -IncludeInternal)

    # A) Kopie auf Dateiebene
    if ($vols.Count -ge 2) {
        $spec = @{
            Text    = 'Kopiert den gesamten Inhalt eines Laufwerks auf ein anderes (Ordnerstruktur, Zeitstempel, Attribute) und vergleicht danach beide. Gut für Daten, Fotos und Sicherungen – das Ergebnis ist nicht bootfähig.'
            Warning = 'Auf dem Ziel werden gleichnamige Dateien überschrieben. Mit »vorher formatieren« bzw. »exakte Kopie« werden dort zusätzlich alle anderen Daten gelöscht.'
            Fields  = @(
                @{ Name = 'Quelle'; Type = 'Auswahl'; Label = 'Quelle'; Items = @($vols | ForEach-Object { "$($_.Label) – belegt $(Format-Bytes $_.Used)" }); Default = 0 }
                @{ Name = 'Ziel'; Type = 'Auswahl'; Label = 'Ziel'; Items = @($vols | ForEach-Object { "$($_.Label) – frei $(Format-Bytes $_.Part.Free)" }); Tokens = @($vols | ForEach-Object { $_.Letter }); Default = [math]::Min(1, $vols.Count - 1) }
                @{ Name = 'Formatieren'; Type = 'Haken'; Label = 'Ziel vorher formatieren (gleiches Dateisystem und gleicher Name wie die Quelle)'; Default = $false }
                @{ Name = 'Spiegeln'; Type = 'Haken'; Label = 'Exakte Kopie: Dateien auf dem Ziel löschen, die es in der Quelle nicht gibt'; Default = $false }
                @{ Name = 'Bestaetigung'; Type = 'Bestaetigung'; Label = 'Zur Bestätigung den Laufwerksbuchstaben des Ziels'; From = 'Ziel' }
            )
        }
        Add-Finding $Category Info 'Laufwerk kopieren (Dateiebene)' -Silent -Repeatable -AskParams $spec `
            -Detail 'Kopiert alle Dateien eines Laufwerks mit dem Windows-Programm Robocopy auf ein anderes und prüft danach, ob alles angekommen ist. Mit Fortschritt, Restzeit und Abbrechen.' `
            -FixLabel 'Laufwerk auf ein anderes kopieren' -FixData @{ Targets = $vols; Spec = $spec } -Fix {
            param($d)
            $o = Resolve-FixParams $d.Spec
            $s = (Get-Choice $d.Targets $o.Quelle); $t = (Get-Choice $d.Targets $o.Ziel)
            Test-ParamConfirmation $o.Bestaetigung $t.Letter
            Copy-DriveFiles -Source $s -Target $t -Prepare ([bool]$o.Formatieren) -Mirror ([bool]$o.Spiegeln)
        }
    }

    # B) Windows auf neue SSD umziehen
    $ssd = @($disks | Where-Object { $_.Size -ge 64GB })
    if ($ssd) {
        $imgVols = @($vols)
        $spec = @{
            Text   = 'Zieht Windows samt Programmen und Daten auf eine neue SSD um. Weg 1 (empfohlen): das kostenlose Umzugsprogramm des SSD-Herstellers. Weg 2: Systemabbild mit Windows-Bordmitteln erstellen und vom Installationsstick auf die neue SSD zurückspielen. Die neue SSD vorher per USB-Adapter oder zweitem Steckplatz anschließen.'
            Fields = @(
                @{ Name = 'Ziel'; Type = 'Auswahl'; Label = 'Neue SSD'; Items = @($ssd | ForEach-Object { Get-DiskLabel $_ }); Default = 0 }
                @{ Name = 'Weg'; Type = 'Auswahl'; Label = 'Vorgehen'; Items = @('Weg 1: Umzugsprogramm des Herstellers öffnen (empfohlen)', 'Weg 2: Systemabbild mit Windows-Bordmitteln erstellen'); Default = 0 }
                @{ Name = 'Abbild'; Type = 'Auswahl'; Label = 'Nur Weg 2: Laufwerk für das Systemabbild (NTFS, nicht die neue SSD)'; Items = @('–') + @($imgVols | ForEach-Object { "$($_.Label) – frei $(Format-Bytes $_.Part.Free)" }); Default = 0 }
            )
        }
        Add-Finding $Category Info 'Windows auf neue SSD umziehen' -Silent -Repeatable -AskParams $spec `
            -Detail "Assistent für den Umzug des Windows-Laufwerks: prüft, ob die neue SSD groß genug ist, öffnet das passende Hersteller-Programm (Samsung, WD/SanDisk, Crucial, Kingston, Seagate) oder erstellt ein Systemabbild und führt Schritt für Schritt durch die Wiederherstellung." `
            -FixLabel 'Umzug auf neue SSD vorbereiten' -FixData @{ Targets = $ssd; Volumes = $imgVols; Spec = $spec } -Fix {
            param($d)
            $o = Resolve-FixParams $d.Spec
            $img = if ([int]$o.Abbild -gt 0) { (Get-Choice $d.Volumes ([int]$o.Abbild - 1)) } else { $null }
            Invoke-SystemMigration -Target (Get-Choice $d.Targets $o.Ziel) -Way ([int]$o.Weg) -ImageTarget $img
        }
    }

    # C) 1:1-Klon und Abbilddateien
    $cDetail = ' Nutzt direkten Sektorzugriff: Der dafür nötige Hilfscode wird erst beim Start geladen – Virenscanner können darauf reagieren.'
    if ($disks.Count -ge 2) {
        $spec = @{
            Text    = 'Kopiert einen Datenträger Sektor für Sektor auf einen anderen – mit allen Partitionen, bootfähig. Lesefehler werden übersprungen und protokolliert (Rettung defekter Sticks und Karten). Das Ziel muss mindestens so groß sein wie die Quelle; zusätzlicher Platz bleibt »nicht zugeordnet«.'
            Warning = 'ACHTUNG: ALLE Daten auf dem Ziel-Datenträger werden überschrieben. Solange Original und Klon gleichzeitig angeschlossen sind, schaltet Windows einen der beiden offline (gleiche Kennung).'
            Fields  = @(
                @{ Name = 'Quelle'; Type = 'Auswahl'; Label = 'Quelle'; Items = @($disks | ForEach-Object { Get-DiskLabel $_ }); Default = 0 }
                @{ Name = 'Ziel'; Type = 'Auswahl'; Label = 'Ziel'; Items = @($disks | ForEach-Object { Get-DiskLabel $_ }); Tokens = @($disks | ForEach-Object { "$($_.Number)" }); Default = 1 }
                @{ Name = 'Vergleich'; Type = 'Haken'; Label = 'Danach Quelle und Ziel vergleichen (doppelte Dauer, empfohlen)'; Default = $true }
                @{ Name = 'Bestaetigung'; Type = 'Bestaetigung'; Label = 'Zur Bestätigung die Datenträgernummer des Ziels'; From = 'Ziel' }
            )
        }
        Add-Finding $Category Info '1:1-Klon (Sektor für Sektor)' -Silent -Repeatable -AskParams $spec `
            -Detail ('Exakte Kopie eines ganzen Datenträgers inklusive Partitionen und Startfähigkeit – z. B. Stick auf Stick oder alte auf neue externe Festplatte. Der laufende Windows-Datenträger kann nicht geklont werden (dafür »Windows auf neue SSD umziehen«).' + $cDetail) `
            -FixLabel 'Datenträger 1:1 klonen (überschreibt das Ziel)' -FixData @{ Targets = $disks; Spec = $spec } -Fix {
            param($d)
            $o = Resolve-FixParams $d.Spec
            $s = (Get-Choice $d.Targets $o.Quelle); $t = (Get-Choice $d.Targets $o.Ziel)
            Test-ParamConfirmation $o.Bestaetigung "$($t.Number)"
            $r = Invoke-RawCopy -SourceDisk $s.Number -TargetDisk $t.Number -Verify ([bool]$o.Vergleich)
            Register-Change -Beschreibung "1:1-Klon: $($s.Name) → $($t.Name)" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis 'Alle vorherigen Daten auf dem Ziel wurden überschrieben.'
            Add-RawCopyResult $r "1:1-Klon $($s.Name) → $($t.Name)" 'Klon' 'Original und Klon haben dieselbe Datenträgerkennung: Sind beide gleichzeitig angeschlossen, schaltet Windows einen offline – nach dem Abziehen des anderen ist alles normal. Zusätzlicher Platz auf einem größeren Ziel lässt sich mit »Partition erstellen« bzw. »Partitionsgröße ändern« nutzen.'
        }
    }
    if ($disks) {
        $spec = @{
            Text   = 'Speichert einen ganzen Datenträger Sektor für Sektor als Abbilddatei (.img) – z. B. die SD-Karte eines Raspberry Pi oder einen Stick vor dem Formatieren. Lesefehler werden übersprungen. Die Datei ist so groß wie der Datenträger.'
            Fields = @(
                @{ Name = 'Quelle'; Type = 'Auswahl'; Label = 'Datenträger'; Items = @($disks | ForEach-Object { Get-DiskLabel $_ }); Default = 0 }
                @{ Name = 'Datei'; Type = 'Datei'; Label = 'Abbilddatei speichern unter'; Mode = 'Speichern'; Filter = 'Abbilddatei (*.img)|*.img'; Default = '' }
                @{ Name = 'Vergleich'; Type = 'Haken'; Label = 'Danach vergleichen'; Default = $true }
            )
        }
        Add-Finding $Category Info 'Abbilddatei erstellen (.img)' -Silent -Repeatable -AskParams $spec `
            -Detail ('Sichert einen kompletten Datenträger als Datei, die sich später mit »Abbilddatei zurückschreiben« 1:1 wiederherstellen lässt (auch mit Programmen wie dem Raspberry Pi Imager).' + $cDetail) `
            -FixLabel 'Datenträger als Abbilddatei sichern' -FixData @{ Targets = $disks; Spec = $spec } -Fix {
            param($d)
            $o = Resolve-FixParams $d.Spec
            $s = (Get-Choice $d.Targets $o.Quelle)
            $file = "$($o.Datei)".Trim().Trim('"')
            if (-not $file) { throw 'Bitte einen Speicherort für die Abbilddatei angeben.' }
            if ([IO.Path]::GetExtension($file) -eq '') { $file += '.img' }
            $r = Invoke-RawCopy -SourceDisk $s.Number -TargetFile $file -Verify ([bool]$o.Vergleich)
            Register-Change -Beschreibung "Abbilddatei erstellt: $($s.Name) → $file" -Typ 'Protokoll' -NichtUmkehrbar
            Add-RawCopyResult $r "Abbilddatei $([IO.Path]::GetFileName($file))" "Abbild|$file" "Gespeichert unter $file."
        }
        $spec = @{
            Text    = 'Schreibt eine Abbilddatei (.img) Sektor für Sektor auf einen Datenträger zurück – z. B. ein Raspberry-Pi-Image auf eine SD-Karte. Der Datenträger muss mindestens so groß sein wie die Datei.'
            Warning = 'ACHTUNG: ALLE Daten auf dem gewählten Datenträger werden überschrieben.'
            Fields  = @(
                @{ Name = 'Datei'; Type = 'Datei'; Label = 'Abbilddatei'; Mode = 'Oeffnen'; Filter = 'Abbilddateien (*.img;*.bin;*.iso)|*.img;*.bin;*.iso|Alle Dateien (*.*)|*.*'; Default = '' }
                @{ Name = 'Ziel'; Type = 'Auswahl'; Label = 'Ziel-Datenträger'; Items = @($disks | ForEach-Object { Get-DiskLabel $_ }); Tokens = @($disks | ForEach-Object { "$($_.Number)" }); Default = 0 }
                @{ Name = 'Vergleich'; Type = 'Haken'; Label = 'Danach vergleichen'; Default = $true }
                @{ Name = 'Bestaetigung'; Type = 'Bestaetigung'; Label = 'Zur Bestätigung die Datenträgernummer des Ziels'; From = 'Ziel' }
            )
        }
        Add-Finding $Category Info 'Abbilddatei zurückschreiben' -Silent -Repeatable -AskParams $spec `
            -Detail ('Stellt einen Datenträger aus einer Abbilddatei wieder her bzw. schreibt ein Betriebssystem-Image (z. B. Raspberry Pi, Linux) auf Stick oder Karte.' + $cDetail) `
            -FixLabel 'Abbilddatei auf Datenträger schreiben (überschreibt das Ziel)' -FixData @{ Targets = $disks; Spec = $spec } -Fix {
            param($d)
            $o = Resolve-FixParams $d.Spec
            $t = (Get-Choice $d.Targets $o.Ziel)
            Test-ParamConfirmation $o.Bestaetigung "$($t.Number)"
            $file = "$($o.Datei)".Trim().Trim('"')
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Abbilddatei nicht gefunden: $file" }
            $r = Invoke-RawCopy -SourceFile $file -TargetDisk $t.Number -Verify ([bool]$o.Vergleich)
            Register-Change -Beschreibung "Abbilddatei zurückgeschrieben: $file → $($t.Name)" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis 'Alle vorherigen Daten auf dem Ziel wurden überschrieben.'
            Add-RawCopyResult $r "Zurückschreiben auf $($t.Name)" "Zurueck|$($t.Number)" 'Der Datenträger enthält jetzt genau den Inhalt der Abbilddatei. Zusätzlicher Platz auf einem größeren Datenträger bleibt »nicht zugeordnet«.'
        }
    }
}

#endregion
