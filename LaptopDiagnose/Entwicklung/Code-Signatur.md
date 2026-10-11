# Code-Signatur mit einem gekauften Zertifikat

Ziel: Virenscanner und Windows sollen PC Repair Pro als Programm eines bekannten Herausgebers (»Eder Tom«) erkennen und seltener Fehlalarme melden. Das Tool ist darauf vorbereitet. Fehlen nur noch das Zertifikat und ein einmaliger Signierlauf.

## 1. Zertifikat auswählen und kaufen

| Art | Kosten (ca.) | Hinweise |
|---|---|---|
| **OV-Code-Signing** (Organisation bzw. Einzelunternehmer validiert) | 100–300 € pro Jahr | Reicht für PowerShell-Skripte. Anbieter z. B. Certum, Sectigo, SSL.com, DigiCert. Certum bietet ein günstiges Zertifikat für Open-Source- bzw. Einzelentwickler an. |
| **EV-Code-Signing** | 300–600 € pro Jahr | Strengere Prüfung. Bringt bei SmartScreen inzwischen keinen Sofort-Vorteil mehr gegenüber OV und ist für dieses Tool nicht nötig. |
| **Cloud-Signatur** (z. B. Microsoft Azure Artifact Signing, früher »Trusted Signing«) | Monatsabo | Kein USB-Token nötig. Ob Einzelpersonen in Österreich bzw. Deutschland zugelassen werden, vor dem Abschluss beim Anbieter prüfen. |

Seit Juni 2023 liegt der private Schlüssel bei gekauften Zertifikaten auf einem **USB-Token** oder in einem **Cloud-Schlüsseltresor**. Eine PFX-Datei gibt es dann nicht mehr. Für die Bestätigung der Identität braucht der Anbieter in der Regel einen Ausweis und eventuell einen Gewerbe- bzw. Firmenbucheintrag. Die Ausstellung dauert meist einige Tage.

## 2. Einrichten

- **USB-Token:** Den Token-Client des Anbieters installieren (z. B. SafeNet Authentication Client oder proCertum SmartSign). Token einstecken. Danach erscheint das Zertifikat im Zertifikatspeicher (`certmgr.msc` › Eigene Zertifikate).
- **Cloud-Signatur:** Windows SDK mit `signtool.exe` sowie das Signier-Modul des Anbieters installieren (bei Azure: `Azure.CodeSigning.Dlib.dll` plus eine `metadata.json` mit Konto und Zertifikatprofil).

Den Fingerabdruck (Thumbprint) des Zertifikats anzeigen:

```powershell
Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Format-List Subject, Thumbprint, NotAfter
```

## 3. Signieren und veröffentlichen

```powershell
# USB-Token oder Zertifikatspeicher
.\Entwicklung\New-LaptopDiagnoseRelease.ps1 -Signieren -Thumbprint <Fingerabdruck> -Notizen 'Was ist neu'

# Cloud-Signatur
.\Entwicklung\New-LaptopDiagnoseRelease.ps1 -Signieren -SignTool -Dlib C:\Signing\Azure.CodeSigning.Dlib.dll -DlibMetadata C:\Signing\metadata.json -Notizen 'Was ist neu'

# Nur prüfen, ohne neu zu signieren
.\Entwicklung\Sign-LaptopDiagnose.ps1 -NurPruefen
```

Das Signierskript prüft danach jede Datei auf vier Punkte: gültig, unverändert, überall dasselbe Zertifikat und mit Zeitstempel. Der Zeitstempel sorgt dafür, dass die Signatur auch nach Ablauf des Zertifikats gültig bleibt. Ist ein Zeitstempel-Server nicht erreichbar, nimmt das Skript automatisch den nächsten.

## 4. Was beim Wechsel des Zertifikats passiert

Ist die installierte Version signiert, akzeptiert die Update-Funktion nur Updates mit demselben Zertifikat. Ab Version 3.1 gilt eine Ausnahme für den Wechsel auf ein neues Zertifikat, zum Beispiel vom selbst ausgestellten auf ein gekauftes oder nach einer Verlängerung. Erlaubt ist der Wechsel nur, wenn beides zutrifft:

- Windows vertraut dem neuen Zertifikat (von einer Zertifizierungsstelle geprüft).
- Der Herausgebername (CN) ist derselbe wie beim bisherigen Zertifikat.

Ein Update, das zwar mit einem gekauften Zertifikat, aber unter einem anderen Namen signiert ist, wird weiterhin abgelehnt.

## 5. Nach dem ersten signierten Release

- Fehlalarme, die noch auftreten, mit dem Hinweis auf die Signatur beim Hersteller melden (siehe README, Abschnitt »Virenscanner meldet das Tool«).
- Den Ablauf des Zertifikats im Kalender vormerken und rechtzeitig verlängern. Bereits veröffentlichte Versionen bleiben dank Zeitstempel gültig.
