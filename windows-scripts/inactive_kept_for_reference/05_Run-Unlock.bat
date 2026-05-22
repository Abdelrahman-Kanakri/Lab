@echo off
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo =============================================
echo   Student Device - UNLOCK
echo =============================================
echo.
echo   This will RE-ENABLE installs, personalization,
echo   and password changes. Use for maintenance only.
echo.
set /p CONFIRM="Proceed? (Y/N): "
if /i not "%CONFIRM%"=="Y" goto END

powershell.exe -ExecutionPolicy Bypass -File "%~dp005_Unlock-StudentDevice.ps1"

:END
echo.
pause
