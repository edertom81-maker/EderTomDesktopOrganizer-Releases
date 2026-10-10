# Merkliste

Stand: 10.10.2026. Neue Wünsche hier ergänzen.

## Offen (noch nicht gebaut)

14. **Defekte Verknüpfungen finden** (Bereich »Fehlersuche«, läuft in der Komplett-Diagnose mit):
    - Geprüft werden Desktop (eigener und »Öffentlicher Desktop«), Startmenü (eigenes und für alle Benutzer), angeheftete Taskleisten-Programme, Autostart-Ordner und Autostart-Einträge in der Registry.
    - Defekt heißt: Das Ziel (Datei oder Ordner) existiert nicht mehr, z. B. nach einer Deinstallation.
    - Nicht melden: Ziele auf Netzlaufwerken, USB-Sticks oder externen Platten, die gerade nicht verbunden sind.
    - Reparatur nach Auswahl in der Ankreuz-Liste: Verknüpfungen in den Papierkorb, defekte Autostart-Einträge deaktivieren (rückgängig über »Änderungen«).
15. **Umfang der Komplett-Diagnose wählbar** (Einstellungen › Komplett-Diagnose): je Prüfbereich ein Haken – Fehlersuche, Speicherfresser, Leistungsbremsen, Herunterfahren, Akku, Netzwerk & WLAN, Software-Updates, Sicherheit, Windows & Treiber – plus der vorhandene Haken für die Speicherbelegung. Standard: alle an (Speicherbelegung aus). Gilt für Fenster, Konsole und geplante Wartung. Mindestens ein Bereich muss gewählt bleiben. »Akku« erscheint nur bei Laptops. Abgewählte Bereiche lassen sich weiterhin einzeln über »Prüfen« starten; Bericht und Verlauf weisen aus, welche Bereiche nicht geprüft wurden.

## Erledigt in Version 2.5.2

13. Einstellung **»Speicherbelegung in die Komplett-Diagnose aufnehmen«** (Standard: aus). Ist sie an, läuft in der Komplett-Diagnose die Ordner-Analyse mit Kachelgrafik mit (`Invoke-MemoryScan -Tiefenanalyse`, dauert 1–2 Minuten länger). Gilt für Fenster, Konsole und geplante Wartung.

## Erledigt in Version 2.5.0 / 2.5.1

## Arbeitsweise

- Vor dem Bauen immer fragen, ob gebaut werden soll oder ob noch etwas hinzukommt. Erst nach »bauen« umsetzen.
- Neue Versionen kommen als Pull Request mit Update-Paket in `LaptopDiagnose/update/`. Nach dem Zusammenführen findet das Tool das Update über *Einstellungen › Nach Updates suchen*.

## Umbenennung und Logo

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

## Desktop-PC-Unterstützung

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
