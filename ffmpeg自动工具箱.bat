@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ffmpeg_toolbox.ps1" "%~1" "%~2"
