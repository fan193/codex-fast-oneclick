@echo off
setlocal
cd /d "%~dp0"

where pwsh.exe >nul 2>&1
if %errorlevel% equ 0 (
    set "POWERSHELL_EXE=pwsh.exe"
) else (
    set "POWERSHELL_EXE=powershell.exe"
)

"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore-CodexStore.ps1"
set "RESTORE_EXIT=%errorlevel%"
echo.
pause
exit /b %RESTORE_EXIT%
