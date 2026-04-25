@echo off
REM Enable-WinRM.bat - drop on USB, double-click on each lab device
REM Self-elevates to Administrator, then enables WinRM persistently.

net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Requesting Administrator privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo.
echo =============================================
echo   Enable WinRM for Lab Management
echo =============================================
echo.

powershell.exe -ExecutionPolicy Bypass -NoProfile -Command ^
    "Enable-PSRemoting -Force; Set-Service -Name WinRM -StartupType Automatic; Start-Service WinRM; Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force; netsh advfirewall firewall add rule name='WinRM HTTP' dir=in action=allow protocol=TCP localport=5985 2>$null; Get-Service WinRM | Select Name,Status,StartType; (Get-NetFirewallRule -DisplayGroup 'Windows Remote Management' -ErrorAction SilentlyContinue | Select DisplayName,Enabled)"

echo.
echo Done. Verify above: WinRM should be Running, StartType Automatic.
echo.
pause
