<#
    Programme deinstallieren (über den offiziellen Deinstaller) und Reste aufspüren.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

# Systemkomponenten, Laufzeitbibliotheken und Treiber – werden nicht zum Deinstallieren angeboten
$Script:ProtectedProgramPattern = 'Redistributable|Runtime|\.NET|Windows SDK|Windows Software Development|WebView2|Microsoft Edge$|Microsoft Edge Update|Update Health|Windows PC Health|Treiber|Driver|Chipset|Management Engine|Intel\(R\) (Serial IO|Rapid|Dynamic|Graphics)|Realtek|NVIDIA (Graphics|HD Audio|PhysX|FrameView)|AMD (Chipset|Software)|Synaptics|ELAN|Precision Touchpad|Thunderbolt|Bluetooth|Wi-?Fi|Wireless|Defender|Bitdefender|Kaspersky|ESET|Norton|McAfee|Avast|AVG|Sophos|Malwarebytes|PC Repair Pro|Laptop-Diagnose|Microsoft Visual Studio Installer'

function Get-InstalledPrograms {
    <# Desktop-Programme aus der Registry und Store-Apps, ohne Updates und Systemkomponenten. #>
    $keys = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'Alle Benutzer' }
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'Alle Benutzer (32 Bit)' }
        @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'; Scope = 'Benutzer' }
    )
    $seen = @{}
    foreach ($k in $keys) {
        foreach ($p in Get-ItemProperty -Path $k.Path -ErrorAction SilentlyContinue) {
            if (-not $p.DisplayName -or -not $p.UninstallString) { continue }
            if ($p.SystemComponent -eq 1 -or $p.ParentKeyName -or $p.ReleaseType -match 'Update|Hotfix') { continue }
            $id = "$($p.DisplayName)|$($p.DisplayVersion)"
            if ($seen.ContainsKey($id)) { continue }
            $seen[$id] = $true
            $date = $null
            if ("$($p.InstallDate)" -match '^(\d{4})(\d{2})(\d{2})$') { try { $date = Get-Date -Year $Matches[1] -Month $Matches[2] -Day $Matches[3] } catch { } }
            [pscustomobject]@{
                Kind = 'Desktop'; Name = "$($p.DisplayName)"; Version = "$($p.DisplayVersion)"; Publisher = "$($p.Publisher)"
                Size = [double]$p.EstimatedSize * 1KB; Date = $date; Uninstall = "$($p.UninstallString)"; Quiet = "$($p.QuietUninstallString)"
                Location = "$($p.InstallLocation)"; Key = $p.PSPath; Scope = $k.Scope
                Protected = ("$($p.DisplayName)" -match $Script:ProtectedProgramPattern)
            }
        }
    }
    foreach ($a in @(Get-AppxPackage -PackageTypeFilter Main -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and -not $_.NonRemovable -and "$($_.SignatureKind)" -ne 'System' })) {
        $display = $a.Name
        try { $m = Get-AppxPackageManifest -Package $a.PackageFullName -ErrorAction Stop; if ($m.Package.Properties.DisplayName -notmatch '^ms-resource') { $display = $m.Package.Properties.DisplayName } } catch { }
        $date = $null
        if ($a.InstallLocation -and (Test-Path -LiteralPath $a.InstallLocation)) { $date = (Get-Item -LiteralPath $a.InstallLocation).CreationTime }
        [pscustomobject]@{
            Kind = 'Store'; Name = "$display"; Version = "$($a.Version)"; Publisher = ("$($a.Publisher)" -replace '^CN=([^,]+).*$', '$1')
            Size = [double]0; Date = $date; Uninstall = $a.PackageFullName; Quiet = ''; Location = "$($a.InstallLocation)"; Key = $a.PackageFullName; Scope = 'Store-App'
            Protected = ("$display $($a.Name)" -match $Script:ProtectedProgramPattern)
        }
    }
}

