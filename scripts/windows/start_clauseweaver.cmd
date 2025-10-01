@echo off
setlocal enabledelayedexpansion

set "SCRIPT_DIR=%~dp0"
set "PROJECT_ROOT=%SCRIPT_DIR%..\.."
for %%I in ("%PROJECT_ROOT%") do set "PROJECT_ROOT=%%~fI"

powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Launch-ClauseWeaver.ps1" -ProjectRoot "%PROJECT_ROOT%" %*

endlocal
