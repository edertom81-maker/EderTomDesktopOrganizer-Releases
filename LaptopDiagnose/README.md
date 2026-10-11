# PC Repair Pro

*Diagnose • Repair • Keep it running* – bis Version 2.4 hieß das Programm »Laptop-Diagnose & Reparatur«.

Diagnose- und Wartungsprogramm für Windows-10/11-Laptops und -Desktop-PCs. Das Programm erkennt den Gerätetyp selbst: Auf Desktop-PCs ist der Bereich *Akku* ausgeblendet, dafür kommen PC-typische Prüfungen hinzu. Es findet Fehler, Sicherheitslücken, Speicherfresser und Leistungsbremsen, prüft Akku und WLAN, hält Programme, Windows und Treiber aktuell und verfolgt die Entwicklung über die Zeit. Gefundene Probleme werden **erst nach Rückfrage** behoben, und jede Änderung wird protokolliert. Umkehrbare Änderungen lassen sich mit einem Klick zurücknehmen.

## Installation und Start

**Empfohlen:** `Install-LaptopDiagnose.cmd` doppelklicken. Das Programm wird für den aktuellen Benutzer installiert, ohne dass Administratorrechte nötig sind:

- Programmordner: `%LOCALAPPDATA%\Programs\LaptopDiagnose`
- Startmenü-Eintrag **»PC Repair Pro«** mit eigenem Symbol, auf Wunsch auch eine Desktop-Verknüpfung (nach einem Programm-Update passt das Programm Name, Symbol und Version dieser Einträge selbst an)
- Eintrag unter *Einstellungen › Apps › Installierte Apps*, dort auch wieder deinstallierbar

**Ohne Installation:** `Start-LaptopDiagnose.cmd` im Ordner doppelklicken.

Beim Start fragt Windows nach Administratorrechten. Diese Rechte braucht das Programm für Reparaturen, Updates und einige Prüfungen.

## Programmfenster

