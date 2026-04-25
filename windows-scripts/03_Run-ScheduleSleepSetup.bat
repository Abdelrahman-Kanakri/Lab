@echo off
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo =============================================
echo   Lab Sleep Schedule - SETUP
echo =============================================
echo.
echo   This will:
echo     - Set timezone to Jordan (Amman, UTC+3)
echo     - Wake device from sleep at 08:00 (Sat-Wed)
echo     - Force SLEEP at 16:00 every day
echo     - Shutdown/Restart stay available at all times
echo.
echo   No BIOS changes needed - wake timers
echo   work natively from sleep mode.
echo.
set /p CONFIRM="Proceed? (Y/N): "
if /i not "%CONFIRM%"=="Y" goto END

powershell.exe -ExecutionPolicy Bypass -File "%~dp003_Setup-SleepSchedule.ps1"

:END
echo.
pause
