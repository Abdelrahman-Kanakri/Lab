# Lab Implementation — Step-by-Step

Build the entire system from scratch on a fresh Nobara/Fedora Linux box, ending
with all lab Windows devices enrolled in MeshCentral and reachable via Ansible.

Replace every `<CONTROLLER_IP>` with the Linux box's lab-network IP. Get it with:
```bash
ip -4 addr show | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' | grep -v '^127\.'
```

Default values used throughout:
- Controller IP: `10.3.5.96`
- Lab subnet: `10.3.5.0/24`
- Lab device admin: `labadmin` / `2026`
- MeshCentral admin: `admin`

> **Already built? You're in the wrong file.**
> This doc is for the first-time build of a fresh controller. For ongoing
> adjustments (rotate password, change IP, move subnet, swap admin user, etc.)
> use [`06_CONTROLLER_CONFIG.md`](06_CONTROLLER_CONFIG.md) — it's a per-setting
> cookbook with copy-paste commands. Per-Windows-device settings live in
> [`05_DEVICE_CONFIG.md`](05_DEVICE_CONFIG.md).

---

## Phase 0 — Prerequisites

### 0.1 OS / shell

A fresh Nobara (or Fedora) install with sudo access for the user running this
setup. Examples assume the user is `abood` and home is `/home/abood`. Adjust
paths if different.

### 0.2 Get the repo

```bash
cd ~
git clone <repo-url> lab          # or rsync/copy from another machine
cd ~/lab
```

`~/lab/` should contain `config.env`, `hosts.ini`, the four numbered shell
scripts, `playbooks/`, `windows-scripts/`, `meshcentral/`, and `docs/`.

### 0.3 Install runtime dependencies

```bash
# Node.js (for MeshCentral)
sudo dnf install -y nodejs npm

# Ansible + WinRM client (user-level, no sudo needed for these)
pip3 install --user ansible pywinrm

# Windows collection for ansible
~/.local/bin/ansible-galaxy collection install ansible.windows community.windows

# wakeonlan (for WoL of lab devices)
sudo dnf install -y wakeonlan || pip3 install --user wakeonlan
```

Verify:
```bash
node --version                                # v18+
~/.local/bin/ansible --version | head -1      # ansible [core 2.X]
python3 -c "import winrm; print('pywinrm OK')"
```

`~/lab/config.env` already exports `~/.local/bin` to PATH, so any script that
sources it will find `ansible`. To get it in your interactive shell now:
```bash
source ~/lab/config.env
which ansible       # → /home/abood/.local/bin/ansible
```

---

## Phase 1 — Linux Controller Setup (MeshCentral)

### 1.1 Set the controller IP

Edit [`~/lab/config.env`](../config.env):
```bash
export CONTROLLER_IP="10.3.5.96"     # ← your actual IP
```

All scripts source this file; one edit propagates everywhere.

### 1.2 Bootstrap MeshCentral

```bash
~/lab/01_install_server.sh
```

What this idempotent script does:
1. `sudo dnf install -y nodejs npm`
2. `npm install meshcentral` into `~/lab/meshcentral/`
3. `sudo setcap` so Node can bind ports 80/443
4. Generates self-signed certs on first run
5. Writes `/etc/systemd/system/meshcentral.service`
6. Opens firewalld 80/443 (skipped if firewalld absent)
7. `systemctl enable --now meshcentral`

End state: `https://<CONTROLLER_IP>` is live with a self-signed cert.

### 1.3 Harden `meshcentral-data/config.json`

Out of the box, MeshCentral writes a sample `config.json` with every setting
prefixed by `_` (which the parser ignores) and a placeholder `sessionKey`.
**Do not skip this step** — without a real `sessionKey` every browser session
invalidates on service restart, and `_newAccounts` left default allows random
signups against your server.

Edit `~/lab/meshcentral/meshcentral-data/config.json`:
```json
{
  "settings": {
    "sessionKey": "<paste output of: openssl rand -hex 32>"
  },
  "domains": {
    "": {
      "newAccounts": false
    }
  }
}
```
Note: the keys go in **without** the leading underscore. Then:
```bash
sudo systemctl restart meshcentral
```

### 1.4 Claim the admin account

In a browser on the Nobara box, before you set `newAccounts: false`:
1. Open `https://<CONTROLLER_IP>` → accept self-signed cert warning
2. Click **Create Account** → first account becomes site admin
   - Use username `admin` (or any short identifier; the email is just a profile field, not the login)