| Bereich | Inhalt |
|---|---|
| **Übersicht** | Systemdaten, Gesundheitswert (0–100) und alle Ergebnisse nach Dringlichkeit |
| **Fehlersuche** | Bluescreens **mit Ursachenanalyse** (Stoppcode → wahrscheinliche Ursache und Empfehlung, optional Auswertung der Absturzabbilder mit dem Windows-Debugger), unerwartete Abschaltungen, Hardware- und Datenträgerfehler, Programmabstürze, Ereignisprotokoll, Problemgeräte, Dienste, Systemabbild, SMART, Dateisystem, Ergebnis des Arbeitsspeicher-Tests, **defekte Verknüpfungen** (Desktop, Startmenü, Taskleiste, Autostart – bereinigen in den Papierkorb bzw. umkehrbar deaktivieren), **Drucker** (Druckwarteschlange, offline, hängende Aufträge, automatisch wechselnder Standarddrucker, allgemeine Treiber), **Audio** (Standard-Ausgabe, Ton über HDMI, deaktivierte Geräte, Audiodienste, Treiberfehler) und **Bluetooth** (Adapter deaktiviert, Dienst, Geräte mit Fehler) |
| **Sicherheit** | **Erweiterte Sicherheit** (Ransomware-Schutz und PUA-Schutz bei Microsoft Defender – Änderung über »Windows-Sicherheit«, SmartScreen, aktiviertes Gastkonto – deaktivierbar, umkehrbar –, lokale Konten ohne Kennwort, automatische Anmeldung mit Klartext-Kennwort – ausschaltbar –, installierte und automatisch startende **Fernwartungsprogramme** wie AnyDesk oder TeamViewer), **Datensicherung** (OneDrive-Ordnersicherung, Dateiversionsverlauf, Systemabbild, Sicherungsprogramme – Warnung, wenn nichts oder nur Veraltetes gesichert ist), **Datenschutz-Einstellungen** (Werbe-ID, Diagnosedaten, Vorschläge, automatische App-Installation, Websuche, Eingabedaten – nach Auswahl datensparsam setzen, umkehrbar; dazu letzte Nutzung von Kamera und Mikrofon), **Browser-Erweiterungen** (Hinweis auf Erweiterungen außerhalb des Stores mit weitreichenden Rechten und typische Werbe-Erweiterungen), **Browser-Entführer** (erzwungene Browser-Richtlinien, ungewöhnliche Startseiten, Firefox user.js, Proxy-Skript, fremde DNS-Server, Hosts-Datei, Browser-Verknüpfungen mit angehängter Webadresse – Beheben nach Auswahl, umkehrbar), Virenschutz, Firewall, Secure Boot, TPM, BitLocker/Geräteverschlüsselung, Kernisolierung, Benutzerkontensteuerung, SMB1, freigegebene Ordner, Remotedesktop, pausierte Updates, veraltete Browser und Mailprogramme |
| **Speicherfresser** | RAM, größte Prozesse, freier Speicher, **Speicherbelegung als Kachelgrafik** (Laufwerk C: und Benutzerordner, je größer die Kachel, desto mehr Platz), Datenmüll (der **Papierkorb** wird direkt im Dateisystem geleert – deutlich schneller als über Windows – und schließt verwaiste Papierkörbe gelöschter Benutzerkonten ein; dazu **Browser-Caches** – nur bei geschlossenem Browser, Cookies/Passwörter/Verlauf bleiben – und alter Windows-Protokolle), Windows.old, **Wiederherstellungspunkte** (ältere löschen, neuester bleibt; Obergrenze setzen), **alte Systemabbilder**, Dateiversionsverlauf, **Reste von Windows-Upgrades**, **alte Treiberpakete** (bei »Prüfen« im Bereich), große Dateien, Werkzeug **»Programme deinstallieren«** (offizieller Deinstaller, danach Suche nach Resten), Werkzeuge **»Doppelte Dateien suchen«** (gleicher Inhalt, gruppiert, Vorschlag: älteste behalten), **»Leere Ordner suchen«** , **»Große Ordner anzeigen und löschen«** und **»Entwickler-Reste finden«** (neu erzeugbare Ordner in Programmier-Projekten wie node_modules, Python-Umgebungen, Caches und Build-Ausgaben sowie globale Paket-Caches – eigener Code und .git bleiben unberührt) (bis zwei Ebenen tief, ganze Ordner auswählbar; Klick auf eine Kachel zeigt die Unterordner; Löschen in den Papierkorb, was nicht hineinpasst nur nach ausdrücklicher Bestätigung), **Downloads aufräumen** (alte Installationsdateien und Archive, doppelte Dateien, große alte Dateien – nur Angekreuztes, und zwar in den Papierkorb) |
| **Leistungsbremsen** | CPU-Last, Autostarts inkl. **geplanter Aufgaben** und **Dienste von Fremdherstellern** (deaktivieren bzw. auf »Manuell« stellen, umkehrbar), Startdauer (inkl. »langsamer als üblich«), Energiesparplan, Drosselung, **Bildwiederholrate** (z. B. 144-Hz-Monitor läuft nur mit 60 Hz), **Arbeitsspeicher** (Takt unter Nenntakt bzw. XMP/EXPO aus, Single-Channel mit nur einem Modul), Bildschirm- und Standby-Zeiten (Desktop-PC), SSD/TRIM, Auslagerungsdatei, Temperatur, **Spiele- und Grafikleistung** (Spielmodus, Hintergrundaufzeichnung der Game Bar, hardwarebeschleunigte GPU-Planung bei eigener Grafikkarte – nach Auswahl setzen, umkehrbar –, Energiemodus am Netzteil, visuelle Effekte bei wenig Arbeitsspeicher), **vorinstallierte Zusatz-Apps und Testversionen** |
| **Herunterfahren** | **Gemessene Dauer** der letzten Herunterfahrvorgänge mit Diagramm und Verlauf, **bremsende Programme, Dienste und Treiber** laut Windows-Leistungsdiagnose, **ungewolltes Aufwachen** aus dem Energiesparmodus (Weckquellen der letzten 7 Tage, Geräte mit Weckberechtigung – Mäuse und Netzwerkadapter vorausgewählt, entziehbar, umkehrbar –, Reaktivierungszeitgeber im Akkubetrieb), hängende Dienste, zu lange Wartezeiten (auf Standard zurücksetzbar), Löschen der Auslagerungsdatei beim Herunterfahren (abschaltbar), ausstehende Updates, nicht erreichbare Netzlaufwerke (entfernbar), Herunterfahr-Skripte, Schnellstart, optional automatisches Beenden hängender Programme |
| **Akku** | Gesundheit, Ladezyklen, **Kapazitätsverlauf als Diagramm** mit Prognose, **Ladegrenze** (erkennt, ob der Akku am Netzteil nur bis ca. 80 % geladen wird, und öffnet sonst MyASUS bzw. die Hersteller-App), Ladezustand, Standby-Art, Akkuverbrauch nach Apps, ausführlicher Akkubericht |
| **Netzwerk & WLAN** | Internet/DNS, **Netzwerkkabel** (nur 100 Mbit/s statt 1 Gbit/s, Verbindungsabbrüche), WLAN-Signal, Band, Kanal, Verschlüsselung, **Geschwindigkeitstest und Latenz**, Proxy, Alter des WLAN-Treibers, WLAN-Bericht, **»Wer ist in meinem WLAN?«** (alle Geräte im Heimnetz mit Adresse und Namen, private MAC-Adressen erkannt, neue Geräte seit der letzten Prüfung hervorgehoben) |
| **Software-Updates** | Alle über WinGet verwalteten Programme, einzeln oder alle installieren. Bei Browsern, die sich selbst aktualisieren (Edge, Chrome, Firefox, Brave), wird die tatsächlich installierte Version gegengeprüft – so gibt es keine falschen »veraltet«-Meldungen. |
| **Windows & Treiber** | Windows- und Treiber-Updates, veraltete Treiber, **Grafiktreiber** (Alter, fehlender Treiber; Link zu NVIDIA App, AMD Adrenalin bzw. Intel-Assistent), **BIOS-Alter** mit Link zur Support-Seite des Geräte- bzw. Mainboard-Herstellers, Hersteller-Tools für BIOS und Firmware. Vor der Installation von Treiber-Updates werden alle Treiber automatisch **gesichert** (einmal am Tag) |
| **Externe Datenträger** | Lädt beim Öffnen automatisch und lädt sich neu, sobald ein Datenträger angesteckt oder abgezogen wird. USB-Sticks, externe Festplatten/SSDs und SD-Karten (interne Laufwerke und das Systemlaufwerk werden nie angeboten – jede Änderung prüft das unmittelbar vorher erneut). **Prüfen:** Übersicht mit Dateisystem, Größe, freiem Platz und BitLocker To Go, Zustand (SMART, soweit das USB-Gehäuse es durchreicht, Lese-/Schreibfehler und unerwartetes Abziehen aus dem Ereignisprotokoll), Dateisystem (bei »Datenträger prüfen« vollständig, in der Komplett-Diagnose schnell), Schreibschutz, fehlender Laufwerksbuchstabe, offline, »RAW« (dann Hinweis auf Datenrettung statt Formatieren), FAT32-Grenze von 4 GB, ungenutzter Platz. **Reparieren:** Dateisystemfehler beheben, Laufwerksbuchstaben zuweisen, online schalten, Schreibschutz aufheben (die Windows-Einstellung umkehrbar). **Ausführlicher Geschwindigkeitstest** (sequenziell und 4K, lesen und schreiben, je 3 Durchgänge, Diagramm und Einordnung wie »läuft mit USB-2.0-Geschwindigkeit«). **Echtheitstest** gegen gefälschte Kapazität (wie H2testw: freien Platz beschreiben und prüfen; vorhandene Dateien bleiben unberührt; mit Restzeit und »Abbrechen«). **Formatieren** mit exFAT, FAT32 oder NTFS samt Empfehlung, schnell oder vollständig, auf Wunsch »komplett neu einrichten« – erst nach Anzeige des Inhalts und Eintippen des Laufwerksbuchstabens. **Sicher entfernen.** **Partitionswerkzeuge** (auch für interne Zusatzlaufwerke wie eine zweite Festplatte – der Windows-Datenträger und Laufwerke mit Auslagerungsdatei sind immer gesperrt): Partitionsleiste je Datenträger, Partition erstellen, Datenträger aufteilen (z. B. 32 GB FAT32 fürs Autoradio + Rest exFAT), Partition löschen, Größe ändern (NTFS, ohne Datenverlust), Laufwerksbuchstaben ändern und Laufwerk umbenennen (beides umkehrbar), FAT32 ohne Datenverlust in NTFS umwandeln. **Klonen:** Laufwerk auf Dateiebene kopieren (Robocopy, mit Vergleich), Assistent »Windows auf neue SSD umziehen« (Hersteller-Programm von Samsung, WD, Crucial, Kingston oder Seagate bzw. Systemabbild mit Anleitung), 1:1-Klon Sektor für Sektor (bootfähig, Lesefehler werden übersprungen) sowie Abbilddatei (.img) erstellen und zurückschreiben, z. B. für Raspberry-Pi-Karten. Für den 1:1-Klon wird ein kleiner Hilfscode für den direkten Datenträgerzugriff erst beim Start geladen – Virenscanner können darauf reagieren. **Gelöschte Dateien retten** (Oberfläche für das kostenlose Microsoft-Tool »Windows File Recovery«: Fotos, Dokumente, Videos, Musik oder eigenes Suchmuster; gespeichert wird immer auf einem anderen Laufwerk). **Datenträger sicher löschen** vor Verkauf oder Weitergabe (freien Platz überschreiben, Laufwerk vollständig formatieren oder ganzen Datenträger mit Nullen überschreiben; Nachweis im Bericht; Hinweis auf »Secure Erase« bei SSDs). |
| **Reparatur-Werkzeuge** | Windows Update reparieren, Systemdateien (SFC/DISM), Startmenü und Suche reparieren, Microsoft Store zurücksetzen, Druckerwarteschlange leeren, Audio- und Bluetooth-Dienste neu starten, Netzwerk zurücksetzen, **Arbeitsspeicher-Test**, **Belastungstest** (Lüfter, Temperatur, Drosselung), Energiebericht, Standby-Analyse, Komponentenspeicher bereinigen, Defender-Schnellscan, **Lautsprecher-Test links/rechts**, Wiederherstellungspunkt, **»Was bremst gerade?«** (60 Sekunden Lastaufzeichnung mit Auswertung, auch in der Konsole), **Treiber sichern** (alle Fremdtreiber in den Berichtordner, die neuesten 2 Sicherungen bleiben; mit Anleitung zum Zurücksetzen) |
| **Live-Monitor** | Laufende Anzeige von **Prozessor, Arbeitsspeicher, Datenträger (gesamt und **jeder Datenträger einzeln**, auch externe, mit Lesen/Schreiben und Verlauf), Netzwerk und Temperatur** mit Verlaufskurve der letzten Minute und den **größten Verbrauchern**. Die Aufzeichnung **»Was bremst gerade?«** misst 60 Sekunden lang und nennt die wahrscheinliche Ursache (z. B. »Prozessor dauerhaft ausgelastet – vor allem durch …«). Liest nur, ändert nichts. |
| **Verlauf & Trends** | Diagramme der wichtigsten Kennzahlen über alle Komplett-Diagnosen, z. B. Akku-Gesundheit, Start- und Herunterfahrdauer, freier Speicher, Abstürze und Internetgeschwindigkeit. Grün bedeutet verbessert, Orange verschlechtert. |
| **Änderungen** | Jede Änderung mit Zeitpunkt und Ergebnis. Umkehrbare Änderungen haben eine Schaltfläche **»Rückgängig«** (deaktivierte Autostarts, Energieplan, Prozessorleistung, TRIM, Auslagerungsdatei, Remotedesktop, SMB1, Wartezeiten beim Herunterfahren, entfernte Netzlaufwerke, geplante Wartung, Gastkonto, automatische Anmeldung, Weckberechtigungen, Reaktivierungszeitgeber). |
| **Einstellungen** | Design **System / Hell / Dunkel**, Umfang der Komplett-Diagnose (**jeder Prüfbereich einzeln an- und abwählbar**, dazu die Option **»Speicherbelegung aufnehmen«**; abgewählte Bereiche vermerkt der Bericht), geplante Wartung, **Berichtordner** (»Ändern …«), Aufbewahrung alter Berichte (10 / 30 / 100 / alle), PDF-Berichte, Geräteübersicht, Programm-Updates (Option **»Beim Start automatisch nach Updates suchen«**, standardmäßig an), **ausgeblendete Meldungen** (einzeln oder alle wieder einblenden), Signaturstatus |
| **Protokoll** | Alle Ausgaben der Sitzung |

