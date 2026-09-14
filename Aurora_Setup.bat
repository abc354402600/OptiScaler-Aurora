@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Aurora_Setup.ps1"
set "AURORA_EXIT=%ERRORLEVEL%"
if not "%AURORA_EXIT%"=="0" pause
exit /b %AURORA_EXIT%
