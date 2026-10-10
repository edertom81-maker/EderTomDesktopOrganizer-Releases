<#
    Geplante Wartung (Windows-Aufgabenplanung), Windows-Benachrichtigungen und Programm-Updates.
    Teil von LaptopDiagnose – Copyright 2026 by Eder Tom
#>

$Script:TaskPath = '\EderTom\'
$Script:TaskName = 'LaptopDiagnose Wartung'
$Script:UpdateRepo = 'edertom81-maker/EderTomDesktopOrganizer-Releases'
$Script:UpdateTagPattern = '^laptopdiagnose-v(\d+\.\d+\.\d+)$'
# Update-Kanal: Manifest im Hauptzweig des Repositorys (Paket liegt daneben). GitHub-Releases bleiben als Ausweichweg.
$Script:UpdateManifestUrl = 'https://raw.githubusercontent.com/edertom81-maker/EderTomDesktopOrganizer-Releases/main/LaptopDiagnose/update/update.json'

#region ---------- Geplante Wartung ----------

function Get-MaintenanceTask {
    $task = Get-ScheduledTask -TaskPath $Script:TaskPath -TaskName $Script:TaskName -ErrorAction SilentlyContinue
    if (-not $task) { return $null }
    if (@($task.Actions)[0].Arguments -match '-BerichtOrdner') { Update-MaintenanceTaskFolder }
    $info = Get-ScheduledTaskInfo -InputObject $task -ErrorAction SilentlyContinue
    $trigger = @($task.Triggers)[0]
    $desc = 'Geplant'
    if ($trigger) {
        $at = ([datetime]$trigger.StartBoundary).ToString('HH:mm')
        if ($trigger.CimClass.CimClassName -eq 'MSFT_TaskDailyTrigger') { $desc = "Täglich um $at Uhr" }
        else {
            $dayNames = @{ 1 = 'Sonntag'; 2 = 'Montag'; 4 = 'Dienstag'; 8 = 'Mittwoch'; 16 = 'Donnerstag'; 32 = 'Freitag'; 64 = 'Samstag' }
            $days = @($dayNames.Keys | Sort-Object | Where-Object { [int]$trigger.DaysOfWeek -band $_ } | ForEach-Object { $dayNames[$_] }) -join ', '
            $desc = "Wöchentlich am $days um $at Uhr"
        }
    }
    return [pscustomobject]@{
        Beschreibung  = $desc
        Aktiviert     = $task.State -ne 'Disabled'
        NaechsterLauf = $info.NextRunTime
        LetzterLauf   = $(if ($info.LastRunTime -and $info.LastRunTime.Year -gt 2000) { $info.LastRunTime })
        Ergebnis      = $info.LastTaskResult
    }
}

