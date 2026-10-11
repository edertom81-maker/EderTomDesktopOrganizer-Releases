# Merkliste

Stand: 11.10.2026. Neue Wünsche hier ergänzen.

## Offen (noch nicht gebaut)

36. **Partitionswerkzeuge** (Bereich »Externe Datenträger«; gilt auch für **interne Zusatzlaufwerke**, z. B. eine zweite Festplatte im Desktop-PC – der Datenträger mit Windows bzw. Boot-/Systempartitionen bleibt immer ausgeschlossen):
    - **Partitionsübersicht als Grafik** je Datenträger (Leiste wie in der Datenträgerverwaltung mit Partitionen und freiem Bereich) plus Tabelle: Buchstabe, Name, Dateisystem, Größe, belegt.
    - **Partition erstellen** im freien Bereich (Größe, Dateisystem, Name, Laufwerksbuchstabe).
    - **Datenträger aufteilen** (Assistent, z. B. 32 GB FAT32 fürs Autoradio + Rest exFAT; löscht alle Daten).
    - **Partition löschen** (Inhalt anzeigen, Bestätigung durch Eintippen des Laufwerksbuchstabens).
    - **Vergrößern** in angrenzenden freien Platz und **Verkleinern** ohne Datenverlust – Windows kann das nur bei NTFS; bei exFAT/FAT32 Erklärung statt Versuch; vor dem Verkleinern Dateisystem prüfen.
    - **Laufwerksbuchstaben ändern/entfernen**, **Namen ändern**.
    - **In NTFS umwandeln ohne Datenverlust** (FAT32/exFAT → NTFS, nur in diese Richtung; Hinweis, dass Mac/TV/Autoradio danach meist nicht mehr schreiben können).
    - Sicherheit wie bisher: Prüfung vor jeder Änderung, Bestätigung durch Eintippen bei Löschen/Aufteilen, Protokoll. Bewusst nicht: Partitionen verschieben oder zusammenführen mit Datenerhalt (kann Windows nicht von sich aus, riskant).

Bewusst weiterhin nicht: Registry-Reiniger, Treiber von Drittanbieter-Seiten, automatische Reparaturen ohne Rückfrage, »RAM-Booster« und ähnliche Schein-Optimierer.

## Erledigt in Version 3.2.0

Umsetzungshinweise:
- Die Geschwindigkeit misst der Windows-Leistungstest (WinSAT), weil er den Zwischenspeicher umgeht. Steht er nicht zur Verfügung, misst das Tool selbst mit einer großen Testdatei.
- Der Echtheitstest hängt das Laufwerk zwischen Schreiben und Lesen aus (`fsutil volume dismount`), damit wirklich vom Datenträger gelesen wird.
- Die vollständige Dateisystemprüfung läuft nur bei »Datenträger prüfen«. In der Komplett-Diagnose wird nur der Fehlerzustand abgefragt, das ist schneller.
- Neu ist »Abbrechen« unten rechts für lange Tests.

