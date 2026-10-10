<#
    Defekte Verknüpfungen: Desktop, Startmenü, Taskleiste und Autostart (Ordner und Registry).
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

function Test-TargetCheckable {
    <#
        Nur Ziele auf fest eingebauten, vorhandenen Laufwerken werden bewertet. Netzlaufwerke, USB-Sticks und externe
        Platten können gerade nur nicht verbunden sein – solche Verknüpfungen gelten nicht als defekt.
    #>
    param([string]$Path)
    if (-not $Path -or $Path.StartsWith('\\')) { return $false }
    if ($Path -notmatch '^[A-Za-z]:\\') { return $false }
    try {
        $drive = New-Object IO.DriveInfo($Path.Substring(0, 1))
        return $drive.IsReady -and $drive.DriveType -eq [IO.DriveType]::Fixed
    } catch { return $false }
}

function Get-CommandExecutable {
    <# Ermittelt aus einer Befehlszeile (Autostart-Eintrag) den Pfad des gestarteten Programms. #>
    param([string]$Command)
    $c = [Environment]::ExpandEnvironmentVariables("$Command").Trim()
    if ($c -match '^"([^"]+)"') { return $Matches[1] }
    if ($c -match '^(.+?\.(exe|cmd|bat|com|vbs|ps1|lnk))(\s|$)') { return $Matches[1] }
    return ($c -split '\s+')[0]
}

