@echo off
setlocal
title DKC Print Agent 1.1.3 - Tek Tik Kurulum
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0update-dkc-one-click.ps1"
set "INSTALL_RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %INSTALL_RESULT%
