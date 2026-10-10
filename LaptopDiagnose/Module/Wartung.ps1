<#
    Geplante Wartung (Windows-Aufgabenplanung), Windows-Benachrichtigungen und Programm-Updates.
    Teil von LaptopDiagnose – Copyright 2026 by Eder Tom
#>

$Script:TaskPath = '\EderTom\'
$Script:TaskName = 'LaptopDiagnose Wartung'
$Script:UpdateRepo = 'edertom81-maker/EderTomDesktopOrganizer-Releases'
$Script:UpdateTagPattern = '^laptopdiagnose-v(\d+\.\d+\.\d+)$'

#region ---------- Geplante Wartung ----------

function Get-MaintenanceTask {
    $task = Get-ScheduledTask -TaskPath $Script:TaskPath -TaskName $Script:TaskName -ErrorAction SilentlyContinue
    if (-not $task) { return $null }
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
    $arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Minimized -File `"$engine`" -Modus Komplett -Unbeaufsichtigt -BerichtOrdner `"$BerichtOrdner`""
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
        $xml.LoadXml("<toast$launch><visual><binding template=""ToastGeneric""><text>$(& $esc $Title)</text><text>$(& $esc $Text)</text></binding></visual></toast>")
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

function Get-ToolUpdateInfo {
    <# Prüft den Release-Kanal auf eine neuere Version (GitHub-Release mit Tag laptopdiagnose-vX.Y.Z). #>
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Script:UpdateRepo/releases?per_page=50" -TimeoutSec 20 -UseBasicParsing `
        -Headers @{ 'User-Agent' = "LaptopDiagnose/$Script:ToolVersion"; 'Accept' = 'application/vnd.github+json' }
    $candidates = foreach ($r in @($releases)) {
        if ($r.draft -or $r.prerelease) { continue }
        if ($r.tag_name -match $Script:UpdateTagPattern) {
            $zip = @($r.assets) | Where-Object { $_.name -like 'LaptopDiagnose-*.zip' } | Select-Object -First 1
            $sha = @($r.assets) | Where-Object { $_.name -like 'LaptopDiagnose-*.zip.sha256' } | Select-Object -First 1
            if ($zip -and $sha) {
                [pscustomobject]@{ Version = [version]$Matches[1]; Notes = $r.body; ZipUrl = $zip.browser_download_url; ShaUrl = $sha.browser_download_url; Page = $r.html_url }
            }
        }
    }
    $latest = $candidates | Sort-Object Version -Descending | Select-Object -First 1
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
        $expected = ((Invoke-WebRequest -Uri $Release.ShaUrl -UseBasicParsing -Headers $hdr -TimeoutSec 30).Content -split '\s+')[0].Trim().ToUpperInvariant()
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

        Copy-Item -Path (Join-Path $root '*') -Destination $installDir -Recurse -Force -ErrorAction Stop
        Get-ChildItem -LiteralPath $installDir -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
        if (Get-Command Register-Change -ErrorAction SilentlyContinue) {
            Register-Change -Beschreibung "LaptopDiagnose auf Version $($Release.Version) aktualisiert" -Typ 'Protokoll' -NichtUmkehrbar
        }
        return "Version $($Release.Version) wurde installiert. Bitte das Programm neu starten."
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
        try { Write-Host "   ✔ $(Install-ToolUpdate -Release $u.Release)" -ForegroundColor Green }
        catch { Write-Host "   ✖ $($_.Exception.Message)" -ForegroundColor Red }
    }
}

#endregion
