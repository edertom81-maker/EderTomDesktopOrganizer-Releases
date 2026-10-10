# Laptop-Diagnose & Reparatur

Diagnose- und Wartungsprogramm für Windows-10/11-Laptops. Es findet Fehler, Sicherheitslücken, Speicherfresser und Leistungsbremsen, prüft Akku und WLAN, hält Programme, Windows und Treiber aktuell und verfolgt die Entwicklung über die Zeit. Gefundene Probleme werden **erst nach Rückfrage** behoben, und jede Änderung wird protokolliert. Umkehrbare Änderungen lassen sich mit einem Klick zurücknehmen.

## Installation und Start

**Empfohlen:** `Install-LaptopDiagnose.cmd` doppelklicken. Das Programm wird für den aktuellen Benutzer installiert, ohne dass Administratorrechte nötig sind:

- Programmordner: `%LOCALAPPDATA%\Programs\LaptopDiagnose`
- Startmenü-Eintrag **»Laptop-Diagnose«** mit eigenem Symbol, auf Wunsch auch eine Desktop-Verknüpfung
- Eintrag unter *Einstellungen › Apps › Installierte Apps*, dort auch wieder deinstallierbar

**Ohne Installation:** `Start-LaptopDiagnose.cmd` im Ordner doppelklicken.

Beim Start fragt Windows nach Administratorrechten. Diese Rechte braucht das Programm für Reparaturen, Updates und einige Prüfungen.

## Programmfenster

| Bereich | Inhalt |
|---|---|
| **Übersicht** | Systemdaten, Gesundheitswert (0–100) und alle Ergebnisse nach Dringlichkeit |
| **Fehlersuche** | Bluescreens **mit Ursachenanalyse** (Stoppcode → wahrscheinliche Ursache und Empfehlung, optional Auswertung der Absturzabbilder mit dem Windows-Debugger), unerwartete Abschaltungen, Hardware- und Datenträgerfehler, Programmabstürze, Ereignisprotokoll, Problemgeräte, Dienste, Systemabbild, SMART, Dateisystem, Ergebnis des Arbeitsspeicher-Tests |
| **Sicherheit** | Virenschutz, Firewall, Secure Boot, TPM, BitLocker/Geräteverschlüsselung, Kernisolierung, Benutzerkontensteuerung, SMB1, freigegebene Ordner, Remotedesktop, pausierte Updates, veraltete Browser und Mailprogramme |
| **Speicherfresser** | RAM, größte Prozesse, freier Speicher, **Speicherbelegung als Balkendiagramm** (Laufwerk C: und Benutzerordner), Datenmüll, Windows.old, große Dateien |
| **Leistungsbremsen** | CPU-Last, Autostarts, Startdauer (inkl. »langsamer als üblich«), Energiesparplan, Drosselung, SSD/TRIM, Auslagerungsdatei, Temperatur, **vorinstallierte Zusatz-Apps und Testversionen** |
| **Akku** | Gesundheit, Ladezyklen, **Kapazitätsverlauf als Diagramm** mit Prognose, Ladezustand, Standby-Art, Akkuverbrauch nach Apps, ausführlicher Akkubericht |
| **Netzwerk & WLAN** | Internet/DNS, WLAN-Signal, Band, Kanal, Verschlüsselung, **Geschwindigkeitstest und Latenz**, Proxy, Alter des WLAN-Treibers, WLAN-Bericht |
| **Software-Updates** | Alle über WinGet verwalteten Programme, einzeln oder alle installieren |
| **Windows & Treiber** | Windows- und Treiber-Updates, veraltete Treiber, Hersteller-Tools für BIOS und Firmware |
| **Reparatur-Werkzeuge** | Windows Update reparieren, Systemdateien (SFC/DISM), Startmenü und Suche reparieren, Microsoft Store zurücksetzen, Druckerwarteschlange leeren, Audio- und Bluetooth-Dienste neu starten, Netzwerk zurücksetzen, **Arbeitsspeicher-Test**, **Belastungstest** (Lüfter, Temperatur, Drosselung), Energiebericht, Standby-Analyse, Komponentenspeicher bereinigen, Defender-Schnellscan, Wiederherstellungspunkt |
| **Verlauf & Trends** | Diagramme der wichtigsten Kennzahlen über alle Komplett-Diagnosen, z. B. Akku-Gesundheit, Startdauer, freier Speicher, Abstürze und Internetgeschwindigkeit. Grün bedeutet verbessert, Orange verschlechtert. |
| **Änderungen** | Jede Änderung mit Zeitpunkt und Ergebnis. Umkehrbare Änderungen haben eine Schaltfläche **»Rückgängig«** (deaktivierte Autostarts, Energieplan, Prozessorleistung, TRIM, Auslagerungsdatei, Remotedesktop, SMB1, geplante Wartung). |
| **Einstellungen** | Design **System / Hell / Dunkel**, geplante Wartung, PDF-Berichte, Geräteübersicht, Programm-Updates, Signaturstatus |
| **Protokoll** | Alle Ausgaben der Sitzung |

