@echo off
setlocal
title KITOKO Yazici Kurulumu
powershell.exe -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0kurulum.ps1"
if errorlevel 1 (
  echo Kurulum tamamlanamadi. Hata mesajini destek ekibine iletin.
  pause
  exit /b 1
)
exit /b 0
