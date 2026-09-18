@echo off
title BCWMS Print Agent Kaldirma

echo.
echo  ==========================================
echo    BCWMS Print Agent - Kaldirma
echo  ==========================================
echo.

set "INSTALLER_DIR=%~dp0"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER_DIR%uninstall.ps1"

if errorlevel 1 (
    echo.
    echo  *** HATA: Kaldirma basarisiz. Yukaridaki mesaji kontrol edin. ***
    echo.
)

echo.
pause
