# bootstrap_v2.ps1 — run once on each NEW lab device
# Extends the original bootstrap.ps1 to also enroll in MeshCentral in one pass.
# Prereq: controller's HTTP server (serve_files.sh) must be running and
# ~/lab/files/meshagent.msi must be present.

# 1. Enable WinRM (Windows Remote Management)
Enable-PSRemoting -Force
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "*" -Force

# 2. Enable SSH server (optional but useful)
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

# 3. Allow firewall rules
netsh advfirewall firewall add rule name="WinRM HTTP" dir=in action=allow protocol=TCP localport=5985
netsh advfirewall firewall add rule name="SSH" dir=in action=allow protocol=TCP localport=22

# 4. Report Wake-on-LAN capability (BIOS WoL still needs manual enable)
powercfg /devicequery wake_programmable

# 5. Install MeshCentral agent — pulls from controller's HTTP server
$controllerIP = "192.168.1.10"   # <-- replace with your Nobara IP
$msiUrl  = "http://$controllerIP:8080/meshagent.msi"
$msiPath = "C:\Windows\Temp\meshagent.msi"

Write-Host "Downloading MeshAgent from $msiUrl ..."
Invoke-WebRequest -Uri $msiUrl -OutFile $msiPath -UseBasicParsing

Write-Host "Installing MeshAgent silently..."
Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait

Write-Host "Verifying service..."
Get-Service "Mesh Agent" | Select-Object Name, Status

Write-Host "Bootstrap complete. Device should appear in MeshCentral within 60 seconds."
