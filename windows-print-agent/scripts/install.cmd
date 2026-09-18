@echo off
title BCWMS Print Agent Kurulum

echo.
echo  ==========================================
echo    BCWMS Print Agent - Kurulum Basliyor
echo  ==========================================
echo.

set "INSTALLER_DIR=%~dp0"

for %%I in ("%INSTALLER_DIR%..") do set "PACKAGE_ROOT=%%~fI"

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER_DIR%install.ps1" -SourceDirectory "%PACKAGE_ROOT%\app"

if errorlevel 1 (
    echo.
    echo  *** HATA: Kurulum basarisiz. Yukaridaki mesaji kontrol edin. ***
    echo.
    pause
    exit /b 1
)

echo.
echo  Kurulum tamamlandi.
echo.
pause
