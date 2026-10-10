@echo off
REM Laptop-Diagnose ^& Reparatur - grafische Oberflaeche
REM Startet das Programmfenster; Administratorrechte werden automatisch angefordert.
start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Minimized -File "%~dp0LaptopDiagnoseGUI.ps1" %*
