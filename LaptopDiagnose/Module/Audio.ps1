<#
    Audio und Bluetooth: Standard-Ausgabe- und Eingabegerät, deaktivierte Audiogeräte, Audiodienste, Treiberfehler,
    Bluetooth-Adapter und -Dienst, Geräte mit Fehler; dazu ein Lautsprechertest links/rechts.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>

$Script:MmDevRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio'

function Get-AudioEndpoints {
    <# Audio-Endpunkte aus der Registry: Name, Zustand und ob es das Standardgerät ist (zuletzt als Standard gesetzt). #>
    param([ValidateSet('Render', 'Capture')][string]$Flow)
    $list = @(foreach ($k in @(Get-ChildItem -Path (Join-Path $Script:MmDevRoot $Flow) -ErrorAction SilentlyContinue)) {
            $state = [int](Get-ItemProperty -Path $k.PSPath -Name DeviceState -ErrorAction SilentlyContinue).DeviceState
            $props = Get-ItemProperty -Path (Join-Path $k.PSPath 'Properties') -ErrorAction SilentlyContinue
            $desc = "$($props.'{a45c254e-df1c-4efd-8020-67d146a850e0},2')"
            $iface = "$($props.'{b3f8fa53-0004-438e-9003-51a46e139bfc},6')"
            $lvl = (Get-ItemProperty -Path $k.PSPath -Name 'Level:0' -ErrorAction SilentlyContinue).'Level:0'
            $ts = if ($lvl -is [byte[]] -and $lvl.Count -ge 8) { [BitConverter]::ToInt64($lvl, 0) } else { 0 }
            [pscustomobject]@{ Id = $k.PSChildName; Name = $(if ($iface) { "$desc ($iface)" } else { $desc }); State = $state; DefaultStamp = $ts; IsDefault = $false }
        })
    $active = @($list | Where-Object { $_.State -eq 1 } | Sort-Object DefaultStamp -Descending)
    if ($active -and $active[0].DefaultStamp -gt 0) { $active[0].IsDefault = $true }
    return $list
}

