@echo off
REM PC Repair Pro - Konsolenversion
REM Startet das Diagnose-Tool im Textmodus; Administratorrechte werden automatisch angefordert.
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0LaptopDiagnose.ps1" %*