function Get-BrokenShortcuts {
    param($Shell)
    $folders = @(
        @{ Path = [Environment]::GetFolderPath('Desktop'); Ort = 'Desktop'; Recurse = $false }
        @{ Path = [Environment]::GetFolderPath('CommonDesktopDirectory'); Ort = 'Öffentlicher Desktop'; Recurse = $false }
        @{ Path = [Environment]::GetFolderPath('Programs'); Ort = 'Startmenü'; Recurse = $true }
        @{ Path = [Environment]::GetFolderPath('CommonPrograms'); Ort = 'Startmenü (alle Benutzer)'; Recurse = $true }
        @{ Path = (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'); Ort = 'Taskleiste'; Recurse = $false }
    )
    $startup = @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('CommonStartup')) | Where-Object { $_ }
    foreach ($f in $folders) {
        if (-not $f.Path -or -not (Test-Path -LiteralPath $f.Path)) { continue }
        foreach ($lnk in Get-ChildItem -LiteralPath $f.Path -Filter '*.lnk' -File -Recurse:$f.Recurse -Force -ErrorAction SilentlyContinue) {
            # Autostart-Ordner liegen im Startmenü – die werden unten als Autostart-Einträge behandelt
            if ($startup | Where-Object { $lnk.FullName.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }) { continue }
            $target = $null
            try { $target = $Shell.CreateShortcut($lnk.FullName).TargetPath } catch { continue }
            # Leeres Ziel: Store-Apps und Installer-Verknüpfungen (MSI) – nicht prüfbar
            if (-not $target) { continue }
            $target = [Environment]::ExpandEnvironmentVariables($target)
            if (-not (Test-TargetCheckable $target)) { continue }
            if (Test-Path -LiteralPath $target) { continue }
            [pscustomobject]@{ Kind = 'Lnk'; Path = $lnk.FullName; Name = $lnk.BaseName; Ort = $f.Ort; Target = $target }
        }
    }
}

function Get-BrokenAutostarts {
    param($Shell)
    foreach ($e in @(Get-AutostartEntries | Where-Object { $_.Enabled })) {
        $exe = $null
        if ($e.Scope -like 'Autostart-Ordner*') {
            if ($e.Command -notlike '*.lnk') { continue }
            try { $exe = [Environment]::ExpandEnvironmentVariables($Shell.CreateShortcut($e.Command).TargetPath) } catch { continue }
        } else {
            $exe = Get-CommandExecutable $e.Command
        }
        if (-not $exe -or -not (Test-TargetCheckable $exe)) { continue }
        if (Test-Path -LiteralPath $exe) { continue }
        [pscustomobject]@{ Kind = 'Autostart'; Path = $e.Command; Name = $e.Name; Ort = $(if ($e.Scope -like 'Autostart*') { $e.Scope } else { "Autostart ($($e.Scope))" }); Target = $exe; Entry = $e }
    }
}

function Repair-BrokenShortcuts {
    <# Verknüpfungen in den Papierkorb, Autostart-Einträge umkehrbar deaktivieren. #>
    param($Items)
    $msgs = @()
    $links = @($Items | Where-Object { $_.Kind -eq 'Lnk' })
    $autos = @($Items | Where-Object { $_.Kind -eq 'Autostart' })
    if ($links) {
        Add-Type -AssemblyName Microsoft.VisualBasic
        $ok = @(); $failed = @()
        foreach ($l in $links) {
            try {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($l.Path, [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs, [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
                $ok += $l.Name
            } catch { $failed += $l.Name }
        }
        if ($ok) {
            Register-Change -Beschreibung "Defekte Verknüpfungen entfernt: $($ok -join ', ')" -Typ 'Protokoll' -NichtUmkehrbar `
                -Ergebnis 'Die Verknüpfungen liegen im Papierkorb und lassen sich dort wiederherstellen.'
            $msgs += "$($ok.Count) Verknüpfung(en) in den Papierkorb verschoben."
        }
        if ($failed) { $msgs += "Nicht möglich: $($failed -join ', ')." }
    }
    if ($autos) { $msgs += Set-AutostartDisabled @($autos | ForEach-Object { $_.Entry }) }
    if (-not $msgs) { return 'Nichts ausgewählt.' }
    return ($msgs -join ' ')
}

function Add-BrokenShortcutFindings {
    param([string]$Category)
    $shell = New-Object -ComObject WScript.Shell
    $items = @(@(Get-BrokenShortcuts -Shell $shell) + @(Get-BrokenAutostarts -Shell $shell))
    if (-not $items) {
        Add-Finding $Category OK 'Keine defekten Verknüpfungen auf Desktop, im Startmenü, in der Taskleiste und im Autostart'
        return
    }
    $autoCount = @($items | Where-Object { $_.Kind -eq 'Autostart' }).Count
    $labels = @($items | ForEach-Object { '{0}  [{1}]  →  {2} (fehlt)' -f $_.Name, $_.Ort, $_.Target })
    $sev = if ($autoCount) { 'Warnung' } else { 'Info' }
    $detail = 'Diese Verknüpfungen zeigen auf Programme oder Dateien, die es nicht mehr gibt – meist Reste deinstallierter Programme.'
    if ($autoCount) { $detail += " $autoCount davon sind Autostart-Einträge: Windows versucht bei jeder Anmeldung vergeblich, sie zu starten." }
    $detail += ' Verknüpfungen auf Netzlaufwerke, USB-Sticks und externe Platten werden nicht bewertet. Nur Angekreuztes wird bereinigt: Verknüpfungen landen im Papierkorb, Autostart-Einträge werden deaktiviert (rückgängig über »Änderungen«).'
    Add-Finding $Category $sev "$($items.Count) defekte Verknüpfung(en) gefunden" -Detail $detail -Items $labels `
        -FixLabel 'Ausgewählte defekte Verknüpfungen bereinigen' -FixData $items -SelectLabels $labels -SelectAllByDefault -Fix {
        param($d, $pre)
        if (-not $pre) {
            $all = @($d)
            for ($i = 0; $i -lt $all.Count; $i++) { Write-Host ('    {0,3}) {1}  [{2}]  → {3}' -f ($i + 1), $all[$i].Name, $all[$i].Ort, $all[$i].Target) }
            $sel = Read-Host '   Bereinigen: [A] alle, Nummern (z. B. 1,3,5-7) oder leer = keine'
            $d = if ($sel -match '^\s*(a|alle)\s*$') { $all } else { @((Read-Selection $sel $all.Count) | ForEach-Object { $all[$_] }) }
            if (-not $d) { return 'Nichts ausgewählt – nichts verändert.' }
        }
        Repair-BrokenShortcuts $d
    }
}