function Register-MaintenanceTask {
    <# Richtet eine regelmäßige, rein prüfende Komplett-Diagnose ein. Bei kritischen Funden erscheint eine Benachrichtigung. #>
    param(
        [ValidateSet('Woechentlich', 'Taeglich')][string]$Intervall = 'Woechentlich',
        [ValidateSet('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')][string]$Tag = 'Monday',
        [string]$Uhrzeit = '10:00'
    )
    $engine = Join-Path $Script:InstallDir 'LaptopDiagnose.ps1'
    # Ohne -BerichtOrdner: die Diagnose verwendet immer den in den Einstellungen gewählten Ordner
    $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$engine`" -Modus Komplett -Unbeaufsichtigt"
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg -WorkingDirectory (Split-Path -Parent $engine)
    $time = [datetime]::ParseExact($Uhrzeit, 'HH:mm', $null)
    $trigger = if ($Intervall -eq 'Taeglich') { New-ScheduledTaskTrigger -Daily -At $time } else { New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Tag -At $time }
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew
    $existed = [bool](Get-MaintenanceTask)
    $null = Register-ScheduledTask -TaskPath $Script:TaskPath -TaskName $Script:TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
        -Description 'Regelmäßige Laptop-Diagnose (nur prüfen, keine Änderungen). Meldet kritische Probleme per Windows-Benachrichtigung. Eder Tom.' -Force -ErrorAction Stop
    $t = Get-MaintenanceTask
    if (-not $existed -and (Get-Command Register-Change -ErrorAction SilentlyContinue)) {
        Register-Change -Beschreibung "Geplante Wartung eingerichtet ($($t.Beschreibung))" -Typ 'Wartungsaufgabe' -Daten @{}
    }
    return "Geplante Wartung eingerichtet: $($t.Beschreibung). Nächster Lauf: $('{0:dd.MM.yyyy HH:mm}' -f $t.NaechsterLauf)."
}

function Unregister-MaintenanceTask {
    param([switch]$NoLog)
    if (-not (Get-MaintenanceTask)) { return 'Es ist keine geplante Wartung eingerichtet.' }
    Unregister-ScheduledTask -TaskPath $Script:TaskPath -TaskName $Script:TaskName -Confirm:$false -ErrorAction Stop
    if (-not $NoLog -and (Get-Command Register-Change -ErrorAction SilentlyContinue)) {
        Register-Change -Beschreibung 'Geplante Wartung entfernt' -Typ 'Protokoll' -NichtUmkehrbar
    }
    return 'Geplante Wartung entfernt.'
}

function Show-MaintenanceConsole {
    Write-Title 'Geplante Wartung'
    $t = Get-MaintenanceTask
    if ($t) {
        Write-Host "   Eingerichtet: $($t.Beschreibung)" -ForegroundColor Green
        if ($t.NaechsterLauf) { Write-Host ('   Nächster Lauf: {0:dd.MM.yyyy HH:mm}' -f $t.NaechsterLauf) -ForegroundColor Gray }
        if ($t.LetzterLauf) { Write-Host ('   Letzter Lauf:  {0:dd.MM.yyyy HH:mm}' -f $t.LetzterLauf) -ForegroundColor Gray }
        if (Read-YesNo 'Geplante Wartung entfernen?' $false) { Write-Host "   $(Unregister-MaintenanceTask)" -ForegroundColor Green }
        return
    }
    Write-Host '   Die geplante Wartung prüft den Laptop regelmäßig im Hintergrund (ohne Änderungen),' -ForegroundColor Gray
    Write-Host '   speichert Bericht und Verlauf und meldet kritische Probleme per Windows-Benachrichtigung.' -ForegroundColor Gray
    if (-not (Read-YesNo 'Jetzt einrichten?' $true)) { return }
    $daily = (Read-Host '   [W]öchentlich oder [T]äglich? (Standard: W)') -match '^\s*t'
    $days = @{ '1' = 'Monday'; '2' = 'Tuesday'; '3' = 'Wednesday'; '4' = 'Thursday'; '5' = 'Friday'; '6' = 'Saturday'; '7' = 'Sunday' }
    $tag = 'Monday'
    if (-not $daily) {
        $d = Read-Host '   Wochentag 1=Mo 2=Di 3=Mi 4=Do 5=Fr 6=Sa 7=So (Standard: 1)'
        if ($days.ContainsKey($d.Trim())) { $tag = $days[$d.Trim()] }
    }
    $zeit = Read-Host '   Uhrzeit HH:mm (Standard: 10:00)'
    if ($zeit -notmatch '^\d{2}:\d{2}$') { $zeit = '10:00' }
    try {
        $msg = Register-MaintenanceTask -Intervall $(if ($daily) { 'Taeglich' } else { 'Woechentlich' }) -Tag $tag -Uhrzeit $zeit
        Write-Host "   ✔ $msg" -ForegroundColor Green
    } catch { Write-Host "   ✖ $($_.Exception.Message)" -ForegroundColor Red }
}

#endregion

#region ---------- Benachrichtigungen ----------

function Show-Notification {
    <# Zeigt eine Windows-Benachrichtigung; ein Klick öffnet optional eine Datei (z. B. den Bericht). #>
    param([string]$Title, [string]$Text, [string]$OpenPath)
    $esc = { param($t) [System.Security.SecurityElement]::Escape("$t") }
    $launch = ''
    if ($OpenPath) { $launch = " activationType=""protocol"" launch=""$(& $esc ([Uri]$OpenPath).AbsoluteUri)""" }
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast$launch><visual><binding template=""ToastGeneric""><text>$(& $esc $Title)</text><text>$(& $esc $Text)</text><text placement=""attribution"">© 2026 Eder Tom</text></binding></visual></toast>")
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
        return $true
    } catch {
        try {
            Add-Type -AssemblyName System.Windows.Forms, System.Drawing
            $icon = New-Object System.Windows.Forms.NotifyIcon
            $icon.Icon = [System.Drawing.SystemIcons]::Information
            $icon.Visible = $true
            $icon.ShowBalloonTip(15000, $Title, $Text, [System.Windows.Forms.ToolTipIcon]::Warning)
            Start-Sleep -Seconds 16
            $icon.Dispose()
            return $true
        } catch { return $false }
    }
}

#endregion

#region ---------- Programm-Updates ----------

function Get-ManifestUpdate {
    <# Liest das Update-Manifest (update.json) aus dem Repository und prüft es auf plausible Werte. #>
    param([int]$TimeoutSec = 20)
    $hdr = @{ 'User-Agent' = "LaptopDiagnose/$Script:ToolVersion"; 'Cache-Control' = 'no-cache' }
    $raw = (Invoke-WebRequest -Uri "$($Script:UpdateManifestUrl)?t=$([DateTime]::UtcNow.Ticks)" -UseBasicParsing -Headers $hdr -TimeoutSec $TimeoutSec).Content
    if ($raw -is [byte[]]) { $raw = [Text.Encoding]::UTF8.GetString($raw) }
    $m = "$raw".TrimStart([char]0xFEFF) | ConvertFrom-Json
    if ("$($m.version)" -notmatch '^\d+\.\d+\.\d+$') { throw 'Update-Manifest enthält keine gültige Version.' }
    if ("$($m.datei)" -notmatch '^LaptopDiagnose-[\d\.]+\.zip$') { throw 'Update-Manifest enthält keinen gültigen Dateinamen.' }
    if ("$($m.sha256)" -notmatch '^[0-9a-fA-F]{64}$') { throw 'Update-Manifest enthält keine gültige Prüfsumme.' }
    $base = $Script:UpdateManifestUrl.Substring(0, $Script:UpdateManifestUrl.LastIndexOf('/') + 1)
    return [pscustomobject]@{
        Version = [version]$m.version
        Notes   = "$($m.notizen)"
        ZipUrl  = $base + $m.datei
        Sha256  = "$($m.sha256)"
        Page    = 'https://github.com/edertom81-maker/EderTomDesktopOrganizer-Releases/tree/main/LaptopDiagnose'
    }
}

function Get-ToolUpdateInfo {
    <# Prüft den Update-Kanal (Manifest im Repository, ersatzweise GitHub-Releases mit Tag laptopdiagnose-vX.Y.Z). #>
    param([int]$TimeoutSec = 20)
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $candidates = @()
    $errors = @()
    try { $candidates += Get-ManifestUpdate -TimeoutSec $TimeoutSec } catch { $errors += $_.Exception.Message }
    $releases = @()
    if (-not $candidates) {
        # Ausweichweg nur, wenn das Manifest nicht erreichbar war
        try {
            $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Script:UpdateRepo/releases?per_page=50" -TimeoutSec $TimeoutSec -UseBasicParsing `
                -Headers @{ 'User-Agent' = "LaptopDiagnose/$Script:ToolVersion"; 'Accept' = 'application/vnd.github+json' }
        } catch { $errors += $_.Exception.Message }
    }
    if (-not $candidates -and $errors.Count -ge 2) { throw "Update-Prüfung nicht möglich: $($errors[0])" }
    $candidates += foreach ($r in @($releases)) {
        if ($r.draft -or $r.prerelease) { continue }
        if ($r.tag_name -match $Script:UpdateTagPattern) {
            $zip = @($r.assets) | Where-Object { $_.name -like 'LaptopDiagnose-*.zip' } | Select-Object -First 1
            $sha = @($r.assets) | Where-Object { $_.name -like 'LaptopDiagnose-*.zip.sha256' } | Select-Object -First 1
            if ($zip -and $sha) {
                [pscustomobject]@{ Version = [version]$Matches[1]; Notes = $r.body; ZipUrl = $zip.browser_download_url; ShaUrl = $sha.browser_download_url; Page = $r.html_url }
            }
        }
    }
    $latest = $candidates | Where-Object { $_ } | Sort-Object Version -Descending | Select-Object -First 1
    $current = [version]$Script:ToolVersion
    return [pscustomobject]@{
        Aktuell     = $current
        Verfuegbar  = $(if ($latest) { $latest.Version })
        IstNeuer    = [bool]($latest -and $latest.Version -gt $current)
        Release     = $latest
    }
}

