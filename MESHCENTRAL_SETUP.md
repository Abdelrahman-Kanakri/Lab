# MeshCentral Lab Deployment — Step-by-Step

Controller: Nobara Linux workstation (admin)
Targets: 50 Windows lab devices (192.168.1.101–192.168.1.150) as managed agents

Replace every `<CONTROLLER_IP>` with your Nobara box's lab-network IP.
Get it with: `ip -4 addr show | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+'`

---

## PART 1 — Admin Controller Setup (Nobara)

### 1.1 Install prerequisites

```bash
sudo dnf install -y nodejs npm
node --version   # expect v18+
```

### 1.2 Install MeshCentral

```bash
mkdir -p ~/lab/meshcentral && cd ~/lab/meshcentral
npm install meshcentral
```

### 1.3 Grant Node permission to bind ports 80/443

```bash
sudo setcap 'cap_net_bind_service=+ep' $(which node)
```

Without this, MeshCentral falls back to ports 1024/1025 and agents can't auto-connect on standard ports.

### 1.4 First-run cert generation

```bash
cd ~/lab/meshcentral
node node_modules/meshcentral
```

Wait for the line `Server has no users, next new account will be site administrator.`
Then press `Ctrl+C`.

### 1.5 Relaunch bound to your controller IP

```bash
node node_modules/meshcentral --cert <CONTROLLER_IP>
```

Expect: `MeshCentral HTTPS server running on port 443.`

### 1.6 Claim the admin account

From your Nobara browser visit: `https://<CONTROLLER_IP>`

- Accept the self-signed cert warning
- Click **Create Account**
- The first account created becomes **site administrator** — use a strong password
- Enable 2FA under **My Account → Security** after login

Once confirmed working, stop the server with `Ctrl+C` — we'll move it to systemd next.

### 1.7 Make it a persistent systemd service

Create `/etc/systemd/system/meshcentral.service`:

```bash
sudo tee /etc/systemd/system/meshcentral.service > /dev/null <<'EOF'
[Unit]
Description=MeshCentral Server
After=network.target

[Service]
Type=simple
User=abood
WorkingDirectory=/home/abood/lab/meshcentral
ExecStart=/usr/bin/node /home/abood/lab/meshcentral/node_modules/meshcentral
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now meshcentral
sudo systemctl status meshcentral
```

Tail logs:

```bash
journalctl -u meshcentral -f
```

### 1.8 Open firewall ports (if firewalld is active)

```bash
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --reload
```

### 1.9 Create a device group for the lab

In the web UI:

- **My Devices → Add Device Group**
- Name: `Lab`
- Type: **Manage using a software agent**
- Save

---

## PART 2 — Lab Device Enrollment (Windows agents)

### 2.1 Download the Windows agent MSI

In the web UI:

- Open the `Lab` group
- Click **Add Agent**
- Select **Windows x64 (MSI)**
- Save the file as `~/lab/files/meshagent.msi`

