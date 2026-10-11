# Merkliste

Stand: 10.10.2026. Neue Wünsche hier ergänzen.

## Offen (noch nicht gebaut)

Geplant: Version 3.0 = 26–28, Version 3.1 = 29–31.

26. **Erweiterte Sicherheit:** überwachter Ordnerzugriff (Ransomware-Schutz), PUA-Schutz, SmartScreen, Konten ohne Passwort, automatische Anmeldung, Gastkonto, installierte bzw. automatisch startende Fernwartungsprogramme (AnyDesk, TeamViewer, RustDesk …) mit Hinweis.
27. **Treiber sichern:** vor Treiber-Updates (und als Werkzeug) alle Fremdtreiber mit `Export-WindowsDriver` in einen Ordner sichern; Hinweis, wie ein Treiber im Geräte-Manager zurückgesetzt bzw. aus der Sicherung installiert wird.
28. **Ungewolltes Aufwachen:** letzte Weckquelle (`powercfg /lastwake`), Weck-Zeitgeber, Geräte mit Weckberechtigung (Maus, Netzwerkkarte …), Standby-Abbrüche aus dem Ereignisprotokoll; Weckberechtigung nach Auswahl entziehen (umkehrbar).
29. **Live-Monitor:** laufende Anzeige von CPU, RAM, Datenträger, Netzwerk und Temperatur mit den größten Verbrauchern; Aufzeichnung über 1–2 Minuten »Was bremst gerade?« mit Auswertung.
30. **Spiele- und Grafikleistung:** Spielmodus, Hardware-beschleunigte GPU-Planung, Energiemodus (Windows-Leistungsregler), visuelle Effekte, Game-Bar-Aufzeichnung im Hintergrund; Empfehlungen nach Auswahl setzen, umkehrbar.
31. **Feinschliff:**
    - Vorbereitung für eine echte Code-Signatur (gekauftes Zertifikat, ca. 100–300 €/Jahr; Kauf durch den Benutzer) – Signier-Skript und Anleitung, damit Virenscanner/SmartScreen nicht mehr warnen.
    - Suchfeld und Filter (Schweregrad, behebbar) in den Ergebnissen, Export der Ergebnisse als CSV.
    - »?« an jeder Prüfung mit kurzer Erklärung, warum sie wichtig ist.

Bewusst weiterhin nicht: Registry-Reiniger, Treiber von Drittanbieter-Seiten, automatische Reparaturen ohne Rückfrage, »RAM-Booster« und ähnliche Schein-Optimierer.

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