function Find-ProgramLeftovers {
    <# Reste eines deinstallierten Programms: Installationsordner und gleichnamige Ordner in Programme/ProgramData/AppData. #>
    param($Program)
    $found = New-Object System.Collections.Generic.List[object]
    $protected = Get-ProtectedFolders
    $add = {
        param($p, $why)
        if (-not $p) { return }
        $p = $p.TrimEnd('\')
        # Nie Wurzel- oder Systemordner (manche Programme tragen z. B. »C:\Program Files« als Installationsort ein)
        if ($protected | Where-Object { $_ -ieq $p }) { return }
        if ($p.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase) -or ($p -split '\\').Count -lt 3) { return }
        if ((Test-Path -LiteralPath $p -PathType Container) -and -not ($found | Where-Object { $_.Path -eq $p })) {
            $found.Add([pscustomobject]@{ Path = $p; Name = (Split-Path -Leaf $p); Size = [double](Get-DirectorySizeFast $p); IsFolder = $true; Reason = $why; Program = $Program.Name })
        }
    }
    if ($Program.Location) { & $add $Program.Location.TrimEnd('\').Trim('"') 'Installationsordner' }
    # Nur exakt passende Ordnernamen (Programmname ohne Versionsnummer) – keine Teiltreffer wie »Microsoft«
    $base = ($Program.Name -replace '\s+\(?(x64|x86|64-bit|32-bit)\)?', '' -replace '\s+v?\d+(\.\d+)+.*$', '').Trim()
    if ($base.Length -lt 4) { return $found.ToArray() }
    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA) | Where-Object { $_ }) {
        & $add (Join-Path $root $base) "Ordner in $(Split-Path -Leaf $root)"
        if ($Program.Publisher -and $Program.Publisher.Length -ge 3) { & $add (Join-Path (Join-Path $root $Program.Publisher) $base) "Ordner in $(Split-Path -Leaf $root)" }
    }
    return $found.ToArray()
}