3. Enable 2FA: **My Account → Security**
4. **Now** apply step 1.3's `newAccounts: false` and restart

If you later forget the password:
```bash
sudo systemctl stop meshcentral
cd ~/lab/meshcentral
node node_modules/meshcentral --resetaccount admin --pass 'NewPassword'
sudo systemctl start meshcentral
```

### 1.5 Create the device group

In the web UI:
1. **My Devices → Add Device Group**
2. Name: `Lab` — Type: **Manage using a software agent** → Save

### 1.6 Stage the agent installer

When MeshCentral first runs, it generates server-signed agent binaries at:
```
~/lab/meshcentral/meshcentral-data/signedagents/MeshService64.exe
```

These are pre-keyed to **this** server's certificate fingerprint. Copy the
Windows x64 one into `~/lab/files/` so the playbooks can push it:
```bash
cp ~/lab/meshcentral/meshcentral-data/signedagents/MeshService64.exe ~/lab/files/
```

The `.exe` has the server URL **baked into it**. If the controller IP ever
changes, regenerate `signedagents/` (just restart MeshCentral after the IP
change) and re-copy.

> **Alternative:** the web UI also offers an MSI download (Lab group → Add
> Agent → Windows x64 MSI). The exe-from-signedagents path above is simpler
> because it doesn't depend on the web UI being up, and it installs the same
> service.

---

## Phase 2 — Lab Device Enrollment (per-device, physical visit once)

This phase requires walking to each lab device with a USB stick.

### 2.1 Prepare the USB stick

Copy the entire [`~/lab/windows-scripts/`](../windows-scripts/) folder to a USB
stick. Required:
- `01_Enroll-LabDevice.bat` + `01_Enroll-LabDevice.ps1`

Optional (only if you also want to lock or schedule devices):
- `02_Lock-StudentDevice.ps1` + `02_Run-Lock.bat`
- `03_Setup-SleepSchedule.ps1` + `03_Run-ScheduleSleepSetup.bat`
- `04_Reset-Passwords.ps1` + `04_Run-ResetPasswords.bat`

### 2.2 First-time-only on the USB: unblock the files

