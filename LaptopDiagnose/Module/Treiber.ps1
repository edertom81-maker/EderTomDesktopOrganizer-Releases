<#
    Treiber sichern: alle Fremdtreiber mit Export-WindowsDriver in den Berichtordner (Treibersicherung\<Datum>).
    Läuft als Werkzeug und automatisch vor der Installation von Treiber-Updates (höchstens einmal am Tag).
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

function Get-DriverBackupRoot { Join-Path $BerichtOrdner 'Treibersicherung' }

function Backup-Drivers {
    <# Exportiert alle Fremdtreiber. Behält die neuesten 2 Sicherungen. Liefert eine kurze Meldung. #>
    param([switch]$SkipIfToday)
    $root = Get-DriverBackupRoot
    $target = Join-Path $root (Get-Date -Format 'yyyy-MM-dd')
    if ($SkipIfToday -and (Test-Path -LiteralPath $target) -and (Get-ChildItem -LiteralPath $target -Directory -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        return "Treibersicherung von heute vorhanden: $target"
    }
    if (-not (Test-Path -LiteralPath $target)) { $null = New-Item -ItemType Directory -Path $target -Force }
    Write-Host "     Treiber werden gesichert nach $target …" -ForegroundColor Gray
    $exported = @(Export-WindowsDriver -Online -Destination $target -ErrorAction Stop)
    $size = [double](Get-DirectorySizeFast $target)
    # Ältere Sicherungen aufräumen (die neuesten 2 bleiben)
    Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -Skip 2 |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    Register-Change -Beschreibung "Treiber gesichert: $($exported.Count) Treiber ($(Format-Bytes $size))" -Typ 'Protokoll' -NichtUmkehrbar -Ergebnis $target
    "$($exported.Count) Treiber gesichert ($(Format-Bytes $size)) nach $target."
}

function Get-DriverRestoreHelp {
    @(
        'So wird ein Treiber zurückgesetzt:'
        '1. Geräte-Manager öffnen (Rechtsklick auf Start › Geräte-Manager).'
        '2. Gerät doppelklicken › Registerkarte »Treiber« › »Vorheriger Treiber« (falls verfügbar).'
        '3. Sonst: »Treiber aktualisieren« › »Auf meinem Computer nach Treibern suchen« › den Ordner der Treibersicherung wählen (Unterordner einschließen).'
        'Alternativ als Administrator: pnputil /add-driver "<Sicherungsordner>\*.inf" /subdirs /install'
    )
}

function Add-DriverBackupToolFinding {
    param([string]$Category)
    $root = Get-DriverBackupRoot
    $last = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    $detail = 'Sichert alle installierten Fremdtreiber (Grafik, WLAN, Audio, Touchpad …) in den Berichtordner. Vor der Installation von Treiber-Updates geschieht das automatisch (einmal am Tag). Die neuesten 2 Sicherungen bleiben erhalten.'
    $detail += if ($last) { " Letzte Sicherung: $($last.Name) in $($last.FullName)." } else { ' Bisher keine Sicherung vorhanden.' }
    Add-Finding $Category Info 'Treiber sichern' -Detail $detail -Items (Get-DriverRestoreHelp) -Silent -Repeatable `
        -FixLabel 'Alle Treiber jetzt sichern (ca. 1–3 Minuten)' -Fix { param($d) Backup-Drivers }
}
