@echo off
rem One-time setup on native Windows: double-click it, or run .\setup.cmd [options] (.\setup.cmd --help).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*
exit /b %errorlevel%
