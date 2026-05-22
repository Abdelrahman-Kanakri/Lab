@echo off
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo =============================================
echo   Lab Shutdown Schedule - REMOVE
echo =============================================
echo.
set /p CONFIRM="Remove all shutdown/wake tasks? (Y/N): "
if /i not "%CONFIRM%"=="Y" goto END

powershell.exe -ExecutionPolicy Bypass -File "%~dp006_Remove-ShutdownSchedule.ps1"

:END
echo.
pause
