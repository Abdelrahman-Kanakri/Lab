# Lab Implementation — Step-by-Step

Build the entire system from scratch on a fresh Nobara Linux box, ending with all lab Windows devices enrolled in MeshCentral and reachable via Ansible.

Replace every `<CONTROLLER_IP>` with the Linux box's lab-network IP. Get it with:
```bash
ip -4 addr show | grep -oP '(?<=inet\s)10\.3\.\d+\.\d+'
```

---

## Phase 1 — Linux Controller Setup

### 1.1 Install prerequisites

```bash
sudo dnf install -y ansible nmap wol nodejs npm
pip install --user pywinrm
ansible-galaxy collection install ansible.windows community.windows
```

Verify:
```bash
ansible --version | head -1
python3 -c "import winrm; print('pywinrm OK')"
```

### 1.2 Set the controller IP

Edit [~/lab/config.env](../config.env):
```
export CONTROLLER_IP="10.3.5.96"   # ← your actual IP
```

### 1.3 Install MeshCentral server

```bash
~/lab/install_server.sh
```

What this script does (idempotent — safe to re-run):
1. Installs Node.js / npm (if missing)
2. `npm install meshcentral` into `~/lab/meshcentral/`
3. `sudo setcap` to let Node bind ports 80/443
4. Generates self-signed certs (first run only)
5. Writes systemd unit `/etc/systemd/system/meshcentral.service`
6. Opens firewalld ports 80/443
7. Enables and starts the service

End state: `https://<CONTROLLER_IP>` is live with self-signed cert.

### 1.4 Claim the admin account

In a browser on the Nobara box:
1. Open `https://<CONTROLLER_IP>` → accept self-signed cert warning
2. Click **Create Account** → first account becomes site admin
3. Enable 2FA (My Account → Security)

### 1.5 Create the device group

In the web UI:
1. **My Devices → Add Device Group**
2. Name: `Lab` — Type: **Manage using a software agent** → Save

### 1.6 Download the agent installer

1. Click into the `Lab` group → **Add Agent**
2. Operating System: **Windows**, Installation Type: **Background & interactive**
3. Click **Windows x86-64 (.exe)** to download
4. Move it to the standard location:
   ```bash
   mv ~/Downloads/meshagent64-Lab.exe ~/lab/files/meshagent.exe
   ```

The `.exe` has the server URL **baked into it**. If the controller IP changes, regenerate this file.

---

## Phase 2 — Lab Device Enrollment (per-device, physical visit once)

This phase requires walking to each lab device with a USB stick.

### 2.1 Prepare a USB stick

Copy the entire `~/lab/windows-scripts/` folder to a USB stick. Required files:
- `Enroll-LabDevice.bat`
- `Enroll-LabDevice.ps1`

Optional (if you also need to lock or schedule devices):
- `Lock-StudentDevice.ps1` + `Run-Lock.bat`
- `Setup-SleepSchedule.ps1` + `Run-ScheduleSleepSetup.bat`
- `Reset-Passwords.ps1` + `Run-ResetPasswords.bat`

### 2.2 First-time-only on the USB: unblock the files

Windows tags files copied via certain methods with "Mark of the Web" (SmartScreen blocks them). On any one Windows machine, plug in the USB and run PowerShell as Admin:

```powershell
Get-ChildItem -Path D:\ -Recurse -Include *.bat,*.ps1 | Unblock-File
```

