@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Aurora_Setup.ps1" -Action Check -InstallDir "%~dp0."
set "AURORA_EXIT=%ERRORLEVEL%"
echo.
echo 只读检查已结束。如需修复，请运行 Aurora_Setup.bat 并选择修复运行库。
pause
exit /b %AURORA_EXIT%