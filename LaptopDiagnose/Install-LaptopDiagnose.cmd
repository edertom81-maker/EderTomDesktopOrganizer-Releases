@echo off
REM PC Repair Pro - Installation fuer den aktuellen Benutzer
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-LaptopDiagnose.ps1" %*
pause