(The MSI is pre-keyed to your server — don't rename it.)

### 2.2 Verify connectivity to all targets

```bash
ansible lab -m win_ping
```

Any host that fails here will not receive the agent. Fix those first.

### 2.3 Push the MSI to every lab device

```bash
ansible lab -m win_copy \
  -a "src=/home/abood/lab/files/meshagent.msi dest=C:\\Windows\\Temp\\meshagent.msi" \
  --forks 50
```

### 2.4 Install silently on every device

```bash
ansible lab -m win_command \
  -a "msiexec /i C:\\Windows\\Temp\\meshagent.msi /quiet /norestart" \
  --forks 50
```

### 2.5 Verify agent service is running

```bash
ansible lab -m win_shell \
  -a "Get-Service Mesh* | Select Name,Status" \
  --forks 50
```

Every host should return `Mesh Agent   Running`.

### 2.6 Confirm in the web UI

Refresh the `Lab` device group — all 50 devices should appear online (green dot) within 60 seconds.

### 2.7 (Optional) Save as a reusable playbook

Create `~/lab/playbooks/enroll_meshcentral.yml`:

```yaml
---
- name: Enroll lab devices in MeshCentral
  hosts: lab
  gather_facts: no
  tasks:
    - name: Copy MeshAgent MSI
      win_copy:
        src: /home/abood/lab/files/meshagent.msi
        dest: C:\Windows\Temp\meshagent.msi

    - name: Install MeshAgent silently
      win_command: msiexec /i C:\Windows\Temp\meshagent.msi /quiet /norestart

    - name: Verify service running
      win_shell: Get-Service "Mesh Agent" | Select-Object -ExpandProperty Status
      register: svc
      changed_when: false

    - name: Show status
      debug:
        var: svc.stdout_lines
```

Run with: `ansible-playbook ~/lab/playbooks/enroll_meshcentral.yml --forks 50`

---

## PART 3 — Operations Reference (what you can do now)

### Via Web UI (per-device or multi-select)

| Task | Location |
|---|---|
| Shutdown / Restart / Sleep / Wake | Select device(s) → **Power** |
| Wake-on-LAN | Right-click offline device → **Wake-up** |
| Remote desktop | Device → **Desktop** tab |
| PowerShell / CMD | Device → **Terminal** tab |
| Upload/download files | Device → **Files** tab |
| Run script on many devices | Group → **Run Command** |
| Live process list | Device → **Processes** |

### Via `meshctrl` CLI (scriptable)

Install:

```bash
cd ~/lab/meshcentral
npm install meshcommander
```

Example commands (replace `<CONTROLLER_IP>`, `<ADMIN_USER>`, `<DEVICE_ID>`):

```bash
# List all devices
node node_modules/meshcentral/meshctrl.js \
  --url wss://<CONTROLLER_IP> --loginuser <ADMIN_USER> ListDevices

# Shutdown one device
node node_modules/meshcentral/meshctrl.js \
  --url wss://<CONTROLLER_IP> --loginuser <ADMIN_USER> \
  Shutdown --id <DEVICE_ID>

# Run a PowerShell command
node node_modules/meshcentral/meshctrl.js \
  --url wss://<CONTROLLER_IP> --loginuser <ADMIN_USER> \
  RunCommand --id <DEVICE_ID> --run "Get-Process chrome"

# Wake a device
node node_modules/meshcentral/meshctrl.js \
  --url wss://<CONTROLLER_IP> --loginuser <ADMIN_USER> \
  Wake --id <DEVICE_ID>
```

### Coexistence with Ansible

Keep both. Rule of thumb:

- **Ansible** — scripted, repeatable batch jobs; CI-style tasks; anything in a playbook
- **MeshCentral** — interactive work, file drops, troubleshooting a single flaky device, eyes-on-screen, remote desktop

---

## PART 4 — Troubleshooting

### Agents don't appear after install
```bash
ansible lab -m win_shell -a "Get-Service MeshAgent | Select Status"
ansible lab -m win_shell -a "Test-NetConnection <CONTROLLER_IP> -Port 443"
```
Firewall/antivirus on the Windows host is the usual culprit.

### Server won't bind to 443 after reboot
The `setcap` from step 1.3 persists, but if Node is updated via dnf it resets. Re-run:
```bash
sudo setcap 'cap_net_bind_service=+ep' $(which node)
sudo systemctl restart meshcentral
```

### Reset a forgotten admin password
```bash
sudo systemctl stop meshcentral
cd ~/lab/meshcentral
node node_modules/meshcentral --resetaccount <ADMIN_USER> --pass <NEW_PASS>
sudo systemctl start meshcentral
```

### Backup the server (config + device DB)
```bash
sudo systemctl stop meshcentral
tar czf ~/lab/backups/meshcentral-$(date +%F).tgz -C ~/lab/meshcentral meshcentral-data
sudo systemctl start meshcentral
```

### Uninstall agent from a lab device
```bash
ansible lab -m win_shell \
  -a "& 'C:\\Program Files\\Mesh Agent\\MeshAgent.exe' -fulluninstall"
```

---

## PART 5 — Rollout Checklist

- [ ] 1.1–1.3 Node + MeshCentral installed, port cap granted
- [ ] 1.4–1.6 First-run cert generation + admin account claimed
- [ ] 1.7–1.8 systemd service running, firewall open
- [ ] 1.9 `Lab` device group created
- [ ] 2.1 Agent MSI downloaded to `~/lab/files/`
- [ ] 2.2 `win_ping` passes on all 50 devices
- [ ] 2.3–2.4 MSI pushed and installed
- [ ] 2.5–2.6 All 50 agents online in web UI
- [ ] 2.7 Playbook saved for future re-enrollments
- [ ] 2FA enabled on admin account
- [ ] Backup schedule decided
