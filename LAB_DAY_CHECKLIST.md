# Lab Day Runbook — MeshCentral Rollout

Print this or keep it open on a second screen. Every command is copy-paste ready.

---

## 0. Before you leave for the lab

- [ ] Laptop charged, USB Digispark handy
- [ ] Confirm you have Administrator password for Windows devices
- [ ] Confirm internet works on Nobara at the university (Part 1 needs ~150 MB npm deps — skip if already done)

### 0a. Install prerequisites — DO THIS TONIGHT AT HOME

The university network may block `dnf` or `pip`. Install while you still have reliable internet:

```bash
sudo dnf install -y ansible nmap wakeonlan python3-pip python3-pywinrm
```

If `python3-pywinrm` is missing from dnf, use pip:

```bash
sudo dnf install -y ansible nmap wakeonlan
pip install --user pywinrm
```

Verify all tools are present:

```bash
ansible --version | head -1
which ansible-playbook nmap wakeonlan python3
python3 -c "import winrm; print('pywinrm OK')"
```

- [ ] `ansible --version` prints a version
- [ ] `which` returns paths for ansible-playbook, nmap, wakeonlan
- [ ] `pywinrm OK` prints successfully

### 0b. Syntax-check the playbooks (tonight)

```bash
for f in ~/lab/playbooks/*.yml; do
    ansible-playbook --syntax-check -i ~/lab/hosts.ini "$f"
done
```

- [ ] All three playbooks report `playbook: ...yml` with no errors

### 0c. (Recommended) Do Part 1 at home, download the MSI, then shut down

Benefits: MeshCentral server + admin account + MSI all ready before you arrive. The lab-day work becomes only Parts 4–7.

```bash
# At home, on any network
~/lab/install_server.sh
# Open https://<CONTROLLER_IP> → create admin → 2FA → create "Lab" group
# → Add Agent → Windows x64 MSI → save to ~/lab/files/meshagent.msi
ls -lh ~/lab/files/meshagent.msi    # should show the MSI
```

Note: the server is bound to your **home** IP tonight. Tomorrow at the lab you'll need to update `CONTROLLER_IP` in `~/lab/config.env`, re-run the systemd unit update, and restart the service. Or skip this step and do Part 1 fresh at the lab.

---

## 1. On arrival — set your controller IP (ONCE)

Find your IP on the lab subnet:

```bash
ip -4 addr show | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+'
```

Edit `~/lab/config.env` and replace the placeholder:

```bash
nano ~/lab/config.env        # set CONTROLLER_IP
source ~/lab/config.env
echo $CONTROLLER_IP           # verify
```

Also update `~/lab/scripts/bootstrap_v2.ps1` line 22 with the same IP if you'll re-bootstrap any device.

Edit `~/lab/hosts.ini` and set `ansible_password` to the real Administrator password:

```bash
nano ~/lab/hosts.ini
```

---

## 2. Install MeshCentral server (SKIP if already done)

```bash
chmod +x ~/lab/install_server.sh ~/lab/serve_files.sh
~/lab/install_server.sh
```

Wait for "MeshCentral should now be running." Open browser:

```
https://<CONTROLLER_IP>
```

- [ ] Accept cert warning
- [ ] Create admin account (first one = site admin)
- [ ] Enable 2FA (My Account → Security)
- [ ] Create device group named `Lab` (My Devices → Add Device Group → Manage using a software agent)

---

## 3. Download the agent MSI

In MeshCentral web UI:

1. Open the `Lab` device group
2. Click **Add Agent**
3. Select **Windows x64 (MSI)**
4. Save to `~/lab/files/meshagent.msi`

Verify:

```bash
ls -lh ~/lab/files/meshagent.msi
```

---

## 4. Pre-flight: confirm Ansible can reach every device

```bash
cd ~/lab
ansible lab -i hosts.ini -m win_ping --forks 50
```

- [ ] All 50 hosts reply `pong`. If any fail → note which ones, they need Digispark re-bootstrap.

---

## 4a. Confirm admin username on the devices (one physical check)

Walk to any one lab device and run locally:

```powershell
Get-LocalGroupMember -Group "Administrators"
```

