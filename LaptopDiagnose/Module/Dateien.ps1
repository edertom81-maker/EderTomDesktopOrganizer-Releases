<#
    Datei-Werkzeuge im Bereich »Speicherfresser«: doppelte Dateien, leere Ordner, große Ordner.
    Gesucht wird nur nach Auswahl; gelöscht wird nur, was angekreuzt ist – in den Papierkorb. Was nicht in den
    Papierkorb passt, wird nie stillschweigend endgültig gelöscht, sondern getrennt zur Bestätigung angeboten.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:HelperFileNames = @('desktop.ini', 'thumbs.db', '.ds_store', 'ehthumbs.db')
$Script:SkipDirNames = @('$recycle.bin', 'system volume information', '.git', 'node_modules', '__pycache__', '.venv', 'appdata')

#region ---------- Orte und Schutz ----------

function Get-UserDataRoots {
    <# Benutzerordner, die durchsucht werden: Dokumente (lokal und ggf. OneDrive), Bilder, Videos, Musik, Desktop, Downloads. #>
    $list = @(
        [Environment]::GetFolderPath('MyDocuments')
        (Join-Path $env:USERPROFILE 'Documents')
        [Environment]::GetFolderPath('MyPictures')
        [Environment]::GetFolderPath('MyVideos')
        [Environment]::GetFolderPath('MyMusic')
        [Environment]::GetFolderPath('Desktop')
        (Get-DownloadsFolder)
    )
    $seen = @{}
    foreach ($p in $list) {
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { continue }
        $full = (Get-Item -LiteralPath $p).FullName.TrimEnd('\')
        if ($seen.ContainsKey($full.ToLowerInvariant())) { continue }
        $seen[$full.ToLowerInvariant()] = $true
        $full
    }
}

function Get-ProtectedFolders {
    <# Ordner, die nie gelöscht werden dürfen (auch nicht als Ganzes): System, Programme, Profil und die Benutzerordner selbst. #>
    $p = @($env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA,
        $(if ($env:SystemDrive) { Join-Path $env:SystemDrive 'Users' }), $env:OneDrive, $env:OneDriveConsumer, $env:OneDriveCommercial)
    $p += @(Get-UserDataRoots)
    $p += foreach ($d in [IO.DriveInfo]::GetDrives()) { $d.RootDirectory.FullName }
    @($p | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') } | Select-Object -Unique)
}

function Test-InsideSystemArea {
    <# Liegt der Pfad in einem Windows-, Programm- oder AppData-Bereich? Dort wird nichts gelöscht. #>
    param([string]$Path)
    $p = $Path.TrimEnd('\') + '\'
    foreach ($root in @($env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA, (Join-Path $env:USERPROFILE 'AppData')) | Where-Object { $_ }) {
        if ($p -like ($root.TrimEnd('\') + '\*')) { return $true }
    }
    return $false
}

function Test-DeletableFolder {
    param([string]$Path, [string[]]$Protected)
    $t = $Path.TrimEnd('\')
    if ($Protected | Where-Object { $_ -ieq $t }) { return $false }
    return -not (Test-InsideSystemArea $t)
}

function Resolve-ScanRoots {
    param($Data)
    if ($Data -and $Data.Folder) { return @((Get-Item -LiteralPath $Data.Folder -ErrorAction Stop).FullName.TrimEnd('\')) }
    return @(Get-UserDataRoots)
}

function Read-FolderChoice {
    <# Konsole: Standard-Orte oder eigener Ordner. #>
    $a = Read-Host '   Benutzerordner durchsuchen [Enter] oder Pfad eines anderen Ordners bzw. Laufwerks eingeben'
    if ([string]::IsNullOrWhiteSpace($a)) { return @{ Folder = $null } }
    if (-not (Test-Path -LiteralPath $a.Trim('"'))) { throw "Ordner nicht gefunden: $a" }
    return @{ Folder = $a.Trim('"') }
}

#endregion

#region ---------- Löschen (Papierkorb, sonst nur nach ausdrücklicher Bestätigung) ----------

function Get-RecycleCapacity {
    <# Größe des Papierkorbs auf dem Laufwerk (Bytes); 0 = kein Papierkorb (z. B. USB-Stick, Netzlaufwerk). #>
    param([string]$Path)
    if ($Path -notmatch '^([A-Za-z]):\\') { return [double]0 }
    $letter = $Matches[1].ToUpperInvariant()
    try {
        $drive = New-Object IO.DriveInfo($letter)
        if ($drive.DriveType -ne [IO.DriveType]::Fixed) { return [double]0 }
        $cap = [double]$drive.TotalSize * 0.05   # Windows-Standard: ca. 5 % des Laufwerks
        $vol = Get-CimInstance Win32_Volume -Filter "DriveLetter='${letter}:'" -ErrorAction Stop
        if ($vol.DeviceID -match '\{[0-9a-fA-F-]+\}') {
            $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume\$($Matches[0])"
            $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            if ($props.NukeOnDelete -eq 1) { return [double]0 }
            if ($props.MaxCapacity) { $cap = [double]$props.MaxCapacity * 1MB }
        }
        return $cap
    } catch { return [double]0 }
}

function Remove-PathsToRecycleBin {
    <#
        Verschiebt Dateien/Ordner in den Papierkorb. Einträge, die nicht hineinpassen oder auf Laufwerken ohne
        Papierkorb liegen, werden NICHT gelöscht, sondern als »Rest« zurückgegeben.
    #>
    param($Items)
    Add-Type -AssemblyName Microsoft.VisualBasic
    $ok = New-Object System.Collections.Generic.List[object]
    $failed = New-Object System.Collections.Generic.List[string]
    $rest = New-Object System.Collections.Generic.List[object]
    $caps = @{}
    foreach ($it in @($Items)) {
        $drive = if ($it.Path -match '^([A-Za-z]):') { $Matches[1].ToUpperInvariant() } else { '' }
        if (-not $caps.ContainsKey($drive)) { $caps[$drive] = Get-RecycleCapacity $it.Path }
        if ([double]$it.Size -gt $caps[$drive]) { $rest.Add($it); continue }
        try {
            if ($it.IsFolder) { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($it.Path, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin) }
            else { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($it.Path, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin) }
            $ok.Add($it)
        } catch { $failed.Add($it.Name) }
    }
    [pscustomobject]@{ Ok = $ok.ToArray(); Failed = $failed.ToArray(); Rest = $rest.ToArray(); Freed = [double](($ok | Measure-Object Size -Sum).Sum) }
}

function Add-PermanentDeleteFinding {
    <# Was nicht in den Papierkorb passt, erscheint als eigene Karte – endgültiges Löschen nur nach ausdrücklicher Auswahl. #>
    param($Items)
    $Items = @($Items)
    Remove-FindingByKey 'Endgueltig'
    if (-not $Items) { return }
    $sum = [double](($Items | Measure-Object Size -Sum).Sum)
    $labels = @($Items | ForEach-Object { '{0,10}  {1}' -f (Format-Bytes $_.Size), $_.Path })
    Add-Finding Speicher Warnung "Endgültig löschen? $($Items.Count) Eintrag/Einträge ($(Format-Bytes $sum)) passen nicht in den Papierkorb" -Key 'Endgueltig' -Silent `
        -Detail 'Diese Einträge sind zu groß für den Papierkorb oder liegen auf einem Laufwerk ohne Papierkorb (USB-Stick, externe Platte, Netzlaufwerk). Sie wurden deshalb NICHT gelöscht. Endgültig gelöschte Daten lassen sich nicht wiederherstellen – nur auswählen, wenn sicher ist, dass sie nicht mehr gebraucht werden (ggf. vorher sichern).' `
        -Items $labels -SelectLabels $labels -FixData $Items -FixLabel 'Ausgewählte Einträge ENDGÜLTIG löschen (nicht wiederherstellbar)' -Fix {
        param($d, $pre)
        if (-not $pre) {
            $a = Read-Host "   $(@($d).Count) Eintrag/Einträge endgültig löschen? Zur Bestätigung LÖSCHEN eingeben"
            if ($a -cne 'LÖSCHEN') { return 'Abgebrochen – nichts gelöscht.' }
        }
        $done = @(); $failed = @()
        foreach ($it in @($d)) {
            try { Remove-Item -LiteralPath $it.Path -Recurse -Force -ErrorAction Stop; $done += $it } catch { $failed += $it.Name }
        }
        $freed = [double](($done | Measure-Object Size -Sum).Sum)
        if ($done) { Register-Change -Beschreibung "Endgültig gelöscht: $(@($done).Count) Eintrag/Einträge ($(Format-Bytes $freed))" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis (($done | ForEach-Object { $_.Path }) -join '; ') }
        $msg = "$(@($done).Count) Eintrag/Einträge endgültig gelöscht ($(Format-Bytes $freed))."
        if ($failed) { $msg += " Nicht möglich (in Benutzung?): $($failed -join ', ')." }
        $msg
    }
}

function Get-DeleteResultText {
    param($Result, [string]$What)
    $msg = "$(@($Result.Ok).Count) $What mit $(Format-Bytes $Result.Freed) in den Papierkorb verschoben."
    if (@($Result.Failed).Count) { $msg += " Nicht möglich (in Benutzung?): $(@($Result.Failed) -join ', ')." }
    if (@($Result.Rest).Count) { $msg += " $(@($Result.Rest).Count) Eintrag/Einträge passen nicht in den Papierkorb und wurden nicht gelöscht – siehe Karte »Endgültig löschen?«." }
    $msg
}

#endregion

#region ---------- Dateien durchsuchen ----------

function Get-FilesUnder {
    <# Alle lokal vorhandenen Dateien unter den Orten – ohne Verknüpfungspunkte, Cloud-Platzhalter und Programm-/Systembereiche. #>
    param([string[]]$Roots, [double]$MinSize = 0)
    $skipAttr = [int][IO.FileAttributes]::ReparsePoint -bor [int][IO.FileAttributes]::Offline -bor 0x400000 -bor 0x40000
    $seen = @{}
    foreach ($root in $Roots) {
        $stack = New-Object System.Collections.Generic.Stack[string]
        $stack.Push($root)
        while ($stack.Count) {
            $dir = $stack.Pop()
            if ($seen.ContainsKey($dir.ToLowerInvariant())) { continue }
            $seen[$dir.ToLowerInvariant()] = $true
            try { $entries = (New-Object IO.DirectoryInfo $dir).EnumerateFileSystemInfos() } catch { continue }
            try {
                foreach ($e in $entries) {
                    if ([int]$e.Attributes -band $skipAttr) { continue }
                    if ($e -is [IO.DirectoryInfo]) {
                        if ($Script:SkipDirNames -contains $e.Name.ToLowerInvariant()) { continue }
                        if (Test-InsideSystemArea $e.FullName) { continue }
                        $stack.Push($e.FullName)
                    } elseif ($e.Length -ge $MinSize) { $e }
                }
            } catch { }
        }
    }
}

function Get-QuickHash {
    <# Prüfsumme aus Anfang und Ende der Datei – trennt die meisten verschiedenen Dateien gleicher Größe ohne alles zu lesen. #>
    param([IO.FileInfo]$File)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $fs = [IO.File]::Open($File.FullName, 'Open', 'Read', 'ReadWrite')
        try {
            $len = [int][math]::Min(65536, $fs.Length)
            $buf = New-Object byte[] ($len * 2)
            $n = $fs.Read($buf, 0, $len)
            if ($fs.Length -gt $len) { $null = $fs.Seek(-$len, 'End'); $n += $fs.Read($buf, $len, $len) }
            return [BitConverter]::ToString($sha.ComputeHash($buf, 0, $n))
        } finally { $fs.Dispose() }
    } catch { return $null } finally { $sha.Dispose() }
}

function Find-DuplicateFiles {
    <# Gruppen von Dateien mit identischem Inhalt (Größe → Schnell-Prüfsumme → volle SHA-256). #>
    param([string[]]$Roots, [double]$MinSize = 1MB)
    $groups = New-Object System.Collections.Generic.List[object]
    $bySize = @(Get-FilesUnder -Roots $Roots -MinSize $MinSize) | Group-Object Length | Where-Object { $_.Count -gt 1 }
    foreach ($sg in $bySize) {
        $quick = foreach ($f in $sg.Group) { $q = Get-QuickHash $f; if ($q) { [pscustomobject]@{ File = $f; Q = $q } } }
        foreach ($qg in @($quick) | Group-Object Q | Where-Object { $_.Count -gt 1 }) {
            $full = foreach ($x in $qg.Group) {
                try { [pscustomobject]@{ File = $x.File; H = (Get-FileHash -LiteralPath $x.File.FullName -Algorithm SHA256 -ErrorAction Stop).Hash } } catch { }
            }
            foreach ($hg in @($full) | Group-Object H | Where-Object { $_.Count -gt 1 }) {
                # Behalten: die älteste Kopie (Erstellungsdatum), bei Gleichstand die mit dem kürzesten Pfad
                $files = @($hg.Group | ForEach-Object { $_.File } | Sort-Object CreationTime, { $_.FullName.Length })
                $groups.Add([pscustomobject]@{ Size = [double]$files[0].Length; Keep = $files[0]; Copies = @($files | Select-Object -Skip 1); All = $files })
            }
        }
    }
    return @($groups | Sort-Object { $_.Size * $_.Copies.Count } -Descending)
}

function Find-EmptyFolders {
    <# Oberste leere Ordner (keine Dateien außer Windows-Hilfsdateien, auch nicht in Unterordnern). #>
    param([string[]]$Roots)
    $protected = Get-ProtectedFolders
    $result = New-Object System.Collections.Generic.List[object]
    $skipAttr = [int][IO.FileAttributes]::ReparsePoint
    $isEmpty = $null
    $isEmpty = {
        param([string]$Dir, [bool]$IsRoot)
        try { $entries = @((New-Object IO.DirectoryInfo $Dir).EnumerateFileSystemInfos()) } catch { return $false }
        $empty = $true
        $emptySubs = @()
        foreach ($e in $entries) {
            if ($e -is [IO.DirectoryInfo]) {
                if ([int]$e.Attributes -band $skipAttr -or $Script:SkipDirNames -contains $e.Name.ToLowerInvariant() -or (Test-InsideSystemArea $e.FullName)) { $empty = $false; continue }
                if (& $isEmpty $e.FullName $false) { $emptySubs += $e } else { $empty = $false }
            } elseif ($Script:HelperFileNames -notcontains $e.Name.ToLowerInvariant()) { $empty = $false }
        }
        # Nur die obersten leeren Ordner melden: ist dieser Ordner leer, vertritt er seine Unterordner
        if ((-not $empty -or $IsRoot) -and $emptySubs) {
            foreach ($s in $emptySubs) {
                if (Test-DeletableFolder $s.FullName $protected) { $result.Add([pscustomobject]@{ Path = $s.FullName; Name = $s.Name; Size = [double]0; IsFolder = $true; Changed = $s.LastWriteTime }) }
            }
        }
        return $empty
    }
    foreach ($r in $Roots) { $null = & $isEmpty $r $true }
    return @($result | Sort-Object Path)
}

function Get-LargeFolders {
    <# Größte Ordner bis zur zweiten Ebene unter den Orten (eine Leserunde für alle Ebenen). #>
    param([string[]]$Roots, [double]$MinSize = 100MB, [int]$Top = 30)
    $protected = Get-ProtectedFolders
    $list = New-Object System.Collections.Generic.List[object]
    $skipAttr = [int][IO.FileAttributes]::ReparsePoint -bor [int][IO.FileAttributes]::Offline -bor 0x400000 -bor 0x40000
    $measure = $null
    $measure = {
        param([string]$Dir, [int]$Depth, [string]$Root)
        $size = [double]0; $files = 0; $last = [datetime]::MinValue
        try { $entries = (New-Object IO.DirectoryInfo $Dir).EnumerateFileSystemInfos() } catch { return @([double]0, 0, $last) }
        try {
            foreach ($e in $entries) {
                if ([int]$e.Attributes -band $skipAttr) { continue }
                if ($e -is [IO.DirectoryInfo]) {
                    $r = & $measure $e.FullName ($Depth + 1) $Root
                    $size += $r[0]; $files += $r[1]; if ($r[2] -gt $last) { $last = $r[2] }
                } else {
                    $size += $e.Length; $files++
                    if ($e.LastWriteTime -gt $last) { $last = $e.LastWriteTime }
                }
            }
        } catch { }
        if ($Depth -ge 1 -and $Depth -le 2 -and $size -ge $MinSize) {
            $list.Add([pscustomobject]@{
                    Path = $Dir; Name = (Split-Path -Leaf $Dir); Size = $size; Files = $files; Changed = $last; IsFolder = $true; Depth = $Depth
                    Rel = $Dir.Substring([math]::Min($Dir.Length, (Split-Path -Parent $Root).Length)).TrimStart('\')
                    Deletable = (Test-DeletableFolder $Dir $protected)
                })
        }
        return @($size, $files, $last)
    }
    foreach ($r in $Roots) { $null = & $measure $r 0 $r }
    return @($list | Sort-Object Size -Descending | Select-Object -First $Top)
}

#endregion

#region ---------- Entwickler-Reste ----------

# Ordner, die immer neu erzeugt werden können (Name → Art)
$Script:DevAlwaysRebuildable = [ordered]@{
    'node_modules' = 'Node.js-Pakete (npm install)'; '__pycache__' = 'Python-Zwischendateien'; '.pytest_cache' = 'pytest-Cache'
    '.mypy_cache' = 'mypy-Cache'; '.ruff_cache' = 'Ruff-Cache'; '.gradle' = 'Gradle-Cache'; '.next' = 'Next.js-Build'; '.nuxt' = 'Nuxt-Build'
    '.parcel-cache' = 'Parcel-Cache'; '.turbo' = 'Turborepo-Cache'; '.angular' = 'Angular-Cache'; '.svelte-kit' = 'SvelteKit-Build'
}
# Build-Ordner nur, wenn daneben eine passende Projektdatei liegt
$Script:DevBuildDirs = @{
    'build'  = @('package.json', 'pyproject.toml', 'setup.py', 'CMakeLists.txt', 'build.gradle', 'build.gradle.kts')
    'dist'   = @('package.json', 'pyproject.toml', 'setup.py')
    'out'    = @('package.json', 'CMakeLists.txt')
    'target' = @('Cargo.toml', 'pom.xml')
    'bin'    = @('*.csproj', '*.vbproj', '*.fsproj')
    'obj'    = @('*.csproj', '*.vbproj', '*.fsproj')
}

function Get-DevSearchRoots {
    param($Data)
    if ($Data -and $Data.Folder) { return @((Get-Item -LiteralPath $Data.Folder -ErrorAction Stop).FullName.TrimEnd('\')) }
    $extra = @('source\repos', 'Projects', 'Projekte', 'dev', 'code', 'git') | ForEach-Object { Join-Path $env:USERPROFILE $_ } | Where-Object { Test-Path -LiteralPath $_ }
    @(@(Get-UserDataRoots) + @($extra) | Select-Object -Unique)
}

function Find-DevLeftovers {
    <# Neu erzeugbare Ordner in Projekten (ohne eigenen Code und ohne .git). #>
    param([string[]]$Roots, [double]$MinSize = 1MB)
    $found = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $stack = New-Object System.Collections.Generic.Stack[string]
    foreach ($r in $Roots) { $stack.Push($r) }
    while ($stack.Count) {
        $dir = $stack.Pop()
        if ($seen.ContainsKey($dir.ToLowerInvariant())) { continue }
        $seen[$dir.ToLowerInvariant()] = $true
        try { $subs = @((New-Object IO.DirectoryInfo $dir).EnumerateDirectories()) } catch { continue }
        foreach ($d in $subs) {
            if ([int]$d.Attributes -band [int][IO.FileAttributes]::ReparsePoint) { continue }
            $name = $d.Name.ToLowerInvariant()
            if ($name -in '.git', '.svn', '.hg', 'appdata', '$recycle.bin') { continue }
            if (Test-InsideSystemArea $d.FullName) { continue }
            $kind = $null
            if ($Script:DevAlwaysRebuildable.Contains($name)) { $kind = $Script:DevAlwaysRebuildable[$name] }
            elseif ($name -in 'venv', '.venv', 'env', '.env' -and (Test-Path -LiteralPath (Join-Path $d.FullName 'pyvenv.cfg'))) { $kind = 'Python-Umgebung (pip install)' }
            elseif ($Script:DevBuildDirs.ContainsKey($name)) {
                foreach ($m in $Script:DevBuildDirs[$name]) {
                    if (@(Get-ChildItem -LiteralPath $dir -Filter $m -File -ErrorAction SilentlyContinue | Select-Object -First 1).Count) { $kind = "Build-Ausgabe ($m)"; break }
                }
            }
            if ($kind) {
                $size = [double](Get-DirectorySizeFast $d.FullName)
                if ($size -ge $MinSize) {
                    $proj = Get-Item -LiteralPath $dir
                    $last = @($proj.LastWriteTime, $d.LastWriteTime) | Sort-Object -Descending | Select-Object -First 1
                    $found.Add([pscustomobject]@{ Path = $d.FullName; Name = $d.Name; Size = $size; IsFolder = $true; Kind = $kind; Project = $dir; Changed = $last; Cache = $false })
                }
                continue   # in neu erzeugbare Ordner nicht weiter hinabsteigen
            }
            $stack.Push($d.FullName)
        }
    }
    return $found.ToArray()
}

function Get-DevGlobalCaches {
    <# Globale Paket-Caches im Benutzerprofil. #>
    $caches = @(
        @{ Path = (Join-Path $env:LOCALAPPDATA 'npm-cache'); Kind = 'npm-Cache' }
        @{ Path = (Join-Path $env:APPDATA 'npm-cache'); Kind = 'npm-Cache' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'pip\cache'); Kind = 'pip-Cache' }
        @{ Path = (Join-Path $env:USERPROFILE '.nuget\packages'); Kind = 'NuGet-Paketcache' }
        @{ Path = (Join-Path $env:LOCALAPPDATA 'Yarn\Cache'); Kind = 'Yarn-Cache' }
        @{ Path = (Join-Path $env:USERPROFILE '.gradle\caches'); Kind = 'Gradle-Cache' }
    )
    foreach ($c in $caches) {
        if (-not $c.Path -or -not (Test-Path -LiteralPath $c.Path)) { continue }
        $size = [double](Get-DirectorySizeFast $c.Path)
        if ($size -lt 50MB) { continue }
        [pscustomobject]@{ Path = $c.Path; Name = (Split-Path -Leaf $c.Path); Size = $size; IsFolder = $true; Kind = $c.Kind; Project = '(globaler Cache)'; Changed = (Get-Item -LiteralPath $c.Path).LastWriteTime; Cache = $true }
    }
}

function Invoke-DevLeftoverSearch {
    param($Data)
    $roots = Get-DevSearchRoots $Data
    Write-Host "     Durchsuche: $($roots -join '; ')" -ForegroundColor Gray
    $items = @(@(Find-DevLeftovers -Roots $roots) + @(if (-not ($Data -and $Data.Folder)) { Get-DevGlobalCaches }) | Sort-Object Size -Descending)
    Remove-FindingByKey 'Entwickler'
    if (-not $items) {
        Add-Finding Speicher OK 'Keine Entwickler-Reste gefunden' -Key 'Entwickler' -Silent -Detail "Durchsucht: $($roots -join '; ')"
        return 'Keine Entwickler-Reste gefunden.'
    }
    $limit = (Get-Date).AddDays(-30)
    $labels = @($items | ForEach-Object { '{0} · {1} · {2} · zuletzt geändert {3:dd.MM.yyyy} · {4}' -f (Format-Bytes $_.Size), $_.Kind, $(if ($_.Cache) { 'globaler Cache' } else { 'Projekt ' + (Split-Path -Leaf $_.Project) }), $_.Changed, $_.Path })
    $defaults = @($items | ForEach-Object { (-not $_.Cache) -and $_.Changed -lt $limit })
    # Details nach Projekt gruppiert
    $lines = foreach ($g in @($items | Group-Object Project | Sort-Object { ($_.Group | Measure-Object Size -Sum).Sum } -Descending)) {
        '{0}  ({1})' -f $g.Name, (Format-Bytes ([double](($g.Group | Measure-Object Size -Sum).Sum)))
        foreach ($i in $g.Group) { '   {0,10}  {1}  –  {2}' -f (Format-Bytes $i.Size), $i.Name, $i.Kind }
    }
    $sum = [double](($items | Measure-Object Size -Sum).Sum)
    $sev = if ($sum -ge 5GB) { 'Warnung' } else { 'Info' }
    Add-Finding Speicher $sev "Entwickler-Reste: $(Format-Bytes $sum) in $($items.Count) neu erzeugbaren Ordner(n)" -Key 'Entwickler' -Silent `
        -Detail "Diese Ordner enthalten keinen eigenen Code: heruntergeladene Pakete, Python-Umgebungen, Caches und Build-Ausgaben. Sie entstehen beim nächsten Bauen bzw. Starten des Projekts neu (z. B. »npm install«, »pip install -r requirements.txt«, erneutes Kompilieren) – das kann beim ersten Mal etwas dauern und braucht Internet. Vorausgewählt sind nur Reste aus Projekten, die seit mehr als 30 Tagen nicht geändert wurden; globale Caches sind nicht vorausgewählt. Eigener Code und Git-Verläufe (.git) werden nie angeboten. Durchsucht: $($roots -join '; ')" `
        -Items @($lines) -FixData $items -SelectLabels $labels -SelectDefault $defaults `
        -FixLabel 'Ausgewählte Entwickler-Reste in den Papierkorb verschieben' -Fix {
        param($d, $pre)
        $chosen = @($d)
        if (-not $pre) {
            for ($i = 0; $i -lt $chosen.Count; $i++) { Write-Host ('    {0,3}) {1,10}  {2}  – {3}' -f ($i + 1), (Format-Bytes $chosen[$i].Size), $chosen[$i].Path, $chosen[$i].Kind) }
            $sel = Read-Host '   In den Papierkorb: [A] alle, Nummern oder leer = keine'
            $chosen = if ($sel -match '^\s*(a|alle)\s*$') { $chosen } else { @((Read-Selection $sel $chosen.Count) | ForEach-Object { $chosen[$_] }) }
            if (-not $chosen) { return 'Nichts ausgewählt – nichts gelöscht.' }
        }
        $res = Remove-PathsToRecycleBin $chosen
        if (@($res.Ok).Count) { Register-Change -Beschreibung "Entwickler-Reste gelöscht: $(@($res.Ok).Count) Ordner ($(Format-Bytes $res.Freed))" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis (($res.Ok | ForEach-Object { $_.Path }) -join '; ') }
        Add-PermanentDeleteFinding $res.Rest
        (Get-DeleteResultText $res 'Ordner') + ' Die Ordner entstehen beim nächsten Bauen bzw. Starten des jeweiligen Projekts neu.'
    }
    "$($items.Count) Entwickler-Rest(e) mit $(Format-Bytes $sum) gefunden – siehe Karte »Entwickler-Reste«."
}

#endregion

#region ---------- Werkzeuge und Ergebniskarten ----------

function Invoke-DuplicateSearch {
    param($Data)
    $roots = Resolve-ScanRoots $Data
    Write-Host "     Durchsuche: $($roots -join '; ')" -ForegroundColor Gray
    $groups = @(Find-DuplicateFiles -Roots $roots)
    Remove-FindingByKey 'Duplikate'
    if (-not $groups) {
        Add-Finding Speicher OK 'Keine doppelten Dateien gefunden (ab 1 MB)' -Key 'Duplikate' -Silent -Detail "Durchsucht: $($roots -join '; ')"
        return 'Keine doppelten Dateien gefunden.'
    }
    $copies = New-Object System.Collections.Generic.List[object]
    $labels = New-Object System.Collections.Generic.List[string]
    $defaults = New-Object System.Collections.Generic.List[bool]
    $items = New-Object System.Collections.Generic.List[string]
    $g = 0
    foreach ($grp in $groups) {
        $g++
        $items.Add(('Gruppe {0}: {1} Dateien zu je {2}' -f $g, $grp.All.Count, (Format-Bytes $grp.Size)))
        foreach ($f in $grp.All) {
            $keep = [object]::ReferenceEquals($f, $grp.Keep)
            $items.Add(('   {0}  {1:dd.MM.yyyy}  {2}' -f $(if ($keep) { 'behalten' } else { 'Kopie   ' }), $f.CreationTime, $f.FullName))
            if ($labels.Count -ge 600) { continue }   # Auswahlliste übersichtlich halten
            $copies.Add([pscustomobject]@{ Path = $f.FullName; Name = $f.Name; Size = [double]$f.Length; IsFolder = $false; Group = $g; Keep = $keep })
            $labels.Add(('Gruppe {0} · {1} · {2:dd.MM.yyyy} · {3}{4}' -f $g, (Format-Bytes $f.Length), $f.CreationTime, $f.FullName, $(if ($keep) { '   (Vorschlag: behalten)' } else { '' })))
            $defaults.Add(-not $keep)
        }
    }
    # Für die Löschung merken: vollständige Liste (Sicherheitsnetz je Gruppe) und durchsuchte Orte (leer gewordene Ordner)
    $Script:DuplicateCandidates = $copies.ToArray()
    $Script:DuplicateRoots = $roots
    $waste = [double](($groups | ForEach-Object { $_.Size * $_.Copies.Count } | Measure-Object -Sum).Sum)
    $nCopies = [int](($groups | ForEach-Object { $_.Copies.Count } | Measure-Object -Sum).Sum)
    $sev = if ($waste -ge 1GB) { 'Warnung' } else { 'Info' }
    Add-Finding Speicher $sev "Doppelte Dateien: $(Format-Bytes $waste) in $nCopies Kopie(n) freigebbar" -Key 'Duplikate' -Silent `
        -Detail "$($groups.Count) Gruppe(n) mit identischem Inhalt (gleiche Größe und Prüfsumme, ab 1 MB). Vorausgewählt sind alle Kopien außer jeweils der ältesten – das lässt sich im nächsten Schritt ändern. Gelöscht wird in den Papierkorb. Durchsucht: $($roots -join '; ')" `
        -Items $items.ToArray() -FixData $copies.ToArray() -SelectLabels $labels.ToArray() -SelectDefault $defaults.ToArray() `
        -FixLabel 'Ausgewählte doppelte Dateien in den Papierkorb verschieben' -Fix {
        param($d, $pre)
        $all = @($Script:DuplicateCandidates)
        $chosen = if ($pre) { @($d) } else {
            for ($i = 0; $i -lt $all.Count; $i++) { Write-Host ('    {0,4}) Gruppe {1} · {2} · {3}{4}' -f ($i + 1), $all[$i].Group, (Format-Bytes $all[$i].Size), $all[$i].Path, $(if ($all[$i].Keep) { '  (Vorschlag: behalten)' } else { '' })) }
            $sel = Read-Host '   In den Papierkorb: [V] Vorschlag (alle Kopien außer der ältesten), Nummern (z. B. 2,3,5-7) oder leer = keine'
            if ($sel -match '^\s*v\s*$') { @($all | Where-Object { -not $_.Keep }) } else { @((Read-Selection $sel $all.Count) | ForEach-Object { $all[$_] }) }
        }
        if (-not $chosen) { return 'Nichts ausgewählt – nichts gelöscht.' }
        # Sicherheitsnetz: nie alle Dateien einer Gruppe löschen
        $safe = foreach ($grp in @($chosen | Group-Object Group)) {
            $total = @($all | Where-Object { $_.Group -eq [int]$grp.Name }).Count
            if ($grp.Count -ge $total -and $total -gt 0) { $grp.Group | Select-Object -Skip 1 } else { $grp.Group }
        }
        $res = Remove-PathsToRecycleBin @($safe)
        if (@($res.Ok).Count) { Register-Change -Beschreibung "Doppelte Dateien gelöscht: $(@($res.Ok).Count) ($(Format-Bytes $res.Freed))" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis 'Die Dateien liegen im Papierkorb.' }
        Add-PermanentDeleteFinding $res.Rest
        $msg = Get-DeleteResultText $res 'Datei(en)'
        if (@($chosen).Count -ne @($safe).Count) { $msg += ' Von mindestens einer Gruppe bleibt zur Sicherheit eine Datei erhalten.' }
        # Dabei leer gewordene Ordner anbieten
        $parents = @($res.Ok | ForEach-Object { Split-Path -Parent $_.Path } | Select-Object -Unique)
        $roots = @($Script:DuplicateRoots)
        $empty = @(Find-EmptyFolders -Roots $roots | Where-Object { $p = $_.Path; $parents | Where-Object { ($_ + '\') -like ($p + '\*') } })
        if ($empty) {
            Add-EmptyFolderFinding -Folders $empty -Roots $roots -Note 'Durch das Löschen der Duplikate leer geworden.'
            $msg += " Dabei sind $($empty.Count) Ordner leer geworden – sie stehen jetzt unter »Leere Ordner« zur Auswahl."
        }
        $msg
    }
    return "$($groups.Count) Gruppe(n) doppelter Dateien gefunden ($(Format-Bytes $waste) freigebbar) – siehe Karte »Doppelte Dateien«."
}

function Add-EmptyFolderFinding {
    param($Folders, [string[]]$Roots, [string]$Note)
    Remove-FindingByKey 'LeereOrdner'
    $Folders = @($Folders)
    if (-not $Folders) {
        Add-Finding Speicher OK 'Keine leeren Ordner gefunden' -Key 'LeereOrdner' -Silent -Detail "Durchsucht: $($Roots -join '; ')"
        return
    }
    $labels = @($Folders | ForEach-Object { '{0:dd.MM.yyyy}  {1}' -f $_.Changed, $_.Path })
    $detail = 'Diese Ordner enthalten keine Dateien (Windows-Hilfsdateien wie desktop.ini ausgenommen), auch nicht in Unterordnern. Benutzer-, Programm- und Systemordner werden nie angeboten. Gelöscht wird in den Papierkorb.'
    if ($Note) { $detail = "$Note $detail" }
    Add-Finding Speicher Info "$($Folders.Count) leere(r) Ordner gefunden" -Key 'LeereOrdner' -Silent -Detail "$detail Durchsucht: $($Roots -join '; ')" `
        -Items $labels -FixData $Folders -SelectLabels $labels -SelectAllByDefault -FixLabel 'Ausgewählte leere Ordner in den Papierkorb verschieben' -Fix {
        param($d, $pre)
        $chosen = @($d)
        if (-not $pre) {
            for ($i = 0; $i -lt $chosen.Count; $i++) { Write-Host ('    {0,4}) {1}' -f ($i + 1), $chosen[$i].Path) }
            $sel = Read-Host '   In den Papierkorb: [A] alle, Nummern oder leer = keine'
            $chosen = if ($sel -match '^\s*(a|alle)\s*$') { $chosen } else { @((Read-Selection $sel $chosen.Count) | ForEach-Object { $chosen[$_] }) }
            if (-not $chosen) { return 'Nichts ausgewählt – nichts gelöscht.' }
        }
        # Nur löschen, was immer noch leer ist
        $still = @($chosen | Where-Object { (Test-Path -LiteralPath $_.Path) -and -not (Get-ChildItem -LiteralPath $_.Path -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $Script:HelperFileNames -notcontains $_.Name.ToLowerInvariant() } | Select-Object -First 1) })
        $res = Remove-PathsToRecycleBin $still
        if (@($res.Ok).Count) { Register-Change -Beschreibung "Leere Ordner gelöscht: $(@($res.Ok).Count)" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis (($res.Ok | ForEach-Object { $_.Path }) -join '; ') }
        Add-PermanentDeleteFinding $res.Rest
        $msg = Get-DeleteResultText $res 'Ordner'
        if ($still.Count -lt $chosen.Count) { $msg += " $($chosen.Count - $still.Count) Ordner waren inzwischen nicht mehr leer und wurden übersprungen." }
        $msg
    }
}

function Invoke-EmptyFolderSearch {
    param($Data)
    $roots = Resolve-ScanRoots $Data
    $folders = @(Find-EmptyFolders -Roots $roots)
    Add-EmptyFolderFinding -Folders $folders -Roots $roots
    if ($folders) { "$($folders.Count) leere(r) Ordner gefunden – siehe Karte »Leere Ordner«." } else { 'Keine leeren Ordner gefunden.' }
}

function Invoke-LargeFolderSearch {
    param($Data)
    $roots = Resolve-ScanRoots $Data
    $folders = @(Get-LargeFolders -Roots $roots)
    Remove-FindingByKey 'GrosseOrdner'
    if (-not $folders) {
        Add-Finding Speicher OK 'Keine Ordner über 100 MB gefunden' -Key 'GrosseOrdner' -Silent -Detail "Durchsucht: $($roots -join '; ')"
        return 'Keine großen Ordner gefunden.'
    }
    $deletable = @($folders | Where-Object { $_.Deletable })
    $items = @($folders | ForEach-Object {
            '{0,10}  {1,7} Dateien  {2:dd.MM.yyyy}  {3}{4}' -f (Format-Bytes $_.Size), $_.Files, $_.Changed, $_.Path, $(if (-not $_.Deletable) { '   (geschützt – nur Anzeige)' } else { '' })
        })
    $labels = @($deletable | ForEach-Object { '{0} · {1} Dateien · zuletzt geändert {2:dd.MM.yyyy} · {3}' -f (Format-Bytes $_.Size), $_.Files, $_.Changed, $_.Path })
    $chart = @($folders | Where-Object { $_.Depth -eq 1 } | Select-Object -First 12 | ForEach-Object { [pscustomobject]@{ Label = $_.Name; Value = $_.Size; Text = (Format-Bytes $_.Size); Path = $_.Path } })
    $detail = 'Die größten Ordner bis zur zweiten Ebene. Nichts ist vorausgewählt: Ordner ankreuzen, die komplett weg sollen – mit allen Unterordnern und Dateien. Gelöscht wird in den Papierkorb; was dort nicht hineinpasst, wird nur nach ausdrücklicher Bestätigung endgültig gelöscht.'
    if (@($folders).Count -gt $deletable.Count) { $detail += ' Programm-, Windows- und Systemordner sowie AppData werden nur angezeigt – Programme bitte über »Einstellungen › Apps« deinstallieren.' }
    $detail += " Durchsucht: $($roots -join '; ')"
    $fixArgs = @{}
    if ($deletable) {
        $fixArgs = @{ FixLabel = 'Ausgewählte Ordner komplett in den Papierkorb verschieben'; FixData = $deletable; SelectLabels = $labels; Fix = {
                param($d, $pre)
                $chosen = @($d)
                if (-not $pre) {
                    for ($i = 0; $i -lt $chosen.Count; $i++) { Write-Host ('    {0,3}) {1,10}  {2}' -f ($i + 1), (Format-Bytes $chosen[$i].Size), $chosen[$i].Path) }
                    $sel = Read-Host '   Komplett löschen (Papierkorb): Nummern oder leer = keine'
                    $chosen = @((Read-Selection $sel $chosen.Count) | ForEach-Object { $chosen[$_] })
                    if (-not $chosen) { return 'Nichts ausgewählt – nichts gelöscht.' }
                }
                # Unterordner eines ebenfalls gewählten Ordners nicht doppelt löschen
                $top = @($chosen | Where-Object { $c = $_; -not ($chosen | Where-Object { $_ -ne $c -and ($c.Path + '\') -like ($_.Path + '\*') }) })
                $res = Remove-PathsToRecycleBin $top
                if (@($res.Ok).Count) { Register-Change -Beschreibung "Ordner gelöscht: $(@($res.Ok | ForEach-Object { $_.Name }) -join ', ') ($(Format-Bytes $res.Freed))" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis 'Die Ordner liegen im Papierkorb.' }
                Add-PermanentDeleteFinding $res.Rest
                Get-DeleteResultText $res 'Ordner'
            }
        }
    }
    Add-Finding Speicher Info "Große Ordner: die $(@($folders).Count) größten (ab 100 MB)" -Key 'GrosseOrdner' -Silent -Detail $detail -Items $items -Chart $chart -ChartStyle Kacheln @fixArgs
    "$(@($folders).Count) große Ordner gefunden – siehe Karte »Große Ordner«."
}

function Invoke-StorageDrillDown {
    <# Kachelgrafik: Unterordner eines angeklickten Ordners anzeigen. #>
    param([string]$Path)
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    Remove-FindingByKey 'Detail'
    $chart = @(Get-StorageBreakdown -Path $Path)
    if (-not $chart) {
        Add-Finding Speicher Info "Speicherbelegung: $Path" -Key 'Detail' -Silent -Detail 'Dieser Ordner enthält keine Unterordner mit nennenswertem Inhalt.'
        return
    }
    Add-Finding Speicher Info "Speicherbelegung: $Path" -Key 'Detail' -Silent -Chart $chart -ChartStyle Kacheln `
        -Detail 'Größte Unterordner. Auf eine Kachel klicken, um noch tiefer zu sehen. Ganze Ordner löschen: Werkzeug »Große Ordner anzeigen« (hier mit »Anderen Ordner wählen«).'
}

function Add-FileToolFindings {
    <# Die Datei-Werkzeuge als ausführbare Karten (Bereich »Speicherfresser« und »Reparatur-Werkzeuge«). #>
    param([string]$Category)
    $common = 'Gesucht wird in Dokumente, Bilder, Videos, Musik, Desktop und Downloads – auf Wunsch in einem anderen Ordner oder Laufwerk (Frage beim Start).'
    Add-Finding $Category Info 'Werkzeug: Doppelte Dateien suchen' -Silent -Repeatable -AskFolder `
        -Detail "Findet Dateien mit identischem Inhalt (ab 1 MB) und zeigt sie gruppiert zum Löschen an. $common Je nach Datenmenge einige Minuten." `
        -FixLabel 'Doppelte Dateien suchen' -FixData @{ Folder = $null } -Fix { param($d, $pre) if (-not $pre -and -not $d.Folder) { $d = Read-FolderChoice }; Invoke-DuplicateSearch $d }
    Add-Finding $Category Info 'Werkzeug: Leere Ordner suchen' -Silent -Repeatable -AskFolder `
        -Detail "Findet Ordner ohne Dateien (auch in Unterordnern) und zeigt sie zum Löschen an. $common" `
        -FixLabel 'Leere Ordner suchen' -FixData @{ Folder = $null } -Fix { param($d, $pre) if (-not $pre -and -not $d.Folder) { $d = Read-FolderChoice }; Invoke-EmptyFolderSearch $d }
    Add-Finding $Category Info 'Werkzeug: Große Ordner anzeigen und löschen' -Silent -Repeatable -AskFolder `
        -Detail "Listet die größten Ordner (bis zwei Ebenen tief) mit Größe, Dateianzahl und Datum; ganze Ordner lassen sich zum Löschen auswählen. $common" `
        -FixLabel 'Große Ordner anzeigen' -FixData @{ Folder = $null } -Fix { param($d, $pre) if (-not $pre -and -not $d.Folder) { $d = Read-FolderChoice }; Invoke-LargeFolderSearch $d }
    Add-Finding $Category Info 'Werkzeug: Entwickler-Reste finden' -Silent -Repeatable -AskFolder `
        -Detail 'Findet neu erzeugbare Ordner in Programmier-Projekten (z. B. Codex-Arbeitsordner): node_modules, Python-Umgebungen, Caches und Build-Ausgaben, dazu globale Paket-Caches von npm, pip, NuGet, Yarn und Gradle. Eigener Code und Git-Verläufe werden nie angeboten. Gesucht wird in Dokumente, Desktop, Downloads und typischen Projektordnern – auf Wunsch in einem anderen Ordner.' `
        -FixLabel 'Entwickler-Reste finden' -FixData @{ Folder = $null } -Fix { param($d, $pre) if (-not $pre -and -not $d.Folder) { $d = Read-FolderChoice }; Invoke-DevLeftoverSearch $d }
}

#endregion
