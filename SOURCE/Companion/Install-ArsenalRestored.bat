@echo off
rem Installs the rivet_hook version of ARSENAL_RESTORED: drag its zip onto this file, or run it and paste the path.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-ArsenalRestored.ps1" -Source "%~1"
pause
