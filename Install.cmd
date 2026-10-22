@echo off
rem Double-click to install Power Manager. Runs Install.ps1, which asks for admin rights once.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
if errorlevel 1 pause
