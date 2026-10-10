<#
    Programmname, Gerätetyp (PC oder Laptop) und Anpassung von Verknüpfungen und »Installierte Apps« nach Updates.
    Wird auch direkt von der Oberfläche geladen, darf daher nur Funktionen ohne Abhängigkeiten enthalten.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:AppName = 'PC Repair Pro'
$Script:AppSlogan = 'Diagnose • Repair • Keep it running'
$Script:AppShortcutName = 'PC Repair Pro.lnk'
$Script:LegacyShortcutNames = @('Laptop-Diagnose.lnk')
$Script:UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\EderTom.LaptopDiagnose'
$Script:DeviceKindCache = $null

function Get-DeviceKind {
    <#
        »Laptop« oder »Desktop«. Grundlage ist die Gehäuseart laut Firmware; ist sie nicht eindeutig,
        entscheidet, ob ein Akku vorhanden ist.
    #>
    if ($Script:DeviceKindCache) { return $Script:DeviceKindCache }
    $kind = $null
    try {
        $types = @((Get-CimInstance Win32_SystemEnclosure -ErrorAction Stop).ChassisTypes | ForEach-Object { [int]$_ })
        # 8–14, 18, 21, 30–32: tragbare Geräte (Laptop, Notebook, Convertible, Tablet …)
        if ($types | Where-Object { $_ -in 8, 9, 10, 11, 12, 14, 18, 21, 30, 31, 32 }) { $kind = 'Laptop' }
        elseif ($types | Where-Object { $_ -in 3, 4, 5, 6, 7, 13, 15, 16, 17, 23, 24, 28, 35, 36 }) { $kind = 'Desktop' }
    } catch { }
    if (-not $kind) {
        $hasBattery = [bool](Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue | Select-Object -First 1)
        $kind = if ($hasBattery) { 'Laptop' } else { 'Desktop' }
    }
    $Script:DeviceKindCache = $kind
    return $kind
}

function Get-DeviceWord {
    <# Bezeichnung für Texte: »Laptop« bzw. »PC«. #>
    if ((Get-DeviceKind) -eq 'Laptop') { 'Laptop' } else { 'PC' }
}

function Update-AppRegistration {
    <#
        Programm-Updates kopieren nur Dateien. Damit Name, Version und Symbol auch im Startmenü, auf dem Desktop und
        unter »Installierte Apps« stimmen, gleicht die neue Version diese Einträge beim Start einmalig an.
    #>
    param([Parameter(Mandatory)][string]$InstallDir, [Parameter(Mandatory)][string]$Version)
    if (-not (Test-Path -LiteralPath $Script:UninstallKey)) { return $false }   # nicht installiert (z. B. direkt aus dem Ordner gestartet)
    $icon = Join-Path $InstallDir 'LaptopDiagnose.ico'
    $changed = $false
    try {
        $cur = Get-ItemProperty -Path $Script:UninstallKey -ErrorAction Stop
        if ($cur.DisplayName -ne $Script:AppName -or $cur.DisplayVersion -ne $Version) {
            Set-ItemProperty -Path $Script:UninstallKey -Name DisplayName -Value $Script:AppName
            Set-ItemProperty -Path $Script:UninstallKey -Name DisplayVersion -Value $Version
            Set-ItemProperty -Path $Script:UninstallKey -Name DisplayIcon -Value $icon
            $changed = $true
        }
    } catch { }
    try {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($folder in @([Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('Desktop')) | Where-Object { $_ }) {
            $target = Join-Path $folder $Script:AppShortcutName
            foreach ($oldName in $Script:LegacyShortcutNames) {
                $old = Join-Path $folder $oldName
                if (-not (Test-Path -LiteralPath $old)) { continue }
                $o = $shell.CreateShortcut($old)
                $n = $shell.CreateShortcut($target)
                $n.TargetPath = $o.TargetPath
                $n.Arguments = $o.Arguments
                $n.WorkingDirectory = $o.WorkingDirectory
                $n.WindowStyle = $o.WindowStyle
                $n.IconLocation = "$icon,0"
                $n.Description = "$Script:AppName – Fehler finden, Leistung verbessern, Updates installieren · © 2026 Eder Tom"
                $n.Save()
                Remove-Item -LiteralPath $old -Force -ErrorAction SilentlyContinue
                $changed = $true
            }
        }
    } catch { }
    return $changed
}
