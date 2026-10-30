@echo off
rem Start, stop and check WATcloud dev sessions from Windows. Run: .\asd-dev.cmd help
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0asd-dev.ps1" %*
exit /b %errorlevel%