35. **Externe Datenträger prüfen, reparieren, formatieren** (eigener Bereich in der Seitenleiste; nur USB-Sticks, externe Festplatten/SSDs und SD-Karten – interne Laufwerke und das Systemlaufwerk werden nie angeboten):
    - **Prüfen (nur lesen):** Übersicht je Datenträger (Name, Größe, Dateisystem, belegt/frei, BitLocker To Go), Zustand (SMART, soweit das USB-Gehäuse es durchreicht; Lese-/Schreibfehler aus dem Ereignisprotokoll), Dateisystem nur prüfen. Erkennen: FAT32 (keine Dateien über 4 GB), nicht ordnungsgemäß entfernt, kein Laufwerksbuchstabe, offline, schreibgeschützt, Dateisystem »RAW«.
    - **Ausführlicher Geschwindigkeitstest:** sequenzielles Schreiben und Lesen mit großer Testdatei (z. B. 1 GB bzw. passend zum freien Platz), zufälliges Lesen/Schreiben kleiner Blöcke (4 KB), mehrere Durchgänge, Ergebnis in MB/s mit Diagramm und Einordnung (z. B. »typisch für USB 2.0 – steckt der Stick an einem USB-3-Anschluss?«). Testdateien werden danach gelöscht.
    - **Echtheitstest gegen gefälschte Kapazität** (wie H2testw): freien Platz mit prüfbaren Testdaten füllen, zurücklesen und vergleichen; Ergebnis »echte nutzbare Kapazität« bzw. »Fälschung«. Vorhandene Dateien bleiben unberührt (getestet wird der freie Platz; für eine vollständige Prüfung den Datenträger vorher leeren). Mit Fortschritt, Restzeit und Abbrechen; dauert je nach Größe bis zu Stunden.
    - **Reparieren (nach Auswahl):** Dateisystemfehler beheben (Laufwerk wird kurz getrennt, Hinweis auf offene Dateien), Laufwerksbuchstaben zuweisen, Offline-Datenträger online schalten, per Richtlinie gesetzten Schreibschutz aufheben (umkehrbar); mechanischer Schalter → Hinweis. Bei »RAW« keine Reparatur, sondern Hinweis auf Datenrettung.
    - **Formatieren (doppelt abgesichert):** Dateisystem mit Empfehlung (exFAT für Austausch mit Mac/TV/Kamera, FAT32 bis 32 GB für Autoradio/ältere Geräte, NTFS nur Windows/Sicherungen), Name, Schnell- oder vollständige Formatierung; Option »komplett neu einrichten« bei falscher Partitionierung bzw. fehlender Kapazität. Vorher Anzeige des Inhalts, Bestätigung durch Eintippen des Laufwerksbuchstabens, deutlicher Hinweis »nicht umkehrbar«, Eintrag im Protokoll.
    - Knopf **»Sicher entfernen«**.
    - **Komplett-Diagnose:** nur der Prüfteil und nur bei angestecktem externem Datenträger; in den Einstellungen abwählbar. Reparieren, Tests und Formatieren nie automatisch.

## Erledigt in Version 3.1.0

Umsetzungshinweise:
- Papierkorb: Statt `SHEmptyRecycleBin` (das wie `Clear-RecycleBin` über die Windows-Shell arbeitet und zur Laufzeit übersetzten Code bräuchte) wird der Papierkorb direkt im Dateisystem geleert. Das gilt für den eigenen Papierkorb und für verwaiste Papierkörbe gelöschter Konten. Papierkörbe anderer vorhandener Konten bleiben unberührt und werden nicht mitgezählt. Temporäre Dateien werden schneller gelöscht (`[IO.File]::Delete` statt `Remove-Item`). Die Dauer je Bereich steht im Protokoll.
- Spiele: Energiemodus und visuelle Effekte werden nur angezeigt und über die Windows-Einstellungen geändert. Spielmodus, Hintergrundaufzeichnung und GPU-Planung (nur bei eigener Grafikkarte) setzt das Tool nach Auswahl, umkehrbar.
- Live-Monitor: Prozessorlast je Programm aus den Prozessorzeiten, gruppiert nach Programmname. Datenträger und Netzwerk gibt es nur als Gesamtwerte. Die Aufzeichnung gibt es zusätzlich als Werkzeug »Was bremst gerade?« (auch in der Konsole).
- Feinschliff: CSV-Export und Suche gibt es im Programmfenster. Die Signatur-Vorbereitung umfasst USB-Token, Cloud-Signatur, eine Prüfung nach dem Signieren und den Zertifikatwechsel bei Updates (gekauft und derselbe Herausgebername). Den Kauf des Zertifikats erledigt der Benutzer, die Anleitung steht in `Entwicklung/Code-Signatur.md`.

