@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
REM The menu can uninstall this BAT; leave its context before launching.
REM PowerShell owns the interactive completion prompt and returns its exit code.
(goto) 2>nul & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Aurora_Setup.ps1"
