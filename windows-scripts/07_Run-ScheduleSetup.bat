@echo off
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo =============================================
echo   Lab Shutdown Schedule - SETUP
echo =============================================
echo.
echo   This will:
echo     - Set timezone to Jordan (Amman, UTC+3)
echo     - Wake device at 08:00 (Sat-Wed)
echo     - Hide Shutdown/Restart 08:00-16:00 (Sat-Wed)
echo     - Force shutdown at 16:00 every day
echo.
echo   For auto power-on from OFF state, enable
echo   "RTC Wake Alarm" in your BIOS/UEFI.
echo.
set /p CONFIRM="Proceed? (Y/N): "
if /i not "%CONFIRM%"=="Y" goto END

powershell.exe -ExecutionPolicy Bypass -File "%~dp007_Setup-ShutdownSchedule.ps1"

:END
echo.
pause