29. **Live-Monitor:** laufende Anzeige von CPU, RAM, Datenträger, Netzwerk und Temperatur mit den größten Verbrauchern; Aufzeichnung über 1–2 Minuten »Was bremst gerade?« mit Auswertung.
30. **Spiele- und Grafikleistung:** Spielmodus, Hardware-beschleunigte GPU-Planung, Energiemodus (Windows-Leistungsregler), visuelle Effekte, Game-Bar-Aufzeichnung im Hintergrund; Empfehlungen nach Auswahl setzen, umkehrbar.
31. **Feinschliff:**
    - Vorbereitung für eine echte Code-Signatur (gekauftes Zertifikat, ca. 100–300 €/Jahr; Kauf durch den Benutzer) – Signier-Skript und Anleitung, damit Virenscanner/SmartScreen nicht mehr warnen.
    - Suchfeld und Filter (Schweregrad, behebbar) in den Ergebnissen, Export der Ergebnisse als CSV.
    - »?« an jeder Prüfung mit kurzer Erklärung, warum sie wichtig ist.

34. **Datenmüll entfernen beschleunigen:** Das Entfernen dauert sehr lange, obwohl das meiste im Papierkorb liegt. Vermutete Ursachen: `Clear-RecycleBin` leert über die Windows-Shell Datei für Datei; dazu wird der Papierkorb vorher und für den Vorher/Nachher-Vergleich erneut vollständig vermessen. Geplant: Papierkorb direkt über die Windows-Funktion `SHEmptyRecycleBin` (ohne Rückfrage, Fortschrittsanzeige und Ton) leeren, Größe über `SHQueryRecycleBin` statt Ordnerdurchlauf ermitteln, Fortschritt je Bereich anzeigen (»Papierkorb wird geleert …«), Dauer der einzelnen Bereiche im Protokoll festhalten.

## Erledigt in Version 3.0.0

Umsetzungshinweise: Defender-Einstellungen (Ransomware-, PUA-Schutz) werden nur gelesen; geändert wird über »Windows-Sicherheit«, weil direkte Defender-Änderungen von Virenscannern als verdächtig gemeldet werden. Ein Klartext-Kennwort der automatischen Anmeldung wird gelöscht und bewusst nicht im Änderungsprotokoll gesichert (dieser Teil ist nicht umkehrbar). Ausblenden und Wiedereinblenden geschieht im Fenster; Konsole und geplante Wartung halten sich an die Liste. Statt `powercfg /lastwake` werden die Weckquellen der letzten 7 Tage aus dem Ereignisprotokoll ausgewertet.

26. **Erweiterte Sicherheit:** überwachter Ordnerzugriff (Ransomware-Schutz), PUA-Schutz, SmartScreen, Konten ohne Passwort, automatische Anmeldung, Gastkonto, installierte bzw. automatisch startende Fernwartungsprogramme (AnyDesk, TeamViewer, RustDesk …) mit Hinweis.
27. **Treiber sichern:** vor Treiber-Updates (und als Werkzeug) alle Fremdtreiber mit `Export-WindowsDriver` in einen Ordner sichern; Hinweis, wie ein Treiber im Geräte-Manager zurückgesetzt bzw. aus der Sicherung installiert wird.
28. **Ungewolltes Aufwachen:** letzte Weckquelle (`powercfg /lastwake`), Weck-Zeitgeber, Geräte mit Weckberechtigung (Maus, Netzwerkkarte …), Standby-Abbrüche aus dem Ereignisprotokoll; Weckberechtigung nach Auswahl entziehen (umkehrbar).
33. **Meldungen ausblenden:**
    - An jeder Ergebniskarte (Warnung, Hinweis, auch »Kritisch«) ein Knopf »Ausblenden«; die Meldung erscheint bei späteren Prüfungen nicht mehr.
    - Wiedererkennung über Bereich und Prüfung (stabiler Schlüssel), nicht über den genauen Text – z. B. bleibt »Ladegrenze« ausgeblendet, auch wenn sich der Prozentwert ändert.
    - Optional »Nur diese Ausprägung ausblenden« (z. B. genau dieser Dienst oder diese Erweiterung), damit neue Funde derselben Prüfung trotzdem erscheinen.
    - Ausgeblendete Meldungen zählen nicht in Gesundheitswert und Zählung; der Bericht nennt am Ende »N Meldungen ausgeblendet«.
    - Unter *Einstellungen › Ausgeblendete Meldungen* eine Liste mit Datum des Ausblendens; einzeln oder alle wieder einblenden.
    - Gilt für Fenster, Konsole und geplante Wartung (Benachrichtigungen nur für nicht ausgeblendete Meldungen). Gespeichert in den Einstellungen im Berichtordner.