Windows tags files copied via the internet/some methods with "Mark of the Web"
(SmartScreen blocks them). On any one Windows machine, plug in the USB and run
PowerShell as Admin:
```powershell
Get-ChildItem -Path D:\ -Recurse -Include *.bat,*.ps1 | Unblock-File
```
(Replace `D:\` with your actual USB drive letter.)

### 2.3 On each lab device

1. Plug in USB
2. Right-click `01_Enroll-LabDevice.bat` → **Run as administrator**
3. Wait for green `[OK]` lines and the final state readout
4. Verify the readout shows:
   - `WinRM: Running, Automatic`
   - `labadmin` listed under Administrators
5. Eject and move to next device

What this does on each device:
- Creates local user `labadmin` (password `2026`); updates if exists
- Adds `labadmin` to Administrators
- `Enable-PSRemoting -Force`, sets WinRM to Automatic, starts service
- Sets `WSMan:\localhost\Client\TrustedHosts = *`
- Opens firewall TCP 5985

The existing student account and any pre-existing lockdown policies are
**untouched**.

---

## Phase 3 — MeshCentral Enrollment (from Linux, automated)

### 3.1 Discover and enroll newly-bootstrapped devices

```bash
~/lab/02_add_devices.sh
```

Flow:
1. TCP-scans `10.3.5.0/24` for hosts with port 5985 open
2. Diffs against current [`hosts.ini`](../hosts.ini) to find new hosts
3. Tests Ansible auth (`labadmin/2026`) on the new ones
4. Shows the list and asks for confirmation
5. Runs [`playbooks/01_enroll_with_unlock.yml`](../playbooks/01_enroll_with_unlock.yml)
6. Merges the successful hosts into `hosts.ini`

The playbook flow per device:
```
Stage scripts → Unlock (lifts DisableMSI + SRP) → Install MeshAgent → Re-Lock → Verify
```

Why the unlock/lock wrap: [`02_Lock-StudentDevice.ps1`](../windows-scripts/02_Lock-StudentDevice.ps1)
sets `DisableMSI=2` and SRP rules that block installer execution. We lift these
temporarily, run `MeshService64.exe -fullinstall` (registers the agent as a
SYSTEM service), then re-apply the lockdown. The agent service survives.

### 3.2 Verify

```bash
~/lab/03_check_lab.sh
```

Reports for each device in inventory:
- WinRM reachability
- `Mesh Agent` service status
- Lock state (`Locked` / `UNLOCKED`)

In the web UI: open `https://<CONTROLLER_IP>` → `Lab` group → enrolled devices
appear with green (online) or grey (offline) dots.

### 3.3 Collect MAC addresses (for Wake-on-LAN)

```bash
python3 ~/lab/collect_macs.py
```

This pulls each reachable device's physical MAC over WinRM and writes one per
line to `~/lab/macs.txt`. Wake the whole lab with:
```bash
xargs -a ~/lab/macs.txt -I{} wakeonlan {}
```

WoL is BIOS-dependent — make sure each device has it enabled in BIOS *before*
you rely on this. That's a one-time physical task.

---

## Phase 4 — Ongoing Operations

### 4.1 Add new devices

After running `01_Enroll-LabDevice.bat` on the new devices:
```bash
~/lab/02_add_devices.sh
```
Only enrolls hosts not already in inventory.

### 4.2 Daily check

```bash
~/lab/03_check_lab.sh
```
Pay attention to:
- `UNLOCKED` devices (failed mid-playbook → re-run `02_add_devices.sh` on them)
- `Mesh Agent: Stopped` (rare; restart via Ansible)

### 4.3 File distribution

```bash
~/lab/04_serve_files.sh
```
Serves `~/lab/files/` on `http://<CONTROLLER_IP>:8080` so devices can pull via
`Invoke-WebRequest`. Or push directly:
```bash
ansible lab -i ~/lab/hosts.ini -m win_copy \
  -a "src=~/lab/files/<file> dest=C:\\Users\\Public\\<file>" --forks 50
```

### 4.4 Common Ansible ops

```bash
# Shutdown all
ansible lab -i ~/lab/hosts.ini -m win_command -a "shutdown /s /t 0" --forks 50

# Restart all
ansible lab -i ~/lab/hosts.ini -m win_command -a "shutdown /r /t 0" --forks 50

# Run PowerShell on all
ansible lab -i ~/lab/hosts.ini -m win_shell -a "<command>" --forks 50

# Re-apply lockdown if any device drifted
ansible lab -i ~/lab/hosts.ini -m win_shell \
  -a "powershell -ExecutionPolicy Bypass -File C:\\Users\\Public\\02_Lock-StudentDevice.ps1" \
  --forks 50
```

### 4.5 Common ops via MeshCentral (web UI)

| Task | Where |
|---|---|
| Power: shutdown / restart / wake | Right-click device(s) → Power |
| Remote desktop | Click device → **Desktop** tab |
| Remote PowerShell | Click device → **Terminal** tab |
| File transfer | Click device → **Files** tab |
| Run script on group | Group → **Run Command** |
| Live process list | Click device → **Processes** |

### 4.6 Delete a stale device record

If a device is decommissioned or shows up under the wrong name, remove it via
the web UI (right-click → Delete Device) or via CLI:
```bash
cd ~/lab/meshcentral
node node_modules/meshcentral/meshctrl.js \
  --url wss://<CONTROLLER_IP> \
  --loginuser admin --loginpass '<PASSWORD>' \
  ListDevices                                # find the node//... id
node node_modules/meshcentral/meshctrl.js \
  --url wss://<CONTROLLER_IP> \
  --loginuser admin --loginpass '<PASSWORD>' \
  RemoveDevice --id 'node//<id-from-above>'
```

---

## Phase 5 — Troubleshooting

### Server won't bind 443 after node update
The `setcap` from 1.2 resets when Node is updated via dnf:
```bash
sudo setcap 'cap_net_bind_service=+ep' "$(readlink -f $(command -v node))"
sudo systemctl restart meshcentral
```

### Agent installed but doesn't appear in UI
```bash
ansible <host> -i ~/lab/hosts.ini -m win_shell \
  -a "Test-NetConnection <CONTROLLER_IP> -Port 443"
```
`False` → firewall on the Windows host (or network) blocks 443. Open it.

### Sessions invalidate on every server restart
Symptom: every `systemctl restart meshcentral` logs everyone out. Cause: no
real `sessionKey` set in `config.json`. Fix: redo step 1.3.

### Random people creating accounts on your server
Symptom: unfamiliar users appear in **Manage Users** in the UI. Cause:
`newAccounts` was never set to `false`. Fix: redo step 1.3 then delete the
unwanted users in the UI.

### A device won't accept Ansible auth
Run on the device locally (as Admin):
```powershell
Get-LocalUser labadmin
```
Missing or wrong password → re-run `01_Enroll-LabDevice.bat` on that device.

### A device is in inventory but unreachable
Most often: asleep or off. Wake via MeshCentral UI (right-click → Wake-up) or
WoL (`wakeonlan <MAC>`). Mesh Agent reconnects on boot.

### Forgot admin password
See step 1.4.

---

## Phase 6 — Backup

```bash
sudo systemctl stop meshcentral
mkdir -p ~/lab/backups
tar czf ~/lab/backups/meshcentral-$(date +%F).tgz \
  -C ~/lab/meshcentral meshcentral-data
sudo systemctl start meshcentral
```

`meshcentral-data/` contains:
- All device-group config
- All registered users + 2FA secrets
- Self-signed cert authority — **regenerating loses agent trust** (every
  device would need its agent reinstalled from a fresh `signedagents/`)
- Device database

Schedule weekly: `crontab -e`:
```
0 3 * * 0 cd ~/lab && sudo systemctl stop meshcentral && tar czf backups/meshcentral-$(date +\%F).tgz -C meshcentral meshcentral-data && sudo systemctl start meshcentral
```

---

## Phase 7 — Customization (different IP / port / subnet / credentials)

If a teammate is rebuilding this on **their own machine** with a different IP,
port, or lab subnet, here's exactly what to change.

> For changes to an **already-running** controller (not a rebuild), prefer
> [`06_CONTROLLER_CONFIG.md`](06_CONTROLLER_CONFIG.md) — same content but
> organized as a per-setting cookbook with verification commands.

### 7.1 Change the controller IP

#### Step 1 — Update the central config
Edit [`config.env`](../config.env):
```bash
export CONTROLLER_IP="<NEW_IP>"
```

#### Step 2 — Update the systemd unit
The unit has the IP baked in via `--cert <IP>`. Edit:
```bash
sudo nano /etc/systemd/system/meshcentral.service
# change ExecStart= to: ... meshcentral.js --cert <NEW_IP>
sudo systemctl daemon-reload
sudo systemctl restart meshcentral
```

#### Step 3 — Regenerate the agent installer
**Critical:** the existing `MeshService64.exe` has the OLD IP baked into it.
After MeshCentral restarts on the new IP, it regenerates `signedagents/`:
```bash
cp ~/lab/meshcentral/meshcentral-data/signedagents/MeshService64.exe ~/lab/files/
```

#### Step 4 — Re-point existing agents
If the IP change is permanent and you want already-enrolled devices to find
the new server (run while the old IP still works):
```bash
ansible lab -i ~/lab/hosts.ini -m win_shell \
  -a "& 'C:\\Program Files\\Mesh Agent\\MeshAgent.exe' -meshaction:changeserver -server:wss://<NEW_IP>:443/agent.ashx" \
  --forks 50
```
If the old IP is gone already: push the new agent.exe to each device and
reinstall via the playbook.

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
Ports below 1024 require `setcap` (already done by `01_install_server.sh`).
Above 1024, no setcap needed:
```bash
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

After the port change, regenerate the agent (Phase 7.1 → Step 3).

#### WinRM port (default 5985)

To use HTTPS WinRM (5986) for stronger transport, on each lab device:
```powershell
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=`"$env:COMPUTERNAME`"; CertificateThumbprint=`"$($cert.Thumbprint)`"}"
New-NetFirewallRule -Name 'WinRM-HTTPS' -DisplayName 'WinRM HTTPS' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5986
```

Update [`hosts.ini`](../hosts.ini):
```ini
[lab:vars]
ansible_port=5986
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
ansible_winrm_scheme=https
```
Update the WinRM scan in [`02_add_devices.sh`](../02_add_devices.sh) — change `5985` to `5986`.

### 7.3 Change the lab subnet

#### Step 1 — Update [`config.env`](../config.env)
```bash
export LAB_RANGE_START="<NEW_SUBNET>.1"
export LAB_RANGE_END="<NEW_SUBNET>.254"
```

#### Step 2 — Update [`02_add_devices.sh`](../02_add_devices.sh)
```bash
SUBNET="10.3.5"     # change to your new subnet, e.g. "192.168.1"
```

#### Step 3 — Rebuild `hosts.ini`
Either delete the `[lab]` IP block and let `02_add_devices.sh` repopulate it,
or replace the IPs manually.

### 7.4 Change the lab device admin credentials

Default: `labadmin / 2026`.

#### Step 1 — Update [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1)
Edit the variables at the top:
```powershell
$user = "newadmin"
$pass = ConvertTo-SecureString "newpassword" -AsPlainText -Force
```

#### Step 2 — Update [`hosts.ini`](../hosts.ini)
```ini
[lab:vars]
ansible_user=newadmin
ansible_password=newpassword
```

#### Step 3 — Re-walk all devices with the updated USB
Run the modified `01_Enroll-LabDevice.bat` on each device. The script handles
"user already exists" by updating the password.

#### Step 4 — Update inline inventories
Search for `labadmin` and `2026` in [`02_add_devices.sh`](../02_add_devices.sh),
[`03_check_lab.sh`](../03_check_lab.sh), and [`collect_macs.py`](../collect_macs.py)
— each has an inline credentials block that needs the same values.

### 7.5 Move the server to a new machine

1. On the OLD machine: backup per Phase 6 (`meshcentral-data.tgz`)
2. On the NEW machine: complete Phases 0 + 1.1 + 1.2 (so node, npm,
   meshcentral, systemd unit, certs are all in place — but **stop the
   service immediately after install**)
3. Replace `~/lab/meshcentral/meshcentral-data/` with the contents of the
   tarball
4. Start meshcentral, then 7.1 to fix the IP everywhere
5. Re-copy `signedagents/MeshService64.exe` → `files/`

### 7.6 Quick reference — what to change for each scenario

| Scenario | Files to edit |
|---|---|
| New controller IP | [`config.env`](../config.env), `/etc/systemd/system/meshcentral.service`, regenerate `files/MeshService64.exe` |
| New MeshCentral port | `meshcentral-data/config.json`, firewalld, regenerate `files/MeshService64.exe` |
| New WinRM port | each Windows device locally, [`hosts.ini`](../hosts.ini), [`02_add_devices.sh`](../02_add_devices.sh) |
| New lab subnet | [`config.env`](../config.env), [`02_add_devices.sh`](../02_add_devices.sh), [`hosts.ini`](../hosts.ini) |
| New device admin user | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1), [`hosts.ini`](../hosts.ini), [`02_add_devices.sh`](../02_add_devices.sh), [`03_check_lab.sh`](../03_check_lab.sh), [`collect_macs.py`](../collect_macs.py) |
| Move server to new machine | Backup `meshcentral-data/`, restore on new host, then 7.1 |

