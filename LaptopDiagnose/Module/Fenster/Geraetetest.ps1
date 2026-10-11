<#
    Gerätecheck – interaktive Tests in eigenen Fenstern (läuft als eigener Prozess im STA-Modus):
    Tastatur (jede Taste leuchtet auf), Bildschirm (Pixelfehler-Test), Lautsprecher (links/rechts), Kamera, Mikrofon.
    Das Ergebnis wird als JSON-Datei geschrieben und von PC Repair Pro in den Bericht »Zustand des Geräts« übernommen.
    Teil von PC Repair Pro – Copyright 2026 by Eder Tom
#>
param([Parameter(Mandatory)][string]$Ergebnis)

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Audio.ps1')

$results = [ordered]@{}
function Ask {
    param([string]$Text, [string]$Title = 'Gerätecheck', [string]$Buttons = 'YesNoCancel')
    "$([System.Windows.MessageBox]::Show($Text, $Title, $Buttons, 'Question'))"
}
function Save-Results { ($results | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $Ergebnis -Encoding UTF8 }

$start = Ask "Der Gerätecheck testet nacheinander Tastatur, Bildschirm, Lautsprecher, Kamera und Mikrofon.`n`nJeder Test lässt sich mit »Abbrechen« überspringen. Am Ende entsteht ein Bericht »Zustand des Geräts«.`n`nStarten?" 'Gerätecheck' 'OKCancel'
if ($start -ne 'OK') { $results.Abgebrochen = $true; Save-Results; return }

#region Tastatur
$rows = @(
    @('Esc', 'F1', 'F2', 'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'F10', 'F11', 'F12', 'Entf')
    @('^', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', 'ß', '´', '⌫')
    @('Tab', 'Q', 'W', 'E', 'R', 'T', 'Z', 'U', 'I', 'O', 'P', 'Ü', '+', '↵')
    @('⇪', 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'Ö', 'Ä', '#')
    @('⇧ links', '<', 'Y', 'X', 'C', 'V', 'B', 'N', 'M', ',', '.', '-', '⇧ rechts')
    @('Strg links', 'Win', 'Alt', 'Leertaste', 'AltGr', 'Strg rechts', '←', '↑', '↓', '→')
)
$keyMap = @{
    'Esc' = 'Escape'; 'Entf' = 'Delete'; '^' = 'Oem5'; 'ß' = 'Oem4'; '´' = 'Oem6'; '⌫' = 'Back'; 'Tab' = 'Tab'; 'Ü' = 'Oem1'; '+' = 'OemPlus'; '↵' = 'Return'
    '⇪' = 'Capital'; 'Ö' = 'Oem3'; 'Ä' = 'Oem7'; '#' = 'Oem2'; '⇧ links' = 'LeftShift'; '<' = 'Oem102'; ',' = 'OemComma'; '.' = 'OemPeriod'; '-' = 'OemMinus'; '⇧ rechts' = 'RightShift'
    'Strg links' = 'LeftCtrl'; 'Win' = 'LWin'; 'Alt' = 'LeftAlt'; 'Leertaste' = 'Space'; 'AltGr' = 'RightAlt'; 'Strg rechts' = 'RightCtrl'; '←' = 'Left'; '↑' = 'Up'; '↓' = 'Down'; '→' = 'Right'
}
foreach ($c in '1234567890'.ToCharArray()) { $keyMap["$c"] = "D$c" }
foreach ($c in 'QWERTZUIOPASDFGHJKLYXCVBNM'.ToCharArray()) { $keyMap["$c"] = "$c" }
for ($i = 1; $i -le 12; $i++) { $keyMap["F$i"] = "F$i" }

$win = New-Object System.Windows.Window
$win.Title = 'Gerätecheck – Tastatur'; $win.Width = 1000; $win.Height = 470; $win.WindowStartupLocation = 'CenterScreen'; $win.Background = '#F5F7FA'
$stack = New-Object System.Windows.Controls.StackPanel; $stack.Margin = '18'
$hint = New-Object System.Windows.Controls.TextBlock
$hint.Text = 'Bitte jede Taste einmal drücken – gedrückte Tasten werden grün. Danach »Fertig« klicken.'; $hint.FontSize = 15; $hint.Margin = '0,0,0,12'; $hint.TextWrapping = 'Wrap'
$null = $stack.Children.Add($hint)
$cells = @{}
foreach ($r in $rows) {
    $line = New-Object System.Windows.Controls.WrapPanel
    foreach ($label in $r) {
        $b = New-Object System.Windows.Controls.Border
        $b.Margin = '3'; $b.Padding = '6,6'; $b.CornerRadius = '5'; $b.Background = '#FFFFFF'; $b.BorderBrush = '#98A2B3'; $b.BorderThickness = '1'
        $b.MinWidth = if ($label -eq 'Leertaste') { 260 } elseif ($label.Length -gt 3) { 78 } else { 44 }
        $t = New-Object System.Windows.Controls.TextBlock; $t.Text = $label; $t.HorizontalAlignment = 'Center'; $t.FontSize = 14
        $b.Child = $t
        $null = $line.Children.Add($b)
        $cells[$keyMap[$label]] = @{ Border = $b; Label = $label; Done = $false }
    }
    $null = $stack.Children.Add($line)
}
$status = New-Object System.Windows.Controls.TextBlock; $status.Margin = '0,10,0,6'; $status.FontSize = 14
$null = $stack.Children.Add($status)
$ok = New-Object System.Windows.Controls.Button; $ok.Content = 'Fertig'; $ok.Padding = '18,6'; $ok.HorizontalAlignment = 'Right'; $ok.Focusable = $false
$null = $stack.Children.Add($ok)
$win.Content = $stack
$update = { $n = @($cells.Values | Where-Object { $_.Done }).Count; $status.Text = "$n von $($cells.Count) Tasten erkannt" }
& $update
$win.Add_PreviewKeyDown({
        param($s, $e)
        $k = if ("$($e.Key)" -eq 'System') { "$($e.SystemKey)" } else { "$($e.Key)" }
        if ($k -eq 'ImeProcessed') { $k = "$($e.ImeProcessedKey)" }
        if ($cells.ContainsKey($k) -and -not $cells[$k].Done) { $cells[$k].Done = $true; $cells[$k].Border.Background = '#ABEFC6'; $cells[$k].Border.BorderBrush = '#079455'; & $update }
        $e.Handled = $true
    })
$ok.Add_Click({ $win.Close() })
$null = $win.ShowDialog()
$missing = @($cells.Values | Where-Object { -not $_.Done } | ForEach-Object { $_.Label })
$results.Tastatur = [ordered]@{ Erkannt = $cells.Count - $missing.Count; Gesamt = $cells.Count; Fehlend = $missing }
Save-Results
#endregion

#region Bildschirm
if ((Ask "Pixelfehler-Test: Der Bildschirm wird nacheinander komplett schwarz, weiß, rot, grün, blau und grau.`nKlick oder Leertaste = nächste Farbe, Esc = Ende.`n`nAuf dauerhaft andersfarbige Punkte, Streifen oder helle Flecken achten.`n`nTest starten?") -eq 'Yes') {
    $colors = @('#000000', '#FFFFFF', '#FF0000', '#00FF00', '#0000FF', '#808080')
    $idx = 0
    $full = New-Object System.Windows.Window
    $full.WindowStyle = 'None'; $full.ResizeMode = 'NoResize'; $full.WindowState = 'Maximized'; $full.Topmost = $true; $full.Background = $colors[0]; $full.Cursor = 'None'
    $next = { $script:idx++; if ($script:idx -ge $colors.Count) { $full.Close() } else { $full.Background = $colors[$script:idx] } }
    $full.Add_MouseDown({ & $next })
    $full.Add_KeyDown({ param($s, $e) if ("$($e.Key)" -eq 'Escape') { $full.Close() } else { & $next } })
    $null = $full.ShowDialog()
    $a = Ask 'Waren dauerhaft andersfarbige Punkte (Pixelfehler), Streifen oder ungleichmäßig helle Flecken zu sehen?'
    $results.Bildschirm = switch ($a) { 'No' { 'in Ordnung' } 'Yes' { 'Fehler gesehen' } default { 'nicht beurteilt' } }
} else { $results.Bildschirm = 'übersprungen' }
Save-Results
#endregion

#region Lautsprecher
if ((Ask "Lautsprecher-Test: Es ertönt ein Ton nur links, dann nur rechts, dann auf beiden Seiten. Lautstärke vorher angenehm einstellen.`n`nTest starten?") -eq 'Yes') {
    $ms = New-StereoToneWav
    try { (New-Object System.Media.SoundPlayer($ms)).PlaySync() } catch { } finally { $ms.Dispose() }
    $a = Ask 'War der Ton zuerst nur links, dann nur rechts und zuletzt auf beiden Seiten klar zu hören (ohne Knacken oder Scheppern)?'
    $results.Lautsprecher = switch ($a) { 'Yes' { 'in Ordnung' } 'No' { 'Fehler gehört' } default { 'nicht beurteilt' } }
} else { $results.Lautsprecher = 'übersprungen' }
Save-Results
#endregion

#region Kamera und Mikrofon
if ((Ask "Kamera-Test: Die Windows-Kamera-App wird geöffnet.`n`nTest starten?") -eq 'Yes') {
    try { Start-Process 'microsoft.windows.camera:' } catch { }
    $a = Ask 'Zeigt die Kamera-App ein klares Bild? (Danach die Kamera-App schließen.)'
    $results.Kamera = switch ($a) { 'Yes' { 'in Ordnung' } 'No' { 'kein oder schlechtes Bild' } default { 'nicht beurteilt' } }
} else { $results.Kamera = 'übersprungen' }
Save-Results
if ((Ask "Mikrofon-Test: Die Soundeinstellungen werden geöffnet. Unter »Eingabe« beim Sprechen auf den Pegel achten (»Mikrofon testen«).`n`nTest starten?") -eq 'Yes') {
    try { Start-Process 'ms-settings:sound' } catch { }
    $a = Ask 'Bewegt sich der Eingabepegel, wenn Sie sprechen?'
    $results.Mikrofon = switch ($a) { 'Yes' { 'in Ordnung' } 'No' { 'kein Pegel' } default { 'nicht beurteilt' } }
} else { $results.Mikrofon = 'übersprungen' }
$results.Fertig = $true
Save-Results
#endregion