## Erledigt in Version 2.9.0

Umsetzungshinweise: Die Programmliste ist nach Größe sortiert (kein eigener Filter – kommt mit Punkt 31). Standortdienst wird nur angezeigt, nicht umgestellt; der Aktivitätsverlauf entfällt (unter Windows 11 nicht mehr vorhanden), dafür Eingabe-Personalisierung, Feedback-Anfragen und Sprachliste für Webseiten.

21. **Datensicherung prüfen:** Windows-Sicherung, Dateiversionsverlauf, OneDrive-Ordnersicherung (Dokumente/Bilder/Desktop) und Systemabbild erkennen, letztes Sicherungsdatum anzeigen. Warnung, wenn keine oder eine veraltete Sicherung existiert (besonders zusammen mit SMART-Problemen). Knopf öffnet die passenden Windows-Einstellungen.
22. **Programme deinstallieren:** Liste aller installierten Programme (Desktop-Programme und Store-Apps) mit Größe, Installationsdatum, Hersteller; sortier- und filterbar. Deinstallation nur über den offiziellen Deinstaller nach Auswahl. Danach Suche nach Resten (Ordner in Programme/AppData, Verknüpfungen, Autostart) zur Auswahl. Systemkomponenten und Treiber werden nicht angeboten.
23. **Browser aufräumen:** Caches von Edge, Chrome, Firefox (und Brave/Opera, falls vorhanden) messen und in den Datenmüll aufnehmen; nur bei geschlossenem Browser löschen. Cookies, Passwörter, Verlauf und Lesezeichen werden nie angefasst. Zusätzlich installierte Erweiterungen auflisten und bekannte Werbe-/Spionage-Erweiterungen hervorheben (Entfernen über die Browser-Einstellungen).
24. **Autostart vollständig:** zusätzlich geplante Aufgaben, die bei Anmeldung/Start laufen (z. B. Updater), und automatisch startende Dienste von Fremdherstellern anzeigen; deaktivieren nach Auswahl, rückgängig über »Änderungen«. Windows-eigene Aufgaben und Dienste sowie Virenschutz werden nicht angeboten.
25. **Datenschutz-Einstellungen:** Telemetrie-Stufe, Werbe-ID, personalisierte Werbung/Tipps, Standortdienst, Aktivitätsverlauf, Websuche im Startmenü prüfen; empfohlene Werte nach Auswahl setzen, alles umkehrbar. Anzeige, welche Apps zuletzt auf Kamera und Mikrofon zugegriffen haben.
32. **Alte Sicherungen und Wiederherstellungsdaten** (Bereich »Speicherfresser«, passt zu Punkt 21):
    - Wiederherstellungspunkte: belegter Platz und Obergrenze anzeigen, Warnung bei sehr viel Platz; ältere Punkte nach Auswahl entfernen (der neueste bleibt immer), Obergrenze einstellbar (`vssadmin`), umkehrbar soweit möglich.
    - Alte Systemabbild-Sicherungen (`WindowsImageBackup`, auch auf externen Platten) mit Datum und Größe; nur ältere Sicherungen zum Löschen anbieten, die neueste bleibt.
    - Dateiversionsverlauf: Platzbedarf alter Versionen anzeigen, Aufräumen älterer Versionen über die Windows-Funktion anstoßen.
    - Reste von Windows-Upgrades: `$WINDOWS.~BT`, `$WINDOWS.~WS`, `C:\ESD`, `$GetCurrent` (nur wenn kein Upgrade läuft).
    - Alte Treiberpakete im Treiberspeicher (DriverStore): ältere Versionen desselben Treibers nach Auswahl entfernen (`pnputil`), der aktive Treiber bleibt.
    - Alte Windows-Protokolle (CBS-, DISM- und Setup-Logs) über einer Größe von z. B. 100 MB.
    - Löschen nur nach Auswahl, Eintrag im Änderungsprotokoll; was nicht in den Papierkorb kann, über die Karte »Endgültig löschen?«.