function Invoke-ProgramUninstall {
    <# Startet den offiziellen Deinstaller und wartet; liefert, ob das Programm danach weg ist. #>
    param($Program)
    if ($Program.Kind -eq 'Store') {
        Remove-AppxPackage -Package $Program.Uninstall -ErrorAction Stop
        return -not (Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.PackageFullName -eq $Program.Uninstall })
    }
    $cmd = [Environment]::ExpandEnvironmentVariables($Program.Uninstall)
    # MSI: sichtbare Deinstallation mit Fortschritt statt Reparatur-Dialog
    if ($cmd -match 'msiexec(\.exe)?\s+/[IX]\s*(\{[0-9A-Fa-f-]+\})') { $cmd = "msiexec.exe /x $($Matches[2])" }
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$cmd`"" -Wait -PassThru -WindowStyle Hidden
    # Manche Deinstaller starten einen zweiten Prozess und beenden sich sofort – kurz auf das Verschwinden des Eintrags warten
    for ($i = 0; $i -lt 15 -and (Test-Path -LiteralPath $Program.Key); $i++) { Start-Sleep -Seconds 2 }
    return -not (Test-Path -LiteralPath $Program.Key)
}

function Invoke-ProgramListTool {
    param($Data)
    $all = @(Get-InstalledPrograms)
    Remove-FindingByKey 'Programme'
    $offer = @($all | Where-Object { -not $_.Protected } | Sort-Object Size, Name -Descending)
    $hidden = @($all | Where-Object { $_.Protected })
    $labels = @($offer | ForEach-Object {
            '{0,9} · {1} {2} · {3} · {4}{5}' -f $(if ($_.Size) { Format-Bytes $_.Size } else { '–' }), $_.Name, $_.Version, $(if ($_.Publisher) { $_.Publisher } else { 'unbekannter Hersteller' }), $(if ($_.Date) { 'installiert ' + $_.Date.ToString('dd.MM.yyyy') } else { 'Datum unbekannt' }), $(if ($_.Kind -eq 'Store') { ' · Store-App' } else { '' })
        })
    $items = @($labels) + @('') + @("Nicht angeboten (Systemkomponenten, Laufzeitbibliotheken, Treiber, Virenschutz): $($hidden.Count)") + @($hidden | Sort-Object Name | ForEach-Object { "   $($_.Name) $($_.Version)" })
    $total = [double](($all | Measure-Object Size -Sum).Sum)
    Add-Finding Speicher Info "Installierte Programme: $($all.Count) (davon $($offer.Count) deinstallierbar, ca. $(Format-Bytes $total))" -Key 'Programme' -Silent -Items $items `
        -Detail 'Nichts ist vorausgewählt. Die Deinstallation läuft über den offiziellen Deinstaller des jeweiligen Programms – dessen Fenster erscheint und will ggf. bestätigt werden. Danach sucht PC Repair Pro nach zurückgebliebenen Ordnern und bietet sie zur Auswahl an. Systemkomponenten, Laufzeitbibliotheken (z. B. Visual C++), Treiber und Virenschutz werden nicht angeboten.' `
        -FixData $offer -SelectLabels $labels -FixLabel 'Ausgewählte Programme deinstallieren' -Fix {
        param($d, $pre)
        $chosen = @($d)
        if (-not $pre) {
            for ($i = 0; $i -lt $chosen.Count; $i++) { Write-Host ('    {0,3}) {1} {2}' -f ($i + 1), $chosen[$i].Name, $chosen[$i].Version) }
            $sel = Read-Host '   Deinstallieren: Nummern oder leer = keine'
            $chosen = @((Read-Selection $sel $chosen.Count) | ForEach-Object { $chosen[$_] })
            if (-not $chosen) { return 'Nichts ausgewählt.' }
        }
        $done = @(); $failed = @(); $leftovers = @()
        foreach ($p in $chosen) {
            Write-Host "     – $($p.Name) wird deinstalliert …" -ForegroundColor Gray
            try {
                if (Invoke-ProgramUninstall $p) { $done += $p.Name; $leftovers += @(Find-ProgramLeftovers $p) } else { $failed += "$($p.Name) (abgebrochen oder noch vorhanden)" }
            } catch { $failed += "$($p.Name) ($($_.Exception.Message))" }
        }
        if ($done) { Register-Change -Beschreibung "Programme deinstalliert: $($done -join ', ')" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis 'Neu installieren über die Webseite des Herstellers bzw. den Microsoft Store.' }
        $msg = "$(@($done).Count) Programm(e) deinstalliert."
        if ($failed) { $msg += " Nicht deinstalliert: $($failed -join '; ')." }
        Remove-FindingByKey 'ProgrammReste'
        if ($leftovers) {
            $ll = @($leftovers | ForEach-Object { '{0} · {1} · {2} · {3}' -f (Format-Bytes $_.Size), $_.Program, $_.Reason, $_.Path })
            Add-Finding Speicher Info "Reste deinstallierter Programme: $(@($leftovers).Count) Ordner" -Key 'ProgrammReste' -Silent -Items $ll -SelectLabels $ll -SelectAllByDefault -FixData $leftovers `
                -Detail 'Diese Ordner sind nach der Deinstallation zurückgeblieben (Installationsordner bzw. gleichnamige Ordner in Programme, ProgramData oder AppData). Sie können Einstellungen enthalten, die bei einer Neuinstallation wieder genutzt würden. Gelöscht wird in den Papierkorb.' `
                -FixLabel 'Ausgewählte Programm-Reste in den Papierkorb verschieben' -Fix {
                param($d2, $pre2)
                $res = Remove-PathsToRecycleBin @($d2)
                if (@($res.Ok).Count) { Register-Change -Beschreibung "Programm-Reste gelöscht: $(@($res.Ok).Count) Ordner" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis (($res.Ok | ForEach-Object { $_.Path }) -join '; ') }
                Add-PermanentDeleteFinding $res.Rest
                Get-DeleteResultText $res 'Ordner'
            }
            $msg += " $(@($leftovers).Count) zurückgebliebene(r) Ordner gefunden – siehe Karte »Reste deinstallierter Programme«."
        }
        $msg
    }
    "$($offer.Count) deinstallierbare Programme gelistet – siehe Karte »Installierte Programme«."
}
