# Laptop-Diagnose & Reparatur

Diagnose-Tool für Windows-10/11-Laptops. Es findet Fehler, Speicherfresser und Leistungsbremsen, prüft den Akku und hält Programme, Windows und Treiber aktuell. Gefundene Probleme werden **erst nach Rückfrage** behoben.

## Start

1. Den Ordner `LaptopDiagnose` auf den Laptop kopieren.
2. **`Start-LaptopDiagnose.cmd`** doppelklicken.
3. Die Abfrage nach Administratorrechten bestätigen. Diese Rechte braucht das Tool für Reparaturen, Updates und einige Prüfungen.

Alternativ in PowerShell:

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

## Berichte

Gespeichert wird in `Dokumente\LaptopDiagnose`:

- `Diagnosebericht_<Datum>.html`: Bericht mit Gesundheitswert, allen Ergebnissen und den durchgeführten Maßnahmen
- `Diagnosebericht_<Datum>.json`: dieselben Daten maschinenlesbar
- `Akkubericht_<Datum>.html`: ausführlicher Windows-Akkubericht
- `Protokoll_<Datum>.txt`: vollständiges Sitzungsprotokoll

## Voraussetzungen

- Windows 10 oder 11, Windows PowerShell 5.1 (vorinstalliert)
- Für Software-Updates: WinGet (App-Installer aus dem Microsoft Store, bei Windows 11 vorinstalliert). Wenn das Modul `Microsoft.WinGet.Client` installiert ist, nutzt das Tool es automatisch.

Copyright 2026 by Eder Tom