## Erledigt in Version 2.8.0

20. **Details anklicken:** Doppelklick auf eine Zeile mit Pfad in den Detail-Listen öffnet den Ordner im Explorer (Dateien werden markiert; fehlt der Pfad, öffnet sich der nächste vorhandene Ordner).
19. **Werkzeug »Entwickler-Reste finden«** (Bereich »Speicherfresser« und »Reparatur-Werkzeuge«; Anlass: `Dokumente\Codex` belegt 52 GB):
    - Sucht Ordner, die sich jederzeit neu erzeugen lassen: `node_modules`, `.venv`/`venv`/`env` (mit `pyvenv.cfg`), `__pycache__`, `.pytest_cache`, `.mypy_cache`, `build`/`dist`/`out`/`target`/`bin`/`obj` (nur neben einer Projektdatei wie `package.json`, `pyproject.toml`, `Cargo.toml`, `*.csproj`, `pom.xml`), `.gradle`, `.next`, `.nuxt`, `.parcel-cache`, `.turbo`.
    - Zusätzlich die globalen Paket-Caches von npm, pip, NuGet, Yarn und Gradle (im Benutzerprofil).
    - Durchsucht Dokumente, Desktop, Downloads, Codex-Arbeitsordner und typische Projektordner (`source\repos`, `Projects`); auf Wunsch eigener Ordner.
    - Eigener Code und Git-Verläufe (`.git`) werden nie angeboten.
    - Anzeige gruppiert nach Projekt (Projektordner, Art, Größe, letzte Änderung), sortiert nach Größe. Vorausgewählt nur Reste aus Projekten, die seit mehr als 30 Tagen nicht geändert wurden.
    - Hinweis in der Karte: Die Ordner werden beim nächsten Bauen/Starten des Projekts neu erzeugt (z. B. `npm install`, `pip install`).
    - Löschen in den Papierkorb bzw. über die Karte »Endgültig löschen?«, wenn zu groß. Eintrag im Änderungsprotokoll.

## Erledigt in Version 2.7.0

16. **Doppelte Dateien finden und zum Löschen anzeigen** (bisher nur im Downloads-Ordner):
    - Neues Werkzeug »Doppelte Dateien suchen« (Bereich »Reparatur-Werkzeuge«, zusätzlich als Knopf im Bereich »Speicherfresser«). Läuft nicht in der Komplett-Diagnose mit, weil dafür viele Dateien gelesen werden müssen.
    - Durchsucht standardmäßig Dokumente, Bilder, Videos, Musik, Desktop und Downloads; auf Wunsch ein selbst gewählter Ordner bzw. Laufwerk (z. B. externe Platte).
    - Gleich heißt gleicher Inhalt (Größe, dann Prüfsumme) – nicht nur gleicher Name. Standard ab 1 MB Dateigröße. Windows-, Programm- und Systemordner sowie reine OneDrive-Cloud-Dateien werden nicht angefasst.
    - Anzeige gruppiert je Duplikat-Gruppe mit Pfad, Größe und Datum, sortiert nach freigebbarem Platz. Vorausgewählt sind alle Kopien außer einer (die älteste bzw. die im Dokumente-Ordner bleibt). Alles lässt sich vor dem Löschen ändern.
    - Löschen nur in den Papierkorb, Eintrag im Änderungsprotokoll.