- [ ] The output names a local account (e.g., `Administrator`, `LabAdmin`)
- [ ] If it's NOT `Administrator`, edit `~/lab/hosts.ini` and change `ansible_user` to the correct name
- [ ] Also confirm `Get-LocalUser | ? Enabled | select Name` shows that account as enabled

Then from your Nobara box:

```bash
ansible lab -i ~/lab/hosts.ini -m win_ping --limit 192.168.1.101 --forks 1
```

- [ ] Returns `pong` — auth with `Administrator` / `2026` works

If it fails on a single host but others work, that one device is the anomaly; skip it.

---

## 5. Enroll all 50 devices (Unlock → Install → Re-Lock)

All devices are currently locked, so MSI installs are blocked. This playbook
temporarily unlocks each device, installs the MeshAgent, then re-locks.

```bash
ansible-playbook -i ~/lab/hosts.ini ~/lab/playbooks/enroll_with_unlock.yml --forks 50
```

Expected: ~4-6 minutes (unlock + MSI install + re-lock per device, in parallel).
You should see `MeshAgent Running` for each host at the end.

If any host fails mid-flight and is left unlocked:

```bash
# Re-lock one or more specific hosts
ansible-playbook -i ~/lab/hosts.ini ~/lab/playbooks/enroll_with_unlock.yml \
  --limit 192.168.1.XXX --tags relock
```

---

## 6. Verify enrollment

```bash
ansible-playbook -i ~/lab/hosts.ini ~/lab/playbooks/verify_agents.yml --forks 50
```

Then in the MeshCentral web UI, refresh the `Lab` group:

- [ ] All 50 devices show up with green (online) status

---

## 7. Smoke test operations

Pick one device in the web UI and test:

- [ ] **Desktop** tab → remote view works
- [ ] **Terminal** tab → run `whoami` → returns `administrator`
- [ ] **Files** tab → browse C:\ drive
- [ ] **Power** menu → "Wake" works on an offline device (requires BIOS WoL)

Then test on the whole group:

- [ ] Select all 50 → **Run Command** → `Get-Date` → all return a timestamp

---

## 8. Done — persistence check

Reboot your Nobara box to confirm MeshCentral auto-starts:

```bash
sudo reboot
```

After reboot:

```bash
sudo systemctl status meshcentral
```

Should be `active (running)`. Open `https://<CONTROLLER_IP>` — agents should reconnect automatically.

---

## Common commands (keep handy)

```bash
# Start file server (for manual pushes or new-device bootstrap)
~/lab/serve_files.sh

# Shutdown all lab devices
ansible lab -i ~/lab/hosts.ini -m win_command -a "shutdown /s /t 0" --forks 50

# Wake all devices
cat ~/lab/macs.txt | xargs -I{} wakeonlan {}

# Fresh MAC scan (update macs.txt)
sudo nmap -sn 192.168.1.101-150 -oG - | awk '/Up/{print $2}' \
  | xargs -I{} arp -n {} | awk '/ether/{print $3}' > ~/lab/macs.txt

# MeshCentral logs
journalctl -u meshcentral -f

# Restart MeshCentral
sudo systemctl restart meshcentral
```

---

## Rollback (only if something goes wrong)

```bash
# Remove agents from all devices
ansible-playbook -i ~/lab/hosts.ini ~/lab/playbooks/uninstall_agents.yml --forks 50

# Stop and disable server
sudo systemctl disable --now meshcentral
```

Your Ansible/WinRM setup is unaffected — this only removes MeshCentral, not the Digispark bootstrap work.

---

## If something fails — quick diagnosis

| Symptom | Check |
|---|---|
| `win_ping` fails on a host | Digispark bootstrap didn't run OR firewall blocked 5985. Re-run Digispark. |
| MSI install succeeds but agent doesn't appear in UI | `ansible <host> -m win_shell -a "Test-NetConnection <CONTROLLER_IP> -Port 443"` |
| Server won't start after reboot | `journalctl -u meshcentral -n 50` — usually the `setcap` reset after a Node update. Re-run `sudo setcap 'cap_net_bind_service=+ep' $(which node)` |
| Forgot admin password | `cd ~/lab/meshcentral && node node_modules/meshcentral --resetaccount <USER> --pass <NEW>` |
