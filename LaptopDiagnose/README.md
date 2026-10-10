# Laptop-Diagnose & Reparatur

Diagnose-Tool für Windows-10/11-Laptops. Es findet Fehler, Speicherfresser und Leistungsbremsen, prüft den Akku und hält Programme, Windows und Treiber aktuell. Gefundene Probleme werden **erst nach Rückfrage** behoben.

## Start

1. Den Ordner `LaptopDiagnose` auf den Laptop kopieren.
2. **`Start-LaptopDiagnose.cmd`** doppelklicken. Das Programmfenster öffnet sich.
3. Die Abfrage nach Administratorrechten bestätigen. Diese Rechte braucht das Tool für Reparaturen, Updates und einige Prüfungen.

### Programmfenster

- **Links** stehen die Bereiche: Übersicht, Fehlersuche, Speicherfresser, Leistungsbremsen, Akku, Software-Updates, Windows & Treiber und Protokoll. Rote oder orange Zähler zeigen offene Probleme.
- **Oben** startet »Komplett-Diagnose starten« alle Prüfungen. Mit »… prüfen« prüfst du nur den gerade gewählten Bereich. Die Kacheln zeigen den Gesundheitswert (0–100) und die Anzahl der Ergebnisse.
- **Ergebniskarten** sind farbig nach Dringlichkeit markiert. »Details anzeigen« klappt Listen auf, z. B. die größten Programme oder verfügbare Updates. Behebbare Punkte haben ein Ankreuzfeld.
- **Unten** markiert »Empfohlene auswählen« alle kritischen Punkte und Warnungen. »Ausgewählte beheben« zeigt zuerst eine Zusammenfassung zur Bestätigung und fragt nach einem Wiederherstellungspunkt. Bei Autostarts und Updates wählst du vorher in einer Liste einzelne Einträge aus.
- **»Nur prüfen«** in der Seitenleiste sperrt alle Änderungen.
- **»Bericht speichern & öffnen«** erstellt den HTML-Bericht und öffnet ihn im Browser.

Während eine Prüfung läuft, bleibt das Fenster bedienbar. Was gerade passiert, steht unten in der Statuszeile und ausführlich unter »Protokoll«.

### Konsolenversion

`Start-LaptopDiagnose-Konsole.cmd` startet die Textversion mit Menü. Sie kann dasselbe und lässt sich auch mit Parametern aufrufen:

```powershell
.\LaptopDiagnose.ps1                        # Menü
.\LaptopDiagnose.ps1 -Modus Komplett        # Komplett-Diagnose mit Reparaturangebot
.\LaptopDiagnose.ps1 -Modus Komplett -NurPruefen   # nur prüfen, nichts verändern
.\LaptopDiagnose.ps1 -Modus Akku            # einzelnes Modul (Fehler, Speicher, Leistung, Akku, Software, Windows)
```

## Was geprüft wird

| Bereich | Prüfungen | Automatische Behebung (nach Rückfrage) |
|---|---|---|
| **Fehlersuche** | Bluescreens, unerwartete Abschaltungen, WHEA-Hardwarefehler, Datenträgerfehler, Programmabstürze, Ereignisprotokoll (7 Tage), Problemgeräte im Geräte-Manager, gestoppte Dienste, Integrität des Windows-Abbilds, SMART/SSD-Verschleiß, Dateisystem, ausstehender Neustart, Virenschutz, Firewall, Internet/DNS, Supportstatus der Windows-Version | Dienste starten, Hardware neu erkennen, DISM + SFC, Dateisystemreparatur, Defender aktivieren/aktualisieren/Schnellscan, Firewall einschalten, Netzwerk zurücksetzen |
| **Speicherfresser** | RAM-Auslastung, größte Prozesse, freier Speicherplatz, Datenmüll (Temp, Update-Cache, Absturzabbilder, Fehlerberichte, Miniaturansichten, Papierkorb), Windows.old, große Dateien, Downloads-Ordner | Datenmüll entfernen, Windows.old/Update-Reste bereinigen, Komponentenspeicher bereinigen, speicherhungrige Programme beenden |
| **Leistungsbremsen** | CPU-Last und Verursacher, Autostart-Programme, Startdauer und bremsende Programme, Energiesparplan, gedrosselte Prozessorleistung, Laufzeit ohne Neustart, HDD/SSD und TRIM, Auslagerungsdatei, Temperatur | Autostarts gezielt deaktivieren (wie im Task-Manager, umkehrbar), Energiesparplan „Ausbalanciert“, Prozessor auf 100 %, TRIM aktivieren, defragmentieren, Auslagerungsdatei aktivieren |
| **Akku** | Gesundheit (aktuelle vs. ursprüngliche Kapazität), Ladezyklen, Ladezustand, Restlaufzeit, Programme, die Energiesparen verhindern, ausführlicher Windows-Akkubericht | – |
| **Software-Updates** | Alle über WinGet verwalteten Programme | Updates einzeln oder alle installieren |
| **Windows & Treiber** | Windows-Updates (inkl. Sicherheitsstufe), Treiber-Updates über Windows Update, über 4 Jahre alte Treiber wichtiger Geräte, Hersteller-Tool für BIOS/Firmware (z. B. Dell Command \| Update, Lenovo System Update) | Updates einzeln oder alle installieren, Dell-Updates per `dcu-cli` installieren, Hersteller-Tool per WinGet installieren |