Unten markiert **»Empfohlene auswählen«** alle kritischen Punkte und Warnungen. **»Ausgewählte beheben«** zeigt vorher eine Zusammenfassung zur Bestätigung und fragt nach einem Wiederherstellungspunkt. Bei Autostarts, Updates, Zusatz-Apps und Downloads wählst du die einzelnen Einträge in einer Liste aus. Danach zeigt ein **Vorher/Nachher-Vergleich**, was sich verbessert hat (Gesundheitswert, offene Probleme, freier Speicher, Autostarts, Arbeitsspeicher). Start- und Herunterfahrdauer lassen sich erst nach einem Neustart vergleichen und erscheinen unter *Verlauf*. **»Nur prüfen«** in der Seitenleiste sperrt alle Änderungen.

**Suchen und Filtern:** Über den Ergebnissen sucht ein Suchfeld in Titel, Details, Einträgen und Prüfungsnamen. Dazu lässt sich nach Schweregrad und »Nur behebbare« filtern. **»Als CSV exportieren«** speichert die angezeigten Ergebnisse als Tabelle für Excel im Berichtordner.

**»?« an jeder Ergebniskarte:** Der Mauszeiger auf dem »?« erklärt kurz, warum die Prüfung wichtig ist.

**Meldungen ausblenden:** Jede Warnung und jeder Hinweis hat den Knopf **»Ausblenden«**. Wahlweise wird nur diese Meldung ausgeblendet (sie bleibt es auch, wenn sich Zahlen darin ändern, etwa der Akkustand) oder die ganze Prüfung. Ausgeblendete Meldungen erscheinen bei späteren Prüfungen – auch in der Konsole und der geplanten Wartung – nicht mehr, zählen nicht im Gesundheitswert, und der Bericht nennt ihre Anzahl. Unter *Einstellungen › Ausgeblendete Meldungen* lassen sie sich wieder einblenden.