Unten markiert **»Empfohlene auswählen«** alle kritischen Punkte und Warnungen. **»Ausgewählte beheben«** zeigt vorher eine Zusammenfassung zur Bestätigung und fragt nach einem Wiederherstellungspunkt. Bei Autostarts, Updates und Zusatz-Apps wählst du die einzelnen Einträge in einer Liste aus. **»Nur prüfen«** in der Seitenleiste sperrt alle Änderungen.

## Geplante Wartung

Unter *Einstellungen › Geplante Wartung* richtest du eine wöchentliche oder tägliche Prüfung über die Windows-Aufgabenplanung ein (Aufgabe `\EderTom\LaptopDiagnose Wartung`). Sie arbeitet so:

- Sie **ändert nichts**, sondern prüft nur und speichert Bericht und Verlauf.
- Bei kritischen Problemen oder deutlich mehr Warnungen als beim letzten Mal erscheint eine **Windows-Benachrichtigung**. Ein Klick darauf öffnet den Bericht.
- Hat der Laptop zur geplanten Zeit nicht gelaufen, wird die Prüfung nachgeholt.

## Berichte

Gespeichert wird in `Dokumente\LaptopDiagnose`:

- `Diagnosebericht_<Datum>.html` und `.json`: Bericht mit Gesundheitswert, Trends, Diagrammen und Maßnahmen. Ein `.pdf` kommt hinzu, wenn PDF in den Einstellungen aktiviert ist (erzeugt über Microsoft Edge).
- `Verlauf\`: ein Messpunkt pro Komplett-Diagnose
- `Aenderungen.json`: das Änderungsprotokoll
- `Einstellungen.json`: Design und PDF-Option
- `Akkubericht_…`, `WLAN-Bericht_…`, `Energiebericht_…`, `Standby-Analyse_…`: ausführliche Windows-Berichte
- `Protokoll_…txt`: Sitzungsprotokolle
- **Geräteübersicht:** Lege die JSON-Berichte mehrerer Laptops in einen gemeinsamen Ordner (z. B. USB-Stick oder OneDrive) und klicke in den Einstellungen auf *Geräteübersicht erstellen*. Du bekommst eine Vergleichstabelle mit Gesundheitswert, kritischen Punkten, Akku, freiem Speicher und offenen Updates.

## Sicherheit

- Alle Prüfungen lesen nur. Geändert wird erst, wenn du Punkte auswählst und bestätigst.
- Vor Reparaturen bietet das Programm einen **Systemwiederherstellungspunkt** an.
- Jede Änderung landet im Änderungsprotokoll. Sicherheitsrelevante Verbesserungen werden bewusst nicht automatisch zurückgenommen, etwa eine eingeschaltete Firewall oder Benutzerkontensteuerung.
- Systemprozesse werden nie zum Beenden angeboten, und vor dem Beenden eines Programms warnt das Tool vor ungespeicherten Daten.
- Absturzabbilder werden erst nach 30 Tagen als Datenmüll angeboten, damit die Bluescreen-Analyse sie nutzen kann.
- Programm-Updates werden vor der Installation per **SHA-256-Prüfsumme** kontrolliert. Ist die installierte Version signiert, muss auch das Update vom selben Herausgeber signiert sein.

## Virenscanner meldet das Tool

Diagnose- und Reparaturskripte nutzen dieselben Windows-Funktionen wie manche Schadsoftware: Adminrechte anfordern, Autostarts ändern, Dateien löschen, Dienste steuern. Manche Virenscanner schlagen deshalb vorsorglich an. Das Tool verzichtet bewusst auf versteckte Fenster, auf zur Laufzeit übersetzten Code und auf Änderungen an den Defender-Einstellungen.

Wenn trotzdem eine Meldung erscheint:

1. Den Namen der Erkennung notieren und prüfen, welche Datei gemeldet wird.
2. Den Fehlalarm beim Hersteller melden: Bitdefender unter https://www.bitdefender.com/submit/, Microsoft unter https://www.microsoft.com/wdsi/filesubmission.
3. **Die Skripte signieren** (siehe unten). Signierte Skripte werden deutlich seltener gemeldet.
4. Nur wenn klar ist, dass es ein Fehlalarm ist: eine Ausnahme nur für den Programmordner einrichten. Den Virenschutz nicht abschalten.

## Für Entwickler: Signieren und Updates veröffentlichen

Die Werkzeuge liegen im Ordner `Entwicklung` und werden nicht mit ausgeliefert:

- **`Sign-LaptopDiagnose.ps1`** signiert alle Skripte mit dem Code-Signing-Zertifikat, also demselben, mit dem die Desktop-Organizer-Setups signiert werden. Das Zertifikat kommt aus dem Zertifikatspeicher (`-Thumbprint`) oder aus einer PFX-Datei (`-PfxPath`), dazu ein Zeitstempel.
- **`New-LaptopDiagnoseRelease.ps1 -Signieren`** erzeugt `dist\LaptopDiagnose-<Version>.zip` und die zugehörige `.sha256`-Datei.
- Auf GitHub ein Release mit dem Tag **`laptopdiagnose-v<Version>`** anlegen und beide Dateien anhängen. Installierte Programme finden das Update dann unter *Einstellungen › Programm-Updates*.

Die Version steht in `LaptopDiagnose.ps1` (`$Script:ToolVersion`).

## Konsolenversion

`Start-LaptopDiagnose-Konsole.cmd` startet die Textversion mit demselben Funktionsumfang. Aufruf mit Parametern:

```powershell
.\LaptopDiagnose.ps1                                  # Menü
.\LaptopDiagnose.ps1 -Modus Komplett                  # Komplett-Diagnose mit Reparaturangebot
.\LaptopDiagnose.ps1 -Modus Komplett -NurPruefen -Pdf # nur prüfen, Bericht auch als PDF
.\LaptopDiagnose.ps1 -Modus Sicherheit                # einzelner Bereich: Fehler, Sicherheit, Speicher, Leistung, Akku,
                                                      # Netzwerk, Software, Windows, Werkzeuge
