@echo off
REM 08_Switch-ToINU.bat - launcher that self-elevates and runs 08_Switch-ToINU.ps1
REM Both files must be in the same folder.

net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo =============================================
echo   Lab Device - SWITCH labadmin -^> INU
echo =============================================
echo.
echo   This will:
echo     - Create INU (password: 2026) if missing, ensure Administrator
echo     - DELETE the local user "labadmin" if it exists
echo.
echo   IMPORTANT: Sign out of labadmin BEFORE running this script.
echo   The script refuses to delete labadmin if it is the current user.
echo.

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp008_Switch-ToINU.ps1"

echo.
pause
