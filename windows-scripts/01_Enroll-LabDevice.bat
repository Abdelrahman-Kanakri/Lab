@echo off
REM Enroll-LabDevice.bat - launcher that self-elevates and runs 01_Enroll-LabDevice.ps1
REM Both files must be in the same folder.

net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo =============================================
echo   Lab Device - ENROLLMENT
echo =============================================
echo.
echo   This will:
echo     - Create/update local admin "labadmin" (password: 2026)
echo     - Enable WinRM (Automatic startup, firewall open)
echo     - Set TrustedHosts to allow remote connections
echo.

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp001_Enroll-LabDevice.ps1"

echo.
pause
