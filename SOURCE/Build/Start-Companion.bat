@echo off
rem Starts the randomizer companion (saves and restores randomizer progress). Keep this window open while playing.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RandoCompanion.ps1"
pause