17. **Leere Ordner aufspüren und löschen**:
    - Werkzeug »Leere Ordner suchen« (Bereich »Reparatur-Werkzeuge« und Knopf im Bereich »Speicherfresser«), dieselben Orte wie bei Punkt 16, auf Wunsch eigener Ordner/Laufwerk.
    - Leer heißt: keine Dateien, auch nicht in Unterordnern. Reine Windows-Hilfsdateien (desktop.ini, Thumbs.db) zählen nicht als Inhalt. Ein Ordner, der nur leere Unterordner enthält, erscheint als ein Eintrag.
    - Nie angeboten: die Benutzerordner selbst (Dokumente, Bilder …), AppData, Programm- und Systemordner, OneDrive-Ordner mit Cloud-Dateien sowie Ordner, die gerade ein Programm benutzt.
    - Anzeige als Ankreuz-Liste mit Pfad und Änderungsdatum, alle vorausgewählt. Löschen in den Papierkorb, Eintrag im Änderungsprotokoll.
    - Nach dem Löschen von Duplikaten (Punkt 16) bietet das Tool an, dabei leer gewordene Ordner gleich mit zu entfernen.
18. **Große Ordner im Bereich »Speicherfresser« anzeigen und zum Löschen auswählen**:
    - Liste der größten Ordner innerhalb der Benutzerordner (Dokumente, Bilder, Videos, Musik, Desktop, Downloads) – bis in zwei Ebenen Tiefe, z. B. »Downloads\Altes Projekt – 12 GB« – mit Größe, Anzahl Dateien und letzter Änderung; auf Wunsch eigener Ordner/Laufwerk.
    - Auswahl per Ankreuz-Liste, nichts ist vorausgewählt. Vor dem Löschen eine Zusammenfassung mit Gesamtgröße zur Bestätigung.
    - Löschen in den Papierkorb. Passt ein Ordner nicht mehr in den Papierkorb (Windows würde endgültig löschen), fragt das Tool dafür ausdrücklich nach bzw. überspringt ihn. Eintrag im Änderungsprotokoll.
    - Programm-, Windows- und Systemordner sowie AppData werden nur angezeigt, nicht zum Löschen angeboten – dort mit Hinweis auf »Apps deinstallieren« bzw. die Datenträgerbereinigung. Die Benutzerordner selbst sind nie löschbar.
    - Die Kachelgrafik der Speicherbelegung bekommt dazu eine Detailstufe: Klick auf eine Kachel zeigt deren größte Unterordner.

## Erledigt in Version 2.6.0

14. **Defekte Verknüpfungen finden** (Bereich »Fehlersuche«, läuft in der Komplett-Diagnose mit):
    - Geprüft werden Desktop (eigener und »Öffentlicher Desktop«), Startmenü (eigenes und für alle Benutzer), angeheftete Taskleisten-Programme, Autostart-Ordner und Autostart-Einträge in der Registry.
    - Defekt heißt: Das Ziel (Datei oder Ordner) existiert nicht mehr, z. B. nach einer Deinstallation.
    - Nicht melden: Ziele auf Netzlaufwerken, USB-Sticks oder externen Platten, die gerade nicht verbunden sind.
    - Reparatur nach Auswahl in der Ankreuz-Liste: Verknüpfungen in den Papierkorb, defekte Autostart-Einträge deaktivieren (rückgängig über »Änderungen«).
15. **Umfang der Komplett-Diagnose wählbar** (Einstellungen › Komplett-Diagnose): je Prüfbereich ein Haken – Fehlersuche, Speicherfresser, Leistungsbremsen, Herunterfahren, Akku, Netzwerk & WLAN, Software-Updates, Sicherheit, Windows & Treiber – plus der vorhandene Haken für die Speicherbelegung. Standard: alle an (Speicherbelegung aus). Gilt für Fenster, Konsole und geplante Wartung. Mindestens ein Bereich muss gewählt bleiben. »Akku« erscheint nur bei Laptops. Abgewählte Bereiche lassen sich weiterhin einzeln über »Prüfen« starten; Bericht und Verlauf weisen aus, welche Bereiche nicht geprüft wurden.

