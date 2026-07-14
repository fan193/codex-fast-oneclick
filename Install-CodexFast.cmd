@echo off
setlocal
cd /d "%~dp0"

where pwsh.exe >nul 2>&1
if %errorlevel% equ 0 (
    set "POWERSHELL_EXE=pwsh.exe"
) else (
    set "POWERSHELL_EXE=powershell.exe"
)

echo Codex Fast one-click installer
echo.
"%POWERSHELL_EXE%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-CodexFast.ps1"
set "INSTALL_EXIT=%errorlevel%"

echo.
if not "%INSTALL_EXIT%"=="0" (
    echo Installation failed with exit code %INSTALL_EXIT%.
    echo Read the error above. No unsupported patch is written to app.asar.
) else (
    echo Installation completed.
)
echo.
pause
exit /b %INSTALL_EXIT%