Das Programmfenster öffnet sich maximiert. In den aufklappbaren Details öffnet ein **Doppelklick auf eine Zeile mit Pfad** den Ordner im Explorer.

## Geplante Wartung

Unter *Einstellungen › Geplante Wartung* richtest du eine wöchentliche oder tägliche Prüfung über die Windows-Aufgabenplanung ein (Aufgabe `\EderTom\LaptopDiagnose Wartung`). Sie arbeitet so:

- Sie **ändert nichts**, sondern prüft nur und speichert Bericht und Verlauf.
- Bei kritischen Problemen oder deutlich mehr Warnungen als beim letzten Mal erscheint eine **Windows-Benachrichtigung**. Ein Klick darauf öffnet den Bericht.
- Hat der Laptop zur geplanten Zeit nicht gelaufen, wird die Prüfung nachgeholt.

## Berichte

Gespeichert wird standardmäßig im **lokalen** Ordner `C:\Users\<Name>\Documents\LaptopDiagnose`. Das gilt auch dann, wenn Windows den Dokumente-Ordner nach OneDrive umgeleitet hat: Ein von OneDrive synchronisierter Ordner macht das Speichern spürbar langsamer. Beim ersten Start ab Version 2.4 werden vorhandene Berichte, Verlauf, Änderungsprotokoll und Einstellungen einmalig aus dem bisherigen Ordner übernommen. Unter *Einstellungen › Berichte › Ändern …* lässt sich jeder andere Ordner wählen, auf Wunsch mit Umzug der vorhandenen Daten.