## Sicherheit

- Alle Prüfungen lesen nur. Geändert wird erst, wenn du Punkte auswählst. Mit **A** werden nur die empfohlenen Punkte (Kritisch und Warnung) behoben, optionale Hinweise nur, wenn du ihre Nummer angibst.
- Vor Reparaturen bietet das Tool an, einen **Systemwiederherstellungspunkt** zu erstellen.
- Bevor ein Programm beendet wird, warnt das Tool vor ungespeicherten Daten. Systemprozesse werden nie zum Beenden angeboten.
- Mit `-NurPruefen` wird nichts verändert.

## Virenscanner meldet das Tool

Diagnose- und Reparaturskripte nutzen dieselben Windows-Funktionen wie manche Schadsoftware: Adminrechte anfordern, Autostarts ändern, Dateien löschen, Dienste steuern. Manche Virenscanner schlagen deshalb vorsorglich an. Das Tool verzichtet bewusst auf versteckte Fenster, auf zur Laufzeit übersetzten Code und auf Änderungen an den Defender-Einstellungen.

Wenn trotzdem eine Meldung erscheint:

1. Den Namen der Erkennung notieren (z. B. `Trojan:PowerShell/…`) und prüfen, welche Datei gemeldet wird.
2. Die Datei als Fehlalarm beim Hersteller einreichen. Für Microsoft Defender geht das unter https://www.microsoft.com/wdsi/filesubmission.
3. Die Skripte mit dem eigenen Code-Signing-Zertifikat signieren, mit dem auch die Desktop-Organizer-Setups signiert werden: `Set-AuthenticodeSignature -FilePath .\LaptopDiagnose.ps1 -Certificate $cert -TimestampServer http://timestamp.digicert.com`, ebenso für `LaptopDiagnoseGUI.ps1`. Signierte Skripte werden deutlich seltener gemeldet.
4. Nur wenn klar ist, dass es ein Fehlalarm ist: eine Ausnahme nur für den Ordner `LaptopDiagnose` einrichten. Den Virenschutz nicht abschalten.

## Berichte

Gespeichert wird in `Dokumente\LaptopDiagnose`:

- `Diagnosebericht_<Datum>.html`: Bericht mit Gesundheitswert, allen Ergebnissen und den durchgeführten Maßnahmen
- `Diagnosebericht_<Datum>.json`: dieselben Daten maschinenlesbar
- `Akkubericht_<Datum>.html`: ausführlicher Windows-Akkubericht
- `Protokoll_<Datum>.txt` bzw. `Protokoll_GUI_<Datum>.txt`: vollständiges Sitzungsprotokoll

## Voraussetzungen

- Windows 10 oder 11, Windows PowerShell 5.1 (vorinstalliert)
- Für Software-Updates: WinGet (App-Installer aus dem Microsoft Store, bei Windows 11 vorinstalliert). Wenn das Modul `Microsoft.WinGet.Client` installiert ist, nutzt das Tool es automatisch.

Copyright 2026 by Eder Tom
