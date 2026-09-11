@echo off
rem ASCII only -- cmd.exe decodes .cmd as ANSI/936
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Fix-Modex-Admin.ps1" %*