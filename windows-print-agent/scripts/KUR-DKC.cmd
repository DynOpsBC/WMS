@echo off
setlocal
chcp 65001 >nul
title DKC Print Agent - Tek Tik Kurulum
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0kur-dkc.ps1"
set "INSTALL_RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %INSTALL_RESULT%
