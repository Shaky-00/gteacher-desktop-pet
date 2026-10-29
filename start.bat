@echo off
setlocal
cd /d "%~dp0"
start "G Teacher Pet" powershell.exe -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0GTeacherPet.ps1"
exit /b 0