.\LaptopDiagnose.ps1 -Modus Verlauf                   # Verlauf, Aenderungen, Wartung, Update
.\LaptopDiagnose.ps1 -Modus Komplett -Unbeaufsichtigt # wie die geplante Wartung
```

## Aufbau

| Datei | Inhalt |
|---|---|
| `LaptopDiagnose.ps1` | Kern: Fehlersuche, Speicher, Leistung, Akku, Software, Windows-Updates, Reparaturablauf, Bericht, Menü |
| `LaptopDiagnoseGUI.ps1` | Programmfenster (WPF) |
| `Module\Sicherheit.ps1` | Sicherheitsprüfungen |
| `Module\Netzwerk.ps1` | Netzwerk, WLAN, Geschwindigkeit |
| `Module\Analyse.ps1` | Bluescreen-Analyse, Speicherbelegung, Akkuverlauf, Speichertest |
| `Module\Werkzeuge.ps1` | Reparatur-Werkzeuge, Belastungstest, Zusatz-Apps |
| `Module\Verlauf.ps1` | Kennzahlen, Trends, Geräteübersicht |
| `Module\Aenderungen.ps1` | Änderungsprotokoll und Rückgängig |
| `Module\Wartung.ps1` | Geplante Wartung, Benachrichtigungen, Programm-Updates |

## Voraussetzungen

- Windows 10 oder 11 mit Windows PowerShell 5.1 (vorinstalliert)
- Für Software-Updates: WinGet (App-Installer, bei Windows 11 vorinstalliert)
- Für PDF-Berichte: Microsoft Edge (vorinstalliert)
- Optional für die Debugger-Auswertung von Bluescreens: *Debugging Tools for Windows* (Teil des Windows SDK)

Copyright 2026 by Eder Tom
