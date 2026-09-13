@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Aurora_Setup.ps1"
set "AURORA_EXIT=%ERRORLEVEL%"
echo.
echo 操作已结束，请查看上方结果。按任意键关闭窗口。
pause >nul
exit /b %AURORA_EXIT%