(Replace `D:\` with your actual USB drive letter.)

### 2.3 On each lab device

1. Plug in USB
2. Right-click **Enroll-LabDevice.bat** → **Run as administrator** (or just double-click and accept UAC)
3. Wait for green `[OK]` lines and the final state readout
4. Verify the readout shows:
   - `WinRM: Running, Automatic`
   - `labadmin` listed under Administrators
5. Eject and move to next device

What this does on each device:
- Creates local user `labadmin` with password `2026` (or updates if exists)
- Adds `labadmin` to Administrators group
- `Enable-PSRemoting -Force`, sets WinRM to Automatic startup, starts service
- Sets `WSMan:\localhost\Client\TrustedHosts = *`
- Opens firewall TCP 5985

The existing student account (`pc`, `student`, etc.) and any existing lockdown policies are **untouched**.

---

## Phase 3 — MeshCentral Enrollment (from Linux, automated)

### 3.1 Discover newly-enrolled devices

```bash
~/lab/add_devices.sh
```

What this does:
1. TCP-scans `10.3.5.0/24` for hosts with port 5985 open
2. Diffs against current `~/lab/hosts.ini` to find what's new
3. Tests Ansible auth (`labadmin/2026`) on the new hosts
4. Shows you the list and asks for confirmation
5. Runs the [enroll_with_unlock.yml](../playbooks/enroll_with_unlock.yml) playbook on confirmed-working hosts
6. Merges them into `~/lab/hosts.ini`

The playbook flow per device:
```
Stage scripts → Unlock (lifts DisableMSI + SRP) → Install MeshAgent → Re-Lock → Verify
```

Why the unlock/lock wrap: [Lock-StudentDevice.ps1](../windows-scripts/Lock-StudentDevice.ps1) sets `DisableMSI=2` and SRP rules that block installer execution. We lift these temporarily, install the agent (which registers as a SYSTEM service), then re-apply the lockdown. The agent service survives re-locking.

### 3.2 Verify

```bash
~/lab/check_lab.sh
```

Reports for each device in inventory:
- WinRM reachability
- `Mesh Agent` service status
- Lock state (`Locked` or `UNLOCKED`)

Then in the web UI: open `https://<CONTROLLER_IP>` → `Lab` group → all enrolled devices appear with green (online) or grey (offline) dots.

---

## Phase 4 — Ongoing Operations

### 4.1 Add new devices (after re-imaging or initial walk)

After running `Enroll-LabDevice.bat` on the new devices, just:
```bash
~/lab/add_devices.sh
```

It only enrolls hosts not already in inventory.

### 4.2 Daily check

```bash
~/lab/check_lab.sh
```

Pay attention to:
- Devices marked `UNLOCKED` (failed mid-playbook → re-run `add_devices.sh` on just those)
- Devices marked `Mesh Agent: Stopped` (rare; restart the service via Ansible)

### 4.3 Common ops via Ansible

```bash
# Shutdown all
ansible lab -i ~/lab/hosts.ini -m win_command -a "shutdown /s /t 0" --forks 50

# Restart all
ansible lab -i ~/lab/hosts.ini -m win_command -a "shutdown /r /t 0" --forks 50

# Push a file to all
ansible lab -i ~/lab/hosts.ini -m win_copy \
    -a "src=~/lab/files/<file> dest=C:\\Users\\Public\\<file>" --forks 50

# Run PowerShell on all
ansible lab -i ~/lab/hosts.ini -m win_shell -a "<command>" --forks 50

# Re-apply lockdown if any device drifted
ansible lab -i ~/lab/hosts.ini -m win_shell \
    -a "powershell -ExecutionPolicy Bypass -File C:\\Path\\Lock-StudentDevice.ps1" --forks 50
```

### 4.4 Common ops via MeshCentral (web UI)

| Task | How |
|---|---|
| Power: shutdown / restart / wake | Right-click device(s) → Power |
| Remote desktop | Click device → **Desktop** tab |
| Remote PowerShell | Click device → **Terminal** tab |
| File transfer | Click device → **Files** tab |
| Run script on group | Group → **Run Command** |
| Live process list | Click device → **Processes** |

---

## Phase 5 — Troubleshooting

### Server won't start after reboot
The `setcap` from 1.3 persists, but if Node is updated via `dnf` it resets:
```bash
sudo setcap 'cap_net_bind_service=+ep' "$(readlink -f $(command -v node))"
sudo systemctl restart meshcentral
```

### Agent installed but doesn't appear in UI
```bash
ansible <host> -i ~/lab/hosts.ini -m win_shell \
    -a "Test-NetConnection <CONTROLLER_IP> -Port 443"
```
If `False` → firewall on the Windows host or network blocks 443. Open it.

### Forgot admin password
```bash
sudo systemctl stop meshcentral
cd ~/lab/meshcentral
node node_modules/meshcentral --resetaccount <ADMIN_USER> --pass <NEW_PASS>
sudo systemctl start meshcentral
```

### A device won't accept Ansible auth
Confirm `labadmin` exists and has password `2026`:
```powershell
# Run locally on the device as Admin
Get-LocalUser labadmin
```
If missing → re-run `Enroll-LabDevice.bat` on that device.

### A device is in inventory but offline (UNREACHABLE)
Most often: the device is asleep or off. Wake it via MeshCentral UI (right-click → Wake-up) or physically. The Mesh Agent reconnects automatically on boot.

---

## Phase 6 — Backup

```bash
sudo systemctl stop meshcentral
tar czf ~/lab/backups/meshcentral-$(date +%F).tgz \
    -C ~/lab/meshcentral meshcentral-data
sudo systemctl start meshcentral
```

The `meshcentral-data` folder contains:
- All device-group config
- All registered users + 2FA secrets
- Self-signed cert authority (regenerating loses agent trust)
- Device database

Schedule weekly: `crontab -e` → `0 3 * * 0 ~/lab/backup.sh` (write a wrapper).

---

## Phase 7 — Customization (different IP / port / subnet)

If a teammate is rebuilding this on **their own machine** with a different IP, port, or lab subnet, here's exactly what to change.

### 7.1 Change the controller IP

Use this when the Linux server moves to a different IP (new machine, different network, DHCP reassignment).

#### Step 1 — Update the central config

Edit [~/lab/config.env](../config.env):
```bash
export CONTROLLER_IP="<NEW_IP>"
```

All scripts ([install_server.sh](../install_server.sh), [add_devices.sh](../add_devices.sh), [check_lab.sh](../check_lab.sh), [serve_files.sh](../serve_files.sh)) source this file, so they pick up the change automatically.

#### Step 2 — Update the systemd unit

The unit file has the IP baked in via `--cert <IP>`. Edit:
```bash
sudo nano /etc/systemd/system/meshcentral.service
```
Change the `ExecStart=` line:
```
ExecStart=/usr/bin/node /home/abood/lab/meshcentral/node_modules/meshcentral --cert <NEW_IP>
```
Reload + restart:
```bash
sudo systemctl daemon-reload
sudo systemctl restart meshcentral
```

#### Step 3 — Regenerate the agent installer

**Critical:** the existing `meshagent.exe` has the OLD IP baked into it. New devices won't know where to phone home until you replace it.

1. Open `https://<NEW_IP>` → log in
2. `Lab` group → **Add Agent** → Windows x86-64 (.exe)
3. Save → replace `~/lab/files/meshagent.exe`:
   ```bash
   mv ~/Downloads/meshagent64-Lab.exe ~/lab/files/meshagent.exe
   ```

#### Step 4 — Re-point existing agents (optional, only if IP truly changes)

If the IP change is permanent and you want already-enrolled devices to find the new server:

```bash
# Run on each device via Ansible (while old IP is still working)
ansible lab -i ~/lab/hosts.ini -m win_shell \
    -a "& 'C:\\Program Files\\Mesh Agent\\MeshAgent.exe' -meshaction:changeserver -server:wss://<NEW_IP>:443/agent.ashx" \
    --forks 50
```

If the old IP is already gone, you'll need to push the new agent .exe to each device and reinstall.

### 7.2 Change ports

#### MeshCentral HTTPS port (default 443)

Edit `~/lab/meshcentral/meshcentral-data/config.json`:
```json
{
  "settings": {
    "port": 8443,
    "redirport": 8080,
    "exactports": true
  }
}
```

If using a port **below 1024** (like default 443/80), `setcap` is required (already done in install_server.sh). For ports above 1024, no setcap needed:
```bash
# remove the cap if not needed
sudo setcap -r "$(readlink -f $(command -v node))"
```

After editing config.json:
```bash
sudo systemctl restart meshcentral
```

Update firewalld:
```bash
sudo firewall-cmd --permanent --remove-port=443/tcp
sudo firewall-cmd --permanent --remove-port=80/tcp
sudo firewall-cmd --permanent --add-port=8443/tcp
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

After changing the port, the URL becomes `https://<CONTROLLER_IP>:8443` and you must regenerate the agent .exe (Step 7.1 → Step 3) so new agents use the new port.

#### Agent (mesh) port (default uses HTTPS port)

By default the MeshAgent connects over the same port as HTTPS. To split them, set in config.json:
```json
{
  "settings": {
    "agentport": 4433
  }
}
```

#### WinRM port (default 5985)

To use HTTPS WinRM (5986) for stronger transport, on each lab device:
```powershell
# Run on the device locally as Admin
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=`"$env:COMPUTERNAME`"; CertificateThumbprint=`"$($cert.Thumbprint)`"}"
New-NetFirewallRule -Name 'WinRM-HTTPS' -DisplayName 'WinRM HTTPS' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5986
```

Then update [~/lab/hosts.ini](../hosts.ini):
```ini
[lab:vars]
ansible_port=5986
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
ansible_winrm_scheme=https
```

Update the WinRM scan in [add_devices.sh](../add_devices.sh) — change `5985` to `5986`.

### 7.3 Change the lab subnet

If devices are on a different subnet (not `10.3.5.0/24`):

#### Step 1 — Update config.env
```bash
export LAB_RANGE_START="<NEW_SUBNET>.1"
export LAB_RANGE_END="<NEW_SUBNET>.254"
```

#### Step 2 — Update add_devices.sh
Edit [~/lab/add_devices.sh](../add_devices.sh) — change the line:
```bash
SUBNET="10.3.5"
```
to your new subnet (e.g. `SUBNET="192.168.1"`).

#### Step 3 — Update hosts.ini

Either let `add_devices.sh` rebuild it from scratch (delete the `[lab]` IP block first), or manually replace the IPs.

### 7.4 Change the admin username on lab devices

Default: `labadmin / 2026`. To change:

#### Step 1 — Update [Enroll-LabDevice.ps1](../windows-scripts/Enroll-LabDevice.ps1)

Edit the variables at the top:
```powershell
$user = "newadmin"
$pass = ConvertTo-SecureString "newpassword" -AsPlainText -Force
```

#### Step 2 — Update hosts.ini
```ini
[lab:vars]
ansible_user=newadmin
ansible_password=newpassword
```

#### Step 3 — Re-walk all devices with the updated USB
Run the modified `Enroll-LabDevice.bat` on each device. The script handles "user already exists" by updating the password.

#### Step 4 — Update add_devices.sh and check_lab.sh

Search for `labadmin` and `2026` in those scripts — there are inline inventory generators that need the same credentials.

### 7.5 Quick reference — what to change for each scenario

| Scenario | Files to edit |
|---|---|
| New controller IP | [config.env](../config.env), `/etc/systemd/system/meshcentral.service`, regenerate `meshagent.exe` |
| New MeshCentral port | `meshcentral-data/config.json`, firewalld, regenerate `meshagent.exe` |
| New WinRM port | each Windows device locally, [hosts.ini](../hosts.ini), [add_devices.sh](../add_devices.sh) |
| New lab subnet | [config.env](../config.env), [add_devices.sh](../add_devices.sh), [hosts.ini](../hosts.ini) |
| New admin user | [Enroll-LabDevice.ps1](../windows-scripts/Enroll-LabDevice.ps1), [hosts.ini](../hosts.ini), [add_devices.sh](../add_devices.sh), [check_lab.sh](../check_lab.sh) |
| Move server to a new machine entirely | Backup `meshcentral-data/`, restore on new host (Phase 6 in reverse), then 7.1 |

### 7.6 Sanity check after any change

```bash
# Confirm playbooks still parse
for f in ~/lab/playbooks/*.yml; do
    ansible-playbook --syntax-check -i ~/lab/hosts.ini "$f"
done

# Confirm Ansible can reach lab
ansible lab -i ~/lab/hosts.ini -m win_ping --forks 50

# Confirm MeshCentral is up on the new endpoint
curl -k https://<NEW_IP>:<NEW_PORT>/

# Full health check
~/lab/check_lab.sh
```
