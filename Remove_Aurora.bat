@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
REM Leave the BAT context before removal; no attempt to reread a deleted BAT.
REM PowerShell owns the interactive completion prompt and returns its exit code.
(goto) 2>nul & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Aurora_Setup.ps1" -Action Remove -InstallDir "%~dp0."
