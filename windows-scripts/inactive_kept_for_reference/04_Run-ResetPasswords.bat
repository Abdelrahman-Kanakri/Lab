@echo off
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo =============================================
echo   Password Reset - All Local Users
echo =============================================
echo.
echo   This will reset every enabled local user
echo   password to "2026".
echo.

powershell.exe -ExecutionPolicy Bypass -File "%~dp004_Reset-Passwords.ps1"

echo.
pause
