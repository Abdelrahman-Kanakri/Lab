# bootstrap.ps1 — run once on each lab device

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

# 4. Enable Wake-on-LAN in Windows
powercfg /devicequery wake_programmable
# (You'll also need to enable WoL in BIOS on each machine - one time manual step)
