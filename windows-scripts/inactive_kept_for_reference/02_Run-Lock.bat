@echo off
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo =============================================
echo   Student Device - LOCK
echo =============================================
echo.
echo   This will block:
echo     - Microsoft Store installs
echo     - MSI and EXE installers
echo     - Wallpaper / theme changes
echo     - Password changes
echo     - Registry Editor (non-admin)
echo.
set /p CONFIRM="Proceed? (Y/N): "
if /i not "%CONFIRM%"=="Y" goto END

powershell.exe -ExecutionPolicy Bypass -File "%~dp002_Lock-StudentDevice.ps1"

:END
echo.
pause