function Test-SignatureIntact {
    <#
        Signatur vorhanden und Datei unverändert. »UnknownError«/»NotTrusted« bedeuten bei einem
        selbst ausgestellten Zertifikat nur, dass Windows der Zertifikatskette nicht vertraut.
    #>
    param($Signature)
    return [bool]($Signature -and $Signature.SignerCertificate -and "$($Signature.Status)" -in 'Valid', 'UnknownError', 'NotTrusted')
}

function Install-ToolUpdate {
    <# Lädt das Update, prüft SHA-256 und Signatur und ersetzt die Programmdateien. #>
    param([Parameter(Mandatory)]$Release)
    $installDir = $Script:InstallDir
    $work = Join-Path $env:TEMP ('LaptopDiagnoseUpdate_' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $work -Force
    try {
        $zipPath = Join-Path $work 'update.zip'
        $hdr = @{ 'User-Agent' = "LaptopDiagnose/$Script:ToolVersion" }
        Invoke-WebRequest -Uri $Release.ZipUrl -OutFile $zipPath -UseBasicParsing -Headers $hdr -TimeoutSec 120
        $expected = if ($Release.Sha256) { "$($Release.Sha256)".ToUpperInvariant() }
        else { ((Invoke-WebRequest -Uri $Release.ShaUrl -UseBasicParsing -Headers $hdr -TimeoutSec 30).Content -split '\s+')[0].Trim().ToUpperInvariant() }
        $actual = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($expected -ne $actual) { throw 'Prüfsumme stimmt nicht überein – Update wurde verworfen.' }

        $extract = Join-Path $work 'files'
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extract -Force
        $root = $extract
        if (-not (Test-Path (Join-Path $root 'LaptopDiagnose.ps1'))) {
            $sub = Get-ChildItem -LiteralPath $extract -Directory | Select-Object -First 1
            if ($sub) { $root = $sub.FullName }
        }
        foreach ($required in 'LaptopDiagnose.ps1', 'LaptopDiagnoseGUI.ps1') {
            if (-not (Test-Path (Join-Path $root $required))) { throw "Updatepaket unvollständig ($required fehlt)." }
        }

        # Signaturprüfung: Ist die installierte Version signiert, muss jede Datei des Updates mit demselben
        # Zertifikat signiert sein (Zertifikat wird »angeheftet«). Selbst ausgestellte Zertifikate sind erlaubt,
        # solange die Datei unverändert ist – eine manipulierte Datei (HashMismatch) wird immer abgelehnt.
        $currentSig = Get-AuthenticodeSignature -FilePath (Join-Path $installDir 'LaptopDiagnose.ps1')
        $pinned = if (Test-SignatureIntact $currentSig) { $currentSig.SignerCertificate.Thumbprint }
        foreach ($ps1 in Get-ChildItem -LiteralPath $root -Filter '*.ps1' -Recurse) {
            $sig = Get-AuthenticodeSignature -FilePath $ps1.FullName
            if ("$($sig.Status)" -eq 'HashMismatch') {
                throw "$($ps1.Name) wurde nach dem Signieren verändert – Update wurde verworfen."
            }
            if ($pinned) {
                if (-not (Test-SignatureIntact $sig) -or $sig.SignerCertificate.Thumbprint -ne $pinned) {
                    throw "$($ps1.Name) ist nicht mit demselben Zertifikat signiert wie die installierte Version – Update wurde verworfen."
                }
            } elseif ("$($sig.Status)" -notin 'Valid', 'NotSigned', 'UnknownError', 'NotTrusted') {
                throw "Signatur von $($ps1.Name) ist ungültig ($($sig.Status)) – Update wurde verworfen."
            }
        }

        # Datei für Datei kopieren (mit Wiederholung): erst Begleitdateien, dann die Skripte, LaptopDiagnose.ps1 zuletzt.
        # Gesperrte Begleitdateien (z. B. ein geöffnetes Symbol) verhindern das Update nicht. Scheitert ein Skript,
        # werden die bisherigen Skripte aus einer Sicherung wiederhergestellt.
        $rank = { if ($_.Name -eq 'LaptopDiagnose.ps1') { 2 } elseif ($_.Extension -eq '.ps1') { 1 } else { 0 } }
        $files = @(Get-ChildItem -LiteralPath $root -Recurse -File | Sort-Object $rank, FullName)
        $backup = Join-Path $work 'backup'
        $oldScripts = @(Get-ChildItem -LiteralPath $installDir -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue)
        foreach ($o in $oldScripts) {
            $b = Join-Path $backup $o.FullName.Substring($installDir.Length).TrimStart('\', '/')
            $null = New-Item -ItemType Directory -Path (Split-Path -Parent $b) -Force
            Copy-Item -LiteralPath $o.FullName -Destination $b -Force
        }
        $skipped = @()
        try {
            foreach ($src in $files) {
                $rel = $src.FullName.Substring($root.Length).TrimStart('\', '/')
                $dst = Join-Path $installDir $rel
                $dstDir = Split-Path -Parent $dst
                if (-not (Test-Path -LiteralPath $dstDir)) { $null = New-Item -ItemType Directory -Path $dstDir -Force }
                $copied = $false
                for ($try = 0; $try -lt 5 -and -not $copied; $try++) {
                    try { Copy-Item -LiteralPath $src.FullName -Destination $dst -Force -ErrorAction Stop; $copied = $true }
                    catch { Start-Sleep -Milliseconds 400 }
                }
                if (-not $copied) {
                    if ($src.Extension -eq '.ps1') { throw "$rel konnte nicht ersetzt werden (Datei gesperrt). Bitte das Programm schließen und das Update über die Konsolenversion oder das Setup installieren." }
                    $skipped += $rel
                }
            }
        } catch {
            foreach ($o in Get-ChildItem -LiteralPath $backup -Recurse -File -ErrorAction SilentlyContinue) {
                $orig = Join-Path $installDir $o.FullName.Substring($backup.Length).TrimStart('\', '/')
                try { Copy-Item -LiteralPath $o.FullName -Destination $orig -Force -ErrorAction Stop } catch { }
            }
            throw "$($_.Exception.Message) Die bisherige Version wurde wiederhergestellt."
        }
        $installed = if ((Get-Content -LiteralPath (Join-Path $installDir 'LaptopDiagnose.ps1') -Raw) -match "ToolVersion = '([\d\.]+)'") { $Matches[1] }
        if ("$installed" -ne "$($Release.Version)") { throw "Das Update wurde nicht vollständig installiert (installiert: $installed, erwartet: $($Release.Version))." }
        Get-ChildItem -LiteralPath $installDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
        if (Get-Command Register-Change -ErrorAction SilentlyContinue) {
            Register-Change -Beschreibung "LaptopDiagnose auf Version $($Release.Version) aktualisiert" -Typ 'Protokoll' -NichtUmkehrbar
        }
        $note = if ($skipped) { " Nicht ersetzt (in Benutzung): $($skipped -join ', ')." } else { '' }
        return "Version $($Release.Version) wurde installiert.$note Bitte das Programm neu starten."
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Show-ToolUpdateConsole {
    Write-Title 'Programm-Updates'
    try {
        $u = Get-ToolUpdateInfo
    } catch {
        Write-Host "   Update-Prüfung nicht möglich: $($_.Exception.Message)" -ForegroundColor Yellow
        return
    }
    Write-Host "   Installierte Version: $($u.Aktuell)"
    if (-not $u.IstNeuer) { Write-Host '   Das Programm ist auf dem neuesten Stand.' -ForegroundColor Green; return }
    Write-Host "   Neue Version verfügbar: $($u.Verfuegbar)" -ForegroundColor Cyan
    if ($u.Release.Notes) { Write-Host ("   " + ($u.Release.Notes -replace "`r?`n", "`n   ")) -ForegroundColor Gray }
    if ($NurPruefen) { return }
    if (Read-YesNo 'Jetzt herunterladen und installieren?' $true) {
        try { Write-Host "   ✔ $(Install-ToolUpdate -Release $u.Release)" -ForegroundColor Green; $Script:UpdateHint = $null }
        catch { Write-Host "   ✖ $($_.Exception.Message)" -ForegroundColor Red }
    }
}

#endregion
