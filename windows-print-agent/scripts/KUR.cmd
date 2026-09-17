@echo off
setlocal
chcp 65001 >nul
title BCWMS Print Agent - Kurulum
echo.
echo   BCWMS Print Agent kuruluyor...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0kur-tek-tik.ps1"
echo.
pause