function Add-AudioFindings {
    param([string]$Category)
    $issues = 0
    # Audiodienste
    $svc = @(Get-Service -Name Audiosrv, AudioEndpointBuilder -ErrorAction SilentlyContinue | Where-Object { $_.Status -ne 'Running' })
    if ($svc) {
        $issues++
        Add-Finding $Category Warnung "Audiodienst läuft nicht: $(($svc | ForEach-Object { $_.DisplayName }) -join ', ')" -Detail 'Ohne diese Dienste gibt es keinen Ton, und das Lautsprechersymbol zeigt ein rotes Kreuz.' `
            -FixLabel 'Audiodienste starten' -Fix {
            param($d)
            foreach ($n in 'AudioEndpointBuilder', 'Audiosrv') { Set-Service -Name $n -StartupType Automatic -ErrorAction SilentlyContinue; Start-Service -Name $n -ErrorAction Stop }
            'Audiodienste gestartet.'
        }
    }
    # Ausgabe- und Eingabegeräte
    $render = @(Get-AudioEndpoints Render)
    $capture = @(Get-AudioEndpoints Capture)
    $out = @($render | Where-Object { $_.State -eq 1 })
    $def = $out | Where-Object { $_.IsDefault } | Select-Object -First 1
    $mic = @($capture | Where-Object { $_.State -eq 1 })
    $defMic = $mic | Where-Object { $_.IsDefault } | Select-Object -First 1
    if ($render -and -not $out) {
        $issues++
        Add-Finding $Category Warnung 'Kein aktives Audio-Ausgabegerät' -Detail 'Alle Lautsprecher/Kopfhörer sind deaktiviert oder nicht angeschlossen. Kopfhörer/Lautsprecher anschließen oder ein deaktiviertes Gerät aktivieren (siehe unten).'
    }
    # Deaktivierte Audio-Endpunkte (Geräte-Manager: Code 22)
    $disabled = @(Get-PnpDevice -Class AudioEndpoint -ErrorAction SilentlyContinue | Where-Object { [int]$_.ConfigManagerErrorCode -eq 22 })
    if ($disabled) {
        $issues++
        Add-Finding $Category Info "$($disabled.Count) deaktivierte(s) Audiogerät(e)" -Items @($disabled | ForEach-Object { $_.FriendlyName }) `
            -Detail 'Deaktivierte Lautsprecher oder Mikrofone erscheinen nicht in der Auswahl. Aktivieren ist über »Änderungen« umkehrbar.' `
            -SelectLabels @($disabled | ForEach-Object { $_.FriendlyName }) -SelectAllByDefault -FixData @($disabled | ForEach-Object { [pscustomobject]@{ Id = $_.InstanceId; Name = $_.FriendlyName } }) -FixLabel 'Ausgewählte Audiogeräte aktivieren' -Fix {
            param($d, $pre)
            foreach ($x in @($d)) { Enable-PnpDevice -InstanceId $x.Id -Confirm:$false -ErrorAction Stop }
            Register-Change -Beschreibung "Audiogeräte aktiviert: $((@($d) | ForEach-Object { $_.Name }) -join ', ')" -Typ 'Geraet' -Daten @{ Ids = @($d | ForEach-Object { $_.Id }) }
            "$(@($d).Count) Gerät(e) aktiviert. Rückgängig über »Änderungen«."
        }
    }
    # Treiberfehler bei Sound-Geräten
    $media = @(Get-PnpDevice -Class MEDIA -ErrorAction SilentlyContinue | Where-Object { [int]$_.ConfigManagerErrorCode -notin 0, 22, 45 })
    if ($media) {
        $issues++
        Add-Finding $Category Warnung "Soundkarte mit Treiberproblem: $(($media | ForEach-Object { $_.FriendlyName }) -join ', ')" `
            -Detail 'Der Treiber der Soundkarte meldet einen Fehler – oft nach einem Windows-Update. Abhilfe: Treiber des Geräteherstellers (bzw. Realtek/Intel über die Support-Seite des Laptop-Herstellers) neu installieren oder im Geräte-Manager »Vorheriger Treiber«.' `
            -FixLabel 'Geräte-Manager öffnen' -Fix { param($d) Start-Process devmgmt.msc; 'Geräte-Manager geöffnet.' }
    }
    $items = @()
    if ($def) { $items += "Standard-Ausgabe: $($def.Name)" }
    $items += @($out | Where-Object { -not $_.IsDefault } | ForEach-Object { "weitere Ausgabe: $($_.Name)" })
    if ($defMic) { $items += "Standard-Mikrofon: $($defMic.Name)" }
    $hint = ''
    if ($def -and $def.Name -match '(?i)HDMI|DisplayPort|NVIDIA High Definition|AMD High Definition|Intel\(R\) Display|Monitor') { $hint = ' Hinweis: Der Ton geht an den Bildschirm (HDMI/DisplayPort) – hat der Bildschirm keine Lautsprecher, bleibt es still. Ausgabegerät über das Lautsprechersymbol in der Taskleiste wechseln.' }
    if (-not $issues) {
        $sev = if ($hint) { 'Info' } else { 'OK' }
        Add-Finding $Category $sev "Audio in Ordnung$(if ($def) { " – Ausgabe: $($def.Name)" })" -Items $items `
            -Detail ("Kein Ton bei einer einzelnen App? Im Lautstärkemixer kann sie stummgeschaltet oder sehr leise sein.$hint") `
            -FixLabel 'Lautstärkemixer öffnen' -Fix { param($d) Start-Process 'ms-settings:apps-volume'; 'Lautstärkemixer geöffnet.' }
    }
}

function Add-BluetoothFindings {
    param([string]$Category)
    $bt = @(Get-PnpDevice -Class Bluetooth -ErrorAction SilentlyContinue)
    $radios = @($bt | Where-Object { $_.InstanceId -match '^(USB|PCI|ACPI)\\' })
    if (-not $radios) { Add-Finding $Category OK 'Kein Bluetooth-Adapter vorhanden' -Silent; return }
    $issues = 0
    $off = @($radios | Where-Object { [int]$_.ConfigManagerErrorCode -eq 22 })
    $err = @($radios | Where-Object { [int]$_.ConfigManagerErrorCode -notin 0, 22, 45 })
    if ($off) {
        $issues++
        Add-Finding $Category Warnung 'Bluetooth-Adapter ist im Geräte-Manager deaktiviert' -Items @($off | ForEach-Object { $_.FriendlyName }) `
            -Detail 'Dann fehlt Bluetooth komplett in den Einstellungen. Aktivieren ist über »Änderungen« umkehrbar.' `
            -FixLabel 'Bluetooth-Adapter aktivieren' -FixData @($off | ForEach-Object { $_.InstanceId }) -Fix {
            param($d)
            foreach ($id in @($d)) { Enable-PnpDevice -InstanceId $id -Confirm:$false -ErrorAction Stop }
            Register-Change -Beschreibung 'Bluetooth-Adapter aktiviert' -Typ 'Geraet' -Daten @{ Ids = @($d) }
            'Bluetooth-Adapter aktiviert. Rückgängig über »Änderungen«.'
        }
    }
    if ($err) {
        $issues++
        Add-Finding $Category Warnung "Bluetooth-Adapter mit Treiberproblem: $(($err | ForEach-Object { $_.FriendlyName }) -join ', ')" `
            -Detail 'Abhilfe: Laptop komplett herunterfahren (nicht Neustart) und neu starten; hilft das nicht, den Bluetooth-/WLAN-Treiber des Geräteherstellers neu installieren.' `
            -FixLabel 'Geräte-Manager öffnen' -Fix { param($d) Start-Process devmgmt.msc; 'Geräte-Manager geöffnet.' }
    }
    $svc = Get-Service -Name bthserv -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
        $issues++
        Add-Finding $Category Warnung 'Der Bluetooth-Unterstützungsdienst läuft nicht' -Detail 'Ohne ihn lassen sich keine Geräte koppeln oder verbinden.' `
            -FixLabel 'Bluetooth-Dienst starten' -Fix {
            param($d)
            Set-Service -Name bthserv -StartupType Manual -ErrorAction SilentlyContinue
            Start-Service -Name bthserv -ErrorAction Stop
            'Bluetooth-Dienst gestartet.'
        }
    }
    # Gekoppelte Geräte mit Fehler (nicht nur »nicht verbunden«)
    $paired = @($bt | Where-Object { $_.InstanceId -match '^(BTHENUM|BTHLE|BTHLEDEVICE)\\' })
    $broken = @($paired | Where-Object { [int]$_.ConfigManagerErrorCode -notin 0, 45, 22 } | Sort-Object FriendlyName -Unique)
    if ($broken) {
        $issues++
        Add-Finding $Category Warnung "$($broken.Count) Bluetooth-Gerät(e) mit Fehler" -Items @($broken | ForEach-Object { $_.FriendlyName }) `
            -Detail 'Häufig nach Updates oder wenn ein Gerät mit einem anderen Computer/Handy gekoppelt wurde: In den Bluetooth-Einstellungen das Gerät »Entfernen«, am Gerät den Kopplungsmodus starten und neu hinzufügen.' `
            -FixLabel 'Bluetooth-Einstellungen öffnen' -Fix { param($d) Start-Process 'ms-settings:bluetooth'; 'Bluetooth-Einstellungen geöffnet: Gerät entfernen und neu koppeln.' }
    }
    if (-not $issues) {
        $names = @($paired | Where-Object { $_.FriendlyName -and $_.FriendlyName -notmatch '(?i)Service|Dienst|Protocol|Protokoll|Gateway|Avrcp|Transport|Hands-?free|Enumerator' } | ForEach-Object { $_.FriendlyName } | Sort-Object -Unique)
        Add-Finding $Category OK "Bluetooth in Ordnung ($($radios[0].FriendlyName))" -Items @($names | Select-Object -First 15 | ForEach-Object { "gekoppelt: $_" })
    }
}

