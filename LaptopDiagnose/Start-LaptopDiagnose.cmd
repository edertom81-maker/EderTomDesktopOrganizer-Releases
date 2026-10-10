@echo off
REM Laptop-Diagnose ^& Reparatur - Startdatei
REM Startet das Diagnose-Tool; Administratorrechte werden automatisch angefordert.
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0LaptopDiagnose.ps1" %*
