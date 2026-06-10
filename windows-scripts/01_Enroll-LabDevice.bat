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
echo   PRE-REQ (you must have done this manually):
echo     - Created Lab-Admin (password: 2026@admin) in Administrators group
echo       (you have to be signed in as some admin to run this script)
echo.
echo   This script will:
echo     - ASK YOU for the student username + password (use the SAME on every device)
echo     - VERIFY Lab-Admin exists in Administrators (aborts if missing)
echo     - CREATE / update the student account in the Guests group
echo     - DELETE every other non-builtin local account
echo     - Enable WinRM (Automatic startup, firewall TCP 5985 open)
echo     - Disable sleep / hibernate / Fast Startup
echo     - Enable Wake-on-LAN on every UP physical NIC (best effort)
echo.
echo   *** WARNING: All other local accounts on this device will be removed. ***
echo   *** Make sure user data is backed up first.                          ***
echo.

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp001_Enroll-LabDevice.ps1"

echo.
pause
