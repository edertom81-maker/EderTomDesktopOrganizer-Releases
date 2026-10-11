<#
    Papierkorb schnell messen und leeren: direkt im Dateisystem statt über die Windows-Shell (die Datei für Datei
    löscht und bei vielen Dateien sehr langsam ist). Berücksichtigt werden der Papierkorb des angemeldeten Benutzers
    und verwaiste Papierkörbe gelöschter Benutzerkonten; Papierkörbe anderer vorhandener Konten bleiben unberührt.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

function Get-CurrentUserSid {
    try { return [Security.Principal.WindowsIdentity]::GetCurrent().User.Value } catch { return '' }
}

function Get-RecycleBinFolders {
    <# Liefert je Laufwerk die Papierkorb-Ordner mit Art: Eigener, Verwaist oder Anderer. #>
    $own = Get-CurrentUserSid
    $profiles = @{}
    Get-ChildItem -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' -ErrorAction SilentlyContinue | ForEach-Object { $profiles[$_.PSChildName] = $true }
    $drives = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue | ForEach-Object { $_.DeviceID })
    foreach ($d in $drives) {
        $root = Join-Path $d '$Recycle.Bin'
        Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $sid = $_.Name
            $kind = if ($sid -eq $own) { 'Eigener' } elseif ($sid -match '^S-1-5-21-' -and -not $profiles.ContainsKey($sid)) { 'Verwaist' } else { 'Anderer' }
            [pscustomobject]@{ Drive = $d; Sid = $sid; Path = $_.FullName; Kind = $kind }
        }
    }
}

function Measure-RecycleBinFast {
    <# Größe des eigenen und der verwaisten Papierkörbe (ohne desktop.ini). #>
    $sum = [double]0; $orphan = [double]0
    foreach ($f in @(Get-RecycleBinFolders | Where-Object { $_.Kind -ne 'Anderer' })) {
        $s = [double]0
        Get-ChildItem -LiteralPath $f.Path -Recurse -Force -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' } | ForEach-Object { $s += $_.Length }
        $sum += $s
        if ($f.Kind -eq 'Verwaist') { $orphan += $s }
    }
    [pscustomobject]@{ Size = $sum; Orphaned = $orphan }
}

function Remove-TreeFast {
    <# Löscht eine Datei bzw. einen Ordner samt Inhalt ohne Umweg über die Shell. #>
    param([string]$Path)
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $null = & cmd.exe /d /c "rd /s /q `"$Path`"" 2>&1
        if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue }
    } else {
        try { [IO.File]::SetAttributes($Path, [IO.FileAttributes]::Normal); [IO.File]::Delete($Path) } catch { Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue }
    }
}

function Clear-RecycleBinFast {
    <# Leert den eigenen und verwaiste Papierkörbe direkt im Dateisystem. Liefert die freigegebene Größe. #>
    $before = (Measure-RecycleBinFast).Size
    foreach ($f in @(Get-RecycleBinFolders | Where-Object { $_.Kind -ne 'Anderer' })) {
        Get-ChildItem -LiteralPath $f.Path -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' } | ForEach-Object { Remove-TreeFast $_.FullName }
        # Verwaiste Papierkörbe ganz entfernen (Windows legt sie bei Bedarf neu an)
        if ($f.Kind -eq 'Verwaist') { Remove-TreeFast $f.Path }
    }
    # Papierkorb-Symbol auf dem Desktop aktualisieren (bei leerem Papierkorb sofort fertig)
    try { Clear-RecycleBin -Force -ErrorAction Stop } catch { }
    $after = (Measure-RecycleBinFast).Size
    return [math]::Max([double]0, $before - $after)
}