function New-StereoToneWav {
    <# WAV im Speicher: Ton nur links, Pause, nur rechts, Pause, beide (16 Bit, 44,1 kHz). #>
    $rate = 44100; $amp = 9000
    $segments = @(@(1, 0, 0.8), @(0, 0, 0.3), @(0, 1, 0.8), @(0, 0, 0.3), @(1, 1, 0.8))
    $frames = 0; foreach ($s in $segments) { $frames += [int]($rate * $s[2]) }
    $ms = New-Object IO.MemoryStream
    $w = New-Object IO.BinaryWriter($ms)
    $data = $frames * 4
    $w.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $w.Write([int](36 + $data)); $w.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
    $w.Write([int]16); $w.Write([int16]1); $w.Write([int16]2); $w.Write([int]$rate); $w.Write([int]($rate * 4)); $w.Write([int16]4); $w.Write([int16]16)
    $w.Write([Text.Encoding]::ASCII.GetBytes('data')); $w.Write([int]$data)
    foreach ($s in $segments) {
        $n = [int]($rate * $s[2])
        for ($i = 0; $i -lt $n; $i++) {
            $v = [int16]([math]::Sin(2 * [math]::PI * 523.25 * $i / $rate) * $amp * [math]::Min(1, [math]::Min($i, $n - $i) / 800.0))
            $w.Write([int16]($v * $s[0])); $w.Write([int16]($v * $s[1]))
        }
    }
    $w.Flush(); $ms.Position = 0
    return , $ms
}

function Add-SpeakerTestToolFinding {
    param([string]$Category)
    Add-Finding $Category Info 'Lautsprecher-Test links/rechts' -Silent -Repeatable `
        -Detail 'Spielt einen Ton nur links, dann nur rechts, dann auf beiden Seiten über das Standard-Ausgabegerät. So fällt ein defekter oder vertauschter Lautsprecher sofort auf. Lautstärke vorher auf ein angenehmes Maß stellen.' `
        -FixLabel 'Testton abspielen (ca. 3 Sekunden)' -Fix {
        param($d)
        $ms = New-StereoToneWav
        try { $p = New-Object Media.SoundPlayer($ms); $p.PlaySync() } finally { $ms.Dispose() }
        'Testton abgespielt: links – rechts – beide. Fehlte eine Seite, Kabel/Stecker bzw. Balance in den Soundeinstellungen prüfen.'
    }
}
