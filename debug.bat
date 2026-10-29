@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0GTeacherPet.ps1"
echo.
echo Please take a screenshot of any error above and send it to G Teacher.
pause