## Erledigt in Version 2.5.2

13. Einstellung **»Speicherbelegung in die Komplett-Diagnose aufnehmen«** (Standard: aus). Ist sie an, läuft in der Komplett-Diagnose die Ordner-Analyse mit Kachelgrafik mit (`Invoke-MemoryScan -Tiefenanalyse`, dauert 1–2 Minuten länger). Gilt für Fenster, Konsole und geplante Wartung.

## Arbeitsweise

- Vor dem Bauen immer fragen, ob gebaut werden soll oder ob noch etwas hinzukommt. Erst nach »bauen« umsetzen.
- Neue Versionen kommen als Pull Request mit Update-Paket in `LaptopDiagnose/update/`. Nach dem Zusammenführen findet das Tool das Update über *Einstellungen › Nach Updates suchen*.

## Erledigt in Version 2.5.0 / 2.5.1

### Umbenennung und Logo

1. Neuer Name **»PC Repair Pro«** an allen sichtbaren Stellen: Fenstertitel, Startmenü, Desktop-Verknüpfung, »Installierte Apps«, Berichte, Benachrichtigungen und Konsole.
   - Die Oberfläche bleibt auf Deutsch. Englisch sind nur der Name und der Slogan »Diagnose • Repair • Keep it running«.
   - Intern bleibt »LaptopDiagnose«: Programmordner, Berichtordner, Update-Kanal, Aufgabe der geplanten Wartung. So funktionieren Updates und der Verlauf weiter.
   - Hinweis: Den Namen vor einer Weitergabe auf Markenrechte prüfen.
2. Neues Programmsymbol: `Entwicklung/Grafik/PC-Repair-Pro.ico` (16 bis 256 px) ersetzt `LaptopDiagnose.ico`.
3. Logo im Tool:
   - Seitenleiste: kleines Symbol mit dem Schriftzug »PC Repair Pro«
   - *Einstellungen › Über*: großes Logo mit Slogan
   - Kopf des HTML-Berichts
   - Vorlagen: `Entwicklung/Grafik/PC-Repair-Pro-Logo.webp` (Logo mit Schriftzug) und `PC-Repair-Pro-Symbol.webp` (App-Symbol)

### Desktop-PC-Unterstützung

4. Gerätetyp erkennen (Desktop oder Laptop, über die Gehäuseart). Auf einem Desktop wird der Bereich »Akku« ausgeblendet, und die Texte sagen »PC« statt »Laptop«.
5. Energie- und Standby-Empfehlungen für Desktop-Rechner anpassen, ohne Akku-Hinweise.
6. Bildwiederholrate: erkennen, wenn ein Monitor mit weniger Hz läuft, als er kann (z. B. 60 statt 144 Hz). Ein Knopf öffnet die Anzeigeeinstellungen.
7. Arbeitsspeicher:
   - Prüfen, ob der eingestellte Takt unter dem Nenntakt liegt (XMP/EXPO aus).
   - Single-Channel erkennen (nur ein Riegel).
8. Netzwerkkabel (LAN): Verbindungsgeschwindigkeit (100 Mbit/s statt 1 Gbit/s deutet auf ein Kabel- oder Portproblem hin) und Verbindungsabbrüche.
9. Grafikkarte: Alter des NVIDIA-, AMD- oder Intel-Treibers, mit Link zur Hersteller-App.
10. Alle Laufwerke: Gesundheit und Belegung, auch bei HDDs. Warnung, wenn Windows auf einer HDD statt einer SSD läuft.
11. Temperatur: Hinweis auf verstaubte Lüfter, wenn die Temperatur unter Last stark steigt (auf dem vorhandenen Belastungstest aufbauen).
12. BIOS-Alter: Hinweis bei einem mehrere Jahre alten BIOS, mit Link zur Support-Seite des Herstellers.

Die Punkte 6 bis 9 helfen auch auf Laptops.