### 7.7 Sanity check after any change

```bash
source ~/lab/config.env

# Confirm playbooks still parse
for f in ~/lab/playbooks/*.yml; do
  ansible-playbook --syntax-check -i ~/lab/hosts.ini "$f"
done

# Confirm Ansible can reach lab
ansible lab -i ~/lab/hosts.ini -m win_ping --forks 50

# Confirm MeshCentral is up on the new endpoint
curl -k https://<NEW_IP>:<NEW_PORT>/

# Full health check
~/lab/03_check_lab.sh
```

---

## Appendix — Repo layout reference

```
~/lab/
├── config.env                        # central config (edit ONCE)
├── hosts.ini                         # Ansible inventory (auto-managed)
├── 01_install_server.sh              # MeshCentral bootstrap
├── 02_add_devices.sh                 # discover + enroll
├── 03_check_lab.sh                   # health snapshot
├── 04_serve_files.sh                 # HTTP file server (port 8080)
├── collect_macs.py                   # MAC collection for WoL
├── macs.txt                          # generated by collect_macs.py
├── files/
│   └── MeshService64.exe             # server-keyed agent (copied from signedagents/)
├── playbooks/
│   ├── 01_enroll_with_unlock.yml     # MAIN: handles locked devices
│   ├── 02_verify_agents.yml          # check agent status
│   ├── 03_enroll_meshcentral.yml     # alt: simple enroll, no lockdown
│   └── 04_uninstall_agents.yml       # rollback
├── windows-scripts/                  # → copy to USB
├── meshcentral/                      # MeshCentral install (~580 MB)
│   └── meshcentral-data/
│       ├── config.json               # server settings
│       ├── meshcentral.db            # devices + users
│       └── signedagents/             # server-keyed agent binaries
├── docs/                             # this file + others
└── backups/                          # tarballs from Phase 6
```
