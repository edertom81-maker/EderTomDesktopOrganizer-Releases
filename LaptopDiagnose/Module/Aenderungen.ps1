<#
    Änderungsprotokoll und Rückgängig-Zentrale.
    Jede Änderung am System wird mit ihrem vorherigen Zustand in Aenderungen.json gespeichert.
    Umkehrbare Änderungen lassen sich einzeln zurücknehmen.
    Teil von LaptopDiagnose – Copyright 2026 by Eder Tom
#>

function Get-ChangeLogPath { Join-Path $BerichtOrdner 'Aenderungen.json' }

function Get-ChangeLog {
    $path = Get-ChangeLogPath
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    try {
        $raw = [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
        if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
        return @($raw | ConvertFrom-Json)
    } catch {
        return @()
    }
}

function Save-ChangeLog {
    param($Entries)
    if (-not (Test-Path -LiteralPath $BerichtOrdner)) { $null = New-Item -ItemType Directory -Path $BerichtOrdner -Force }
    $json = ConvertTo-Json -InputObject ([object[]]@($Entries | ForEach-Object { $_ })) -Depth 8
    [IO.File]::WriteAllText((Get-ChangeLogPath), $json, (New-Object System.Text.UTF8Encoding $false))
}

function Register-Change {
    <#
        Protokolliert eine Änderung. -Typ bestimmt, wie Undo-Change sie zurücknimmt.
        Typen: Autostart, Energieplan, Prozessorleistung, TRIM, Auslagerungsdatei, Registry, Feature, Wartungsaufgabe, Netzlaufwerk,
        Aufgabe, Dienst, Schattenspeicher, Protokoll
    #>
    param(
        [Parameter(Mandatory)][string]$Beschreibung,
        [Parameter(Mandatory)][string]$Typ,
        $Daten,
        [string]$Ergebnis,
        [switch]$NichtUmkehrbar,
        [string]$Hinweis
    )
    $entries = New-Object System.Collections.Generic.List[object]
    foreach ($e in Get-ChangeLog) { $entries.Add($e) }
    $entries.Add([pscustomobject]@{
            Id           = [guid]::NewGuid().ToString()
            Zeit         = (Get-Date).ToString('s')
            Computer     = $env:COMPUTERNAME
            Beschreibung = $Beschreibung
            Typ          = $Typ
            Daten        = $Daten
            Ergebnis     = $Ergebnis
            Umkehrbar    = -not $NichtUmkehrbar
            Hinweis      = $Hinweis
            Status       = 'Aktiv'
            Rueckgaengig = $null
        })
    Save-ChangeLog $entries
    $Script:ChangeCounter++
}

function Set-RegistryValueTracked {
    <# Setzt einen Registry-Wert und protokolliert den vorherigen Zustand für das Rückgängigmachen. #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [string]$Type = 'DWord',
        [Parameter(Mandatory)][string]$Beschreibung,
        [switch]$NichtUmkehrbar
    )
    $prev = $null; $existed = $false
    if (Test-Path $Path) {
        $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        if ($null -ne $item -and $item.PSObject.Properties[$Name]) { $prev = $item.$Name; $existed = $true }
        if ($prev -is [byte[]]) { $prev = [Convert]::ToBase64String($prev) }
    } else {
        $null = New-Item -Path $Path -Force
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -ErrorAction Stop
    Register-Change -Beschreibung $Beschreibung -Typ 'Registry' -NichtUmkehrbar:$NichtUmkehrbar -Daten @{
        Werte = @(@{ Path = $Path; Name = $Name; Type = $Type; Existed = $existed; Previous = $prev })
    }
}

function Undo-Change {
    param([Parameter(Mandatory)][string]$Id)
    $entries = @(Get-ChangeLog)
    $e = $entries | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
    if (-not $e) { throw 'Eintrag nicht gefunden.' }
    if (-not $e.Umkehrbar) { throw 'Diese Änderung kann nicht automatisch rückgängig gemacht werden.' }
    if ($e.Status -ne 'Aktiv') { throw 'Diese Änderung wurde bereits rückgängig gemacht.' }
    $d = $e.Daten

    switch ($e.Typ) {
        'Autostart' {
            foreach ($x in @($d.Eintraege)) {
                if ($x.Previous) {
                    Set-ItemProperty -Path $x.Approved -Name $x.Name -Value ([Convert]::FromBase64String($x.Previous)) -Type Binary
                } else {
                    Remove-ItemProperty -Path $x.Approved -Name $x.Name -ErrorAction SilentlyContinue
                }
            }
        }
        'Energieplan' { $null = & powercfg.exe /setactive $d.Previous }
        'Prozessorleistung' {
            $null = & powercfg.exe /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX ([int]$d.Previous)
            $null = & powercfg.exe /setactive SCHEME_CURRENT
        }
        'TRIM' { $null = & fsutil.exe behavior set DisableDeleteNotify ([int]$d.Previous) }
        'Auslagerungsdatei' {
            Get-CimInstance Win32_ComputerSystem | Set-CimInstance -Property @{ AutomaticManagedPagefile = [bool]$d.Previous } -ErrorAction Stop
            $Script:RebootNeeded = $true
        }
        'Registry' {
            foreach ($v in @($d.Werte)) {
                if ($v.Existed) {
                    $val = $v.Previous
                    if ($v.Type -eq 'Binary' -and $val -is [string]) { $val = [Convert]::FromBase64String($val) }
                    Set-ItemProperty -Path $v.Path -Name $v.Name -Value $val -Type $v.Type -ErrorAction Stop
                } else {
                    Remove-ItemProperty -Path $v.Path -Name $v.Name -ErrorAction SilentlyContinue
                }
            }
            if ($d.Neustart) { $Script:RebootNeeded = $true }
        }
        'Feature' {
            if ($d.Aktion -eq 'Deaktiviert') { $null = Enable-WindowsOptionalFeature -Online -FeatureName $d.Feature -NoRestart -ErrorAction Stop }
            else { $null = Disable-WindowsOptionalFeature -Online -FeatureName $d.Feature -NoRestart -ErrorAction Stop }
            $Script:RebootNeeded = $true
        }
        'Wartungsaufgabe' { Unregister-MaintenanceTask -NoLog }
        'Netzlaufwerk' { $null = New-SmbMapping -LocalPath $d.LocalPath -RemotePath $d.RemotePath -Persistent $true -ErrorAction Stop }
        'Aufgabe' { foreach ($t in @($d.Aufgaben)) { $null = Enable-ScheduledTask -TaskName $t.Name -TaskPath $t.Path -ErrorAction Stop } }
        'Dienst' {
            foreach ($s in @($d.Dienste)) {
                Set-Service -Name $s.Name -StartupType Automatic -ErrorAction Stop
                if ($s.Delayed) { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\$($s.Name)" -Name DelayedAutostart -Value 1 -Type DWord -ErrorAction SilentlyContinue }
            }
        }
        'Schattenspeicher' {
            $vol = Get-CimInstance Win32_Volume -Filter "DriveLetter='$($d.Drive)'" -ErrorAction Stop
            $size = if ([double]$d.PreviousMB * 1MB -ge [double]$vol.Capacity) { 'UNBOUNDED' } else { "$([int64]$d.PreviousMB)MB" }
            $null = & vssadmin.exe resize shadowstorage /for=$($d.Drive) /on=$($d.Drive) /maxsize=$size 2>&1
            if ($LASTEXITCODE -ne 0) { throw "vssadmin meldet Exitcode $LASTEXITCODE." }
        }
        default { throw "Unbekannter Änderungstyp: $($e.Typ)" }
    }

    foreach ($x in $entries) {
        if ($x.Id -eq $Id) {
            $x.Status = 'Rückgängig gemacht'
            $x.Rueckgaengig = (Get-Date).ToString('s')
        }
    }
    Save-ChangeLog $entries
    Write-Host "     ✔ Rückgängig gemacht: $($e.Beschreibung)" -ForegroundColor Green
    if (Get-Command Add-ActionLog -ErrorAction SilentlyContinue) { Add-ActionLog "Rückgängig: $($e.Beschreibung)" 'Wiederhergestellt' $true }
    return "Rückgängig gemacht: $($e.Beschreibung)"
}

function Show-ChangeLogConsole {
    <# Konsolenansicht: Änderungen auflisten und auf Wunsch zurücknehmen. #>
    Write-Title 'Änderungen & Rückgängig'
    $entries = @(Get-ChangeLog | Sort-Object Zeit -Descending)
    if (-not $entries) { Write-Host '   Bisher wurden keine Änderungen vorgenommen.' -ForegroundColor Gray; return }
    $undoable = @()
    foreach ($e in $entries) {
        $t = ([datetime]$e.Zeit).ToString('dd.MM.yyyy HH:mm')
        $mark = '   '
        if ($e.Umkehrbar -and $e.Status -eq 'Aktiv') { $undoable += $e; $mark = ('{0,2})' -f $undoable.Count) }
        Write-Host "   $mark $t  " -NoNewline
        Write-Host $e.Beschreibung -NoNewline
        $color = if ($e.Status -eq 'Aktiv') { 'DarkGray' } else { 'DarkYellow' }
        $state = if ($e.Status -ne 'Aktiv') { "  [$($e.Status)]" } elseif (-not $e.Umkehrbar) { '  [nicht umkehrbar]' } else { '' }
        Write-Host $state -ForegroundColor $color
    }
    if (-not $undoable) { return }
    $sel = Read-Host "`n   Nummern der Änderungen, die rückgängig gemacht werden sollen (leer = keine)"
    foreach ($i in (Read-Selection $sel $undoable.Count)) {
        try { $null = Undo-Change -Id $undoable[$i].Id }
        catch { Write-Host "     ✖ $($_.Exception.Message)" -ForegroundColor Red }
    }
}
