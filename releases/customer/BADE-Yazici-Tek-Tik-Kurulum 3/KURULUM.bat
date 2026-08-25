@echo off
setlocal
title BADE BCWMS Yazici Kurulumu

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0kurulum.ps1"
if errorlevel 1 (
  echo.
  echo Kurulum tamamlanamadi. Yukaridaki hata mesajini destek ekibine iletin.
  pause
  exit /b 1
)

exit /b 0