Alte Berichte werden beim Speichern eines neuen automatisch gelöscht; standardmäßig bleiben je Berichtsart die neuesten 30 erhalten. Verlauf und Änderungsprotokoll werden nie gelöscht.

Inhalt des Berichtordners:

- `Diagnosebericht_<Datum>.html` und `.json`: Bericht mit Gesundheitswert, Trends, Diagrammen und Maßnahmen. Ein `.pdf` kommt hinzu, wenn PDF in den Einstellungen aktiviert ist (erzeugt über Microsoft Edge).
- `Verlauf\`: ein Messpunkt pro Komplett-Diagnose
- `Aenderungen.json`: das Änderungsprotokoll
- `Einstellungen.json`: Design, PDF-Option, Umfang der Komplett-Diagnose, ausgeblendete Meldungen
- `Ergebnisse_<Datum>.csv`: exportierte Ergebnisse
- `Heimnetz.json`: als bekannt gespeicherte Geräte im Heimnetz
- `hosts_Sicherung_<Datum>.txt`: Sicherung der Hosts-Datei vor dem Entfernen von Einträgen
- `Treibersicherung\<Datum>\`: Treibersicherungen (die neuesten 2)
- `Akkubericht_…`, `WLAN-Bericht_…`, `Energiebericht_…`, `Standby-Analyse_…`: ausführliche Windows-Berichte
- Sitzungsprotokolle (`Protokoll_…txt`) liegen lokal unter `%LOCALAPPDATA%\LaptopDiagnose\Protokolle`, ebenso die Angabe des gewählten Berichtordners (`Berichtordner.json`)
- **Geräteübersicht:** Lege die JSON-Berichte mehrerer Laptops in einen gemeinsamen Ordner (z. B. USB-Stick oder OneDrive) und klicke in den Einstellungen auf *Geräteübersicht erstellen*. Du bekommst eine Vergleichstabelle mit Gesundheitswert, kritischen Punkten, Akku, freiem Speicher und offenen Updates.

## Sicherheit

- Alle Prüfungen lesen nur. Geändert wird erst, wenn du Punkte auswählst und bestätigst.
- Vor Reparaturen bietet das Programm einen **Systemwiederherstellungspunkt** an.
- Jede Änderung landet im Änderungsprotokoll. Sicherheitsrelevante Verbesserungen werden bewusst nicht automatisch zurückgenommen, etwa eine eingeschaltete Firewall oder Benutzerkontensteuerung.
- Systemprozesse werden nie zum Beenden angeboten, und vor dem Beenden eines Programms warnt das Tool vor ungespeicherten Daten.
- Absturzabbilder werden erst nach 30 Tagen als Datenmüll angeboten, damit die Bluescreen-Analyse sie nutzen kann.
- Programm-Updates werden vor der Installation per **SHA-256-Prüfsumme** kontrolliert. Ist die installierte Version signiert, muss jede Datei des Updates mit **demselben Zertifikat** signiert sein. Das gilt auch für selbst ausgestellte Zertifikate. Eine nachträglich veränderte Datei wird immer abgelehnt. Wer einmal signiert ausliefert, muss weitere Updates mit demselben Zertifikat signieren. Einzige Ausnahme ist der Wechsel auf ein von Windows anerkanntes (gekauftes) Zertifikat mit demselben Herausgebernamen.

## Virenscanner meldet das Tool

Diagnose- und Reparaturskripte nutzen dieselben Windows-Funktionen wie manche Schadsoftware: Adminrechte anfordern, Autostarts ändern, Dateien löschen, Dienste steuern. Manche Virenscanner schlagen deshalb vorsorglich an. Das Tool verzichtet bewusst auf versteckte Fenster und auf Änderungen an den Defender-Einstellungen. Zur Laufzeit übersetzten Code gibt es nur bei einer Funktion: dem 1:1-Klon bzw. den Abbilddateien unter »Externe Datenträger«, und auch dort erst, wenn sie gestartet wird.

Wenn trotzdem eine Meldung erscheint:

1. Den Namen der Erkennung notieren und prüfen, welche Datei gemeldet wird.
2. Den Fehlalarm beim Hersteller melden: Bitdefender unter https://www.bitdefender.com/submit/, Microsoft unter https://www.microsoft.com/wdsi/filesubmission.
3. **Die Skripte signieren** (siehe unten). Signierte Skripte werden deutlich seltener gemeldet.
4. Nur wenn klar ist, dass es ein Fehlalarm ist: eine Ausnahme nur für den Programmordner einrichten. Den Virenschutz nicht abschalten.

## Für Entwickler: Signieren und Updates veröffentlichen

**Update-Kanal:** Das Programm liest `LaptopDiagnose/update/update.json` aus dem Hauptzweig `main` dieses Repositorys. Die Datei enthält Version, Paketname, SHA-256-Prüfsumme und Änderungsnotizen. Das Paket `LaptopDiagnose-<Version>.zip` liegt im selben Ordner. GitHub-Releases mit dem Tag `laptopdiagnose-v<Version>` werden als Ausweichweg weiterhin erkannt.

Ein neues Update veröffentlichst du so:

1. Die Version in `LaptopDiagnose.ps1` erhöhen (`$Script:ToolVersion`).
2. Unter Windows `Entwicklung\New-LaptopDiagnoseRelease.ps1 -Signieren -Notizen 'Was ist neu'` ausführen. Das Skript signiert alle Skripte, erzeugt das Paket und ersetzt Paket und `update.json` im Ordner `update`.
3. Die Änderungen committen und nach `main` übernehmen. Ab dann finden installierte Programme das Update unter *Einstellungen › Programm-Updates*.

**Gekauftes Zertifikat:** Die Anleitung in `Entwicklung\Code-Signatur.md` beschreibt Auswahl, Kauf (USB-Token oder Cloud-Signatur), Signieren und den Wechsel des Zertifikats.

`Entwicklung\Sign-LaptopDiagnose.ps1` signiert die Skripte und prüft danach jede Datei (gültig, unverändert, dasselbe Zertifikat, Zeitstempel; nur prüfen mit `-NurPruefen`). Cloud-Signatur über `signtool` mit `-SignTool -Dlib … -DlibMetadata …`. Geeignet ist z. B. auch das Zertifikat der Desktop-Organizer-Setups. Das Zertifikat kommt aus dem Zertifikatspeicher (`-Thumbprint`) oder aus einer PFX-Datei (`-PfxPath`). Auch selbst ausgestellte Zertifikate werden unterstützt.

## Konsolenversion

`Start-LaptopDiagnose-Konsole.cmd` startet die Textversion mit demselben Funktionsumfang. Aufruf mit Parametern:

```powershell
.\LaptopDiagnose.ps1                                  # Menü
.\LaptopDiagnose.ps1 -Modus Komplett                  # Komplett-Diagnose mit Reparaturangebot
.\LaptopDiagnose.ps1 -Modus Komplett -NurPruefen -Pdf # nur prüfen, Bericht auch als PDF
.\LaptopDiagnose.ps1 -Modus Sicherheit                # einzelner Bereich: Fehler, Sicherheit, Speicher, Leistung, Akku,
                                                      # Netzwerk, Software, Windows, Werkzeuge, Herunterfahren
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
| `Module\Herunterfahren.ps1` | Diagnose und Reparatur für langsames Herunterfahren |
| `Module\Werkzeuge.ps1` | Reparatur-Werkzeuge, Belastungstest, Zusatz-Apps |
| `Module\Verlauf.ps1` | Kennzahlen, Trends, Geräteübersicht |
| `Module\Aenderungen.ps1` | Änderungsprotokoll und Rückgängig |
| `Module\Wartung.ps1` | Geplante Wartung, Benachrichtigungen, Programm-Updates |
| `Module\Berichtordner.ps1` | Speicherort der Berichte, einmaliger Umzug, Aufräumen alter Berichte |
| `Module\Aufraeumen.ps1` | Downloads aufräumen, Vorher/Nachher-Vergleich |
| `Module\Hardware.ps1` | Bildwiederholrate, Arbeitsspeicher, Netzwerkkabel, Grafiktreiber, BIOS, Energie (Desktop) |
| `Module\Verknuepfungen.ps1` | Defekte Verknüpfungen und Autostart-Einträge |
| `Module\Dateien.ps1` | Doppelte Dateien, leere Ordner, große Ordner, sicheres Löschen |
| `Module\Sicherung.ps1` | Datensicherung, Wiederherstellungspunkte, alte Systemabbilder, Upgrade-Reste, alte Treiberpakete |
| `Module\Programme.ps1` | Programme deinstallieren und Reste finden |
| `Module\Browser.ps1` | Browser-Caches und -Erweiterungen |
| `Module\Autostart.ps1` | Geplante Aufgaben und Dienste beim Start |
| `Module\Datenschutz.ps1` | Datenschutz-Einstellungen, Kamera-/Mikrofonnutzung |
| `Module\SicherheitPlus.ps1` | Erweiterte Sicherheit: Ransomware-/PUA-Schutz, SmartScreen, Konten, automatische Anmeldung, Fernwartung |
| `Module\Treiber.ps1` | Treiber sichern und Anleitung zum Zurücksetzen |
| `Module\Aufwachen.ps1` | Ungewolltes Aufwachen: Weckquellen, Weckberechtigungen, Reaktivierungszeitgeber |
| `Module\Ausblenden.ps1` | Meldungen ausblenden und wieder einblenden |
| `Module\Extern.ps1` | Externe Datenträger: prüfen, reparieren, Geschwindigkeits- und Echtheitstest, formatieren, sicher entfernen |
| `Module\Partition.ps1` | Partitionswerkzeuge |
| `Module\Klonen.ps1` | Kopieren, SSD-Umzug, 1:1-Klon und Abbilddateien |
| `Module\Rettung.ps1` | Gelöschte Dateien retten, Datenträger sicher löschen |
| `Module\Browserschutz.ps1` | Browser-Entführer erkennen und beheben |
| `Module\Heimnetz.ps1` | Geräte im Heimnetz |
| `Module\Drucker.ps1` | Drucker-Diagnose |
| `Module\Audio.ps1` | Audio, Bluetooth, Lautsprecher-Test |
| `Module\Papierkorb.ps1` | Papierkorb schnell messen und leeren (inkl. verwaister Papierkörbe) |
| `Module\Spiele.ps1` | Spiele- und Grafikleistung |
| `Module\LiveMonitor.ps1` | Live-Messung, Aufzeichnung »Was bremst gerade?« und Auswertung |
| `Module\Hilfe.ps1` | Erklärungen zu jeder Prüfung (»?«) |
| `Module\Programm.ps1` | Programmname, Gerätetyp (PC/Laptop), Anpassung von Verknüpfungen nach Updates |
| `Logo.png`, `LaptopDiagnose.ico` | Logo und Programmsymbol (Vorlagen in `Entwicklung\Grafik`) |

## Voraussetzungen

- Windows 10 oder 11 mit Windows PowerShell 5.1 (vorinstalliert)
- Für Software-Updates: WinGet (App-Installer, bei Windows 11 vorinstalliert)
- Für PDF-Berichte: Microsoft Edge (vorinstalliert)
- Optional für die Debugger-Auswertung von Bluescreens: *Debugging Tools for Windows* (Teil des Windows SDK)

Copyright 2026 by Eder Tom
