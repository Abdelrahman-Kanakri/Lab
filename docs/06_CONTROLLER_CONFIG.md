# Linux Controller — Configuration Cookbook

Every adjustable setting on the Nobara controller box, with the exact command
to change it and the exact command to verify the change. Each section is
self-contained — find the setting you want to change, copy the commands, done.

For the first-time build of a brand-new controller, follow [`01_IMPLEMENTATION.md`](01_IMPLEMENTATION.md).
This file is for **changes** to an already-running controller.

---

## How this file is organized

1. **Quick map** — which file holds which setting
2. **Per-setting recipes** — change it / verify it
3. **Common scenarios** — multi-setting changes that touch several files (new IP, new lab subnet, rotate admin password, …)

Convention used in commands:
- `<UPPERCASE>` = a placeholder you must replace
- All commands assume you've run `source ~/lab/config.env` first
- Commands that need `sudo` are marked with `sudo`

---

## 1. Quick map: where each setting lives

| Setting | File | Variable / key |
|---|---|---|
| Controller IP | [`config.env`](../config.env) | `CONTROLLER_IP` |
| Controller IP (also) | `/etc/systemd/system/meshcentral.service` | `--cert <IP>` |
| Lab subnet | [`config.env`](../config.env) | `LAB_RANGE_START` / `LAB_RANGE_END` |
| Lab device admin user | [`config.env`](../config.env) | `LAB_ADMIN_USER` |
| Lab device admin password | [`config.env`](../config.env) | `LAB_ADMIN_PASS` |
| Lab device admin (also) | [`windows-scripts/01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) | `$user` / `$pass` |
| MeshCentral admin username | (created in web UI on first launch) | — |
| MeshCentral admin password | reset via CLI | `--resetaccount` |
| MeshCentral session key | `~/lab/meshcentral/meshcentral-data/config.json` | `settings.sessionKey` |
| MeshCentral new account signups | `~/lab/meshcentral/meshcentral-data/config.json` | `domains."".newAccounts` |
| MeshCentral HTTPS port | `~/lab/meshcentral/meshcentral-data/config.json` | `settings.port` |
| MeshCentral HTTP redirect port | `~/lab/meshcentral/meshcentral-data/config.json` | `settings.redirport` |
| MeshCentral branding (title) | `~/lab/meshcentral/meshcentral-data/config.json` | `domains."".title` |
| systemd run-as user | `/etc/systemd/system/meshcentral.service` | `User=` |
| Firewall open ports | firewalld | — |

---

## 2. Per-setting recipes

### 2.1 Controller IP

**What it does:** the IP this Nobara box uses on the lab subnet. The MeshCentral
TLS cert is signed for this IP. Every Windows agent has it baked into its
`MeshService64.exe` binary.

**Default:** `10.3.5.96`
**Where:** `config.env` + systemd unit + agent binary

**Change it (full procedure — touches all three places):**
```bash
NEW_IP="<NEW_IP>"

# 1. Update config.env
sed -i "s|^export CONTROLLER_IP=.*|export CONTROLLER_IP=\"$NEW_IP\"|" ~/lab/config.env

# 2. Update systemd unit
sudo sed -i "s|--cert [0-9.]\+|--cert $NEW_IP|" /etc/systemd/system/meshcentral.service
sudo systemctl daemon-reload
sudo systemctl restart meshcentral

# 3. Wait for MeshCentral to regenerate signedagents/, then re-copy the agent
sleep 5
cp ~/lab/meshcentral/meshcentral-data/signedagents/MeshService64.exe ~/lab/files/

# 4. (optional) Re-point already-enrolled agents — only works while OLD IP still reachable
source ~/lab/config.env
ansible lab -i ~/lab/hosts.ini -m win_shell \
  -a "& 'C:\\Program Files\\Mesh Agent\\MeshAgent.exe' -meshaction:changeserver -server:wss://$NEW_IP:443/agent.ashx" \
  --forks 50
```

**Verify:**
```bash
source ~/lab/config.env
echo "Env: $CONTROLLER_IP"
grep -- "--cert" /etc/systemd/system/meshcentral.service
ss -tlnp | grep -E ':443|:80|:4433'
curl -k -s -o /dev/null -w "Web: HTTP %{http_code}\n" "https://$CONTROLLER_IP"
```

---

### 2.2 Lab subnet

**What it does:** the IP range that `02_add_devices.sh` scans for new devices.

**Default:** `10.3.5.1 – 10.3.5.254`
**Where:** `config.env`

**Change it:**
```bash
NEW_PREFIX="<e.g. 192.168.1>"

sed -i "s|^export LAB_RANGE_START=.*|export LAB_RANGE_START=\"$NEW_PREFIX.1\"|"   ~/lab/config.env
sed -i "s|^export LAB_RANGE_END=.*|export LAB_RANGE_END=\"$NEW_PREFIX.254\"|"      ~/lab/config.env
```

**Verify:**
```bash
source ~/lab/config.env
echo "Range: $LAB_RANGE_START - $LAB_RANGE_END"
# Confirm 02_add_devices.sh derives the right /24:
bash -c 'source ~/lab/config.env; echo "Will scan: ${LAB_RANGE_START%.*}.0/24"'
```

**Side effects:** the existing `~/lab/hosts.ini` still lists the OLD subnet's
IPs. After changing, run `~/lab/02_add_devices.sh` to discover the new devices,
or manually edit `hosts.ini`.

---

### 2.3 Lab device admin credentials

**What it does:** the local Windows admin (`INU/2026` by default) created
on every device by the enrollment USB. Ansible uses these creds to connect.

**Default:** `LAB_ADMIN_USER=INU`, `LAB_ADMIN_PASS=2026`
**Where:** `config.env` + `windows-scripts/01_Enroll-LabDevice.ps1` + `hosts.ini` (auto-regenerated)

**Change the username:**
```bash
NEW_USER="<newadmin>"

# 1. config.env
sed -i "s|^export LAB_ADMIN_USER=.*|export LAB_ADMIN_USER=\"$NEW_USER\"|" ~/lab/config.env

# 2. Enrollment script (used by future USB walks)
sed -i "s|^\$user = \".*\"|\$user = \"$NEW_USER\"|" \
  ~/lab/windows-scripts/01_Enroll-LabDevice.ps1

# 3. Re-generate hosts.ini (run after walking USB to re-enrol with new user)
source ~/lab/config.env
~/lab/02_add_devices.sh
```

**Rotate the password (fleet-wide, no USB walk needed):**
```bash
NEW_PASS="<NewPassword>"

source ~/lab/config.env

# 1. Push new password to every Windows device
ansible lab -i ~/lab/hosts.ini -m win_user \
  -a "name=$LAB_ADMIN_USER password=$NEW_PASS update_password=always password_never_expires=yes groups=Administrators" \
  --forks 50

# 2. Update config.env
sed -i "s|^export LAB_ADMIN_PASS=.*|export LAB_ADMIN_PASS=\"$NEW_PASS\"|" ~/lab/config.env

# 3. Update windows-scripts/ (so future USB enrols use the new password)
sed -i "s|ConvertTo-SecureString \".*\" -AsPlainText|ConvertTo-SecureString \"$NEW_PASS\" -AsPlainText|" \
  ~/lab/windows-scripts/01_Enroll-LabDevice.ps1

# 4. Sync hosts.ini (the script will pick up the new password)
sed -i "s|^ansible_password=.*|ansible_password=$NEW_PASS|" ~/lab/hosts.ini

# 5. Verify
ansible lab -i ~/lab/hosts.ini -m win_ping --forks 50
```

**Verify:**
```bash
source ~/lab/config.env
echo "User: $LAB_ADMIN_USER  /  Pass: $LAB_ADMIN_PASS"
ansible lab -i ~/lab/hosts.ini -m win_ping --forks 50 | grep -c SUCCESS
```

---

### 2.4 MeshCentral admin password (forgot it)

**What it does:** the password for the MeshCentral web UI admin login.

**Where:** stored hashed inside `meshcentral-data/meshcentral.db`. Resettable
via the MeshCentral CLI.

**Change it:**
```bash
NEW_PASS="<NewPassword>"

sudo systemctl stop meshcentral
cd ~/lab/meshcentral
node node_modules/meshcentral --resetaccount admin --pass "$NEW_PASS"
sudo systemctl start meshcentral
```

> Username is whatever you typed when you first created the admin in the web
> UI — usually `admin`. The email on the account is just a profile field, not
> the login.

**Verify:** open `https://$CONTROLLER_IP` and log in.

---

### 2.5 MeshCentral session key

**What it does:** signs browser session cookies. Without a stable value, every
service restart invalidates all logins.

**Default:** placeholder string until set
**Where:** `~/lab/meshcentral/meshcentral-data/config.json` → `settings.sessionKey`

**Change it:**
```bash
NEW_KEY="$(openssl rand -hex 32)"
python3 -c "
import json, pathlib
p = pathlib.Path.home() / 'lab/meshcentral/meshcentral-data/config.json'
c = json.loads(p.read_text())
c['settings']['sessionKey'] = '$NEW_KEY'
p.write_text(json.dumps(c, indent=2))
"
sudo systemctl restart meshcentral
```

**Verify:**
```bash
python3 -c "
import json, pathlib
c = json.loads((pathlib.Path.home() / 'lab/meshcentral/meshcentral-data/config.json').read_text())
print('sessionKey set:', bool(c['settings'].get('sessionKey')))
"
```

> Rotating this **logs out every active session** — only do it intentionally
> (e.g. after a suspected breach).

---

### 2.6 MeshCentral new account signups

**What it does:** if `true`, anyone hitting the web UI can register an account.
After you've claimed admin, set to `false`.

**Default after our setup:** `false`
**Where:** `~/lab/meshcentral/meshcentral-data/config.json` → `domains."".newAccounts`

**Change it:**
```bash
ALLOW="false"   # or "true" temporarily to onboard a teammate

python3 -c "
import json, pathlib
p = pathlib.Path.home() / 'lab/meshcentral/meshcentral-data/config.json'
c = json.loads(p.read_text())
c['domains']['']['newAccounts'] = ($ALLOW == 'true')
p.write_text(json.dumps(c, indent=2))
"
sudo systemctl restart meshcentral
```

**Verify:** in an incognito browser, hit `https://$CONTROLLER_IP/` — the
"Create Account" button should be absent when `false`.

---

### 2.7 MeshCentral HTTPS port

**What it does:** the port the MeshCentral web UI listens on.

**Default:** `443`
**Where:** `~/lab/meshcentral/meshcentral-data/config.json` → `settings.port`
(also `redirport` for the plain-HTTP redirect)

**Change it:**
```bash
NEW_HTTPS=8443
NEW_HTTP=8080

# 1. Edit config
python3 -c "
import json, pathlib
p = pathlib.Path.home() / 'lab/meshcentral/meshcentral-data/config.json'
c = json.loads(p.read_text())
c['settings']['port']      = $NEW_HTTPS
c['settings']['redirport'] = $NEW_HTTP
c['settings']['exactports'] = True
p.write_text(json.dumps(c, indent=2))
"

# 2. Firewall — open new, close old
sudo firewall-cmd --permanent --remove-port=443/tcp
sudo firewall-cmd --permanent --remove-port=80/tcp
sudo firewall-cmd --permanent --add-port=$NEW_HTTPS/tcp
sudo firewall-cmd --permanent --add-port=$NEW_HTTP/tcp
sudo firewall-cmd --reload

# 3. If new port >= 1024 you no longer need cap_net_bind_service:
if [ "$NEW_HTTPS" -ge 1024 ] && [ "$NEW_HTTP" -ge 1024 ]; then
    sudo setcap -r "$(readlink -f $(command -v node))" 2>/dev/null || true
fi

# 4. Restart and re-stage agent (port is baked into the binary)
sudo systemctl restart meshcentral
sleep 5
cp ~/lab/meshcentral/meshcentral-data/signedagents/MeshService64.exe ~/lab/files/
```

**Verify:**
```bash
ss -tlnp | grep -E ":$NEW_HTTPS|:$NEW_HTTP"
curl -k -s -o /dev/null -w "HTTP %{http_code}\n" "https://$CONTROLLER_IP:$NEW_HTTPS"
```

> Already-enrolled agents still talk to the old port. Re-point them with the
> `changeserver` ansible command from §2.1, using `wss://$CONTROLLER_IP:$NEW_HTTPS/agent.ashx`.

---

### 2.8 MeshCentral branding (UI title)

**What it does:** the text shown on the login screen and browser tab.

**Default:** unset (MeshCentral default branding)
**Where:** `~/lab/meshcentral/meshcentral-data/config.json` → `domains."".title`

**Change it:**
```bash
NEW_TITLE="INU Lab"

python3 -c "
import json, pathlib
p = pathlib.Path.home() / 'lab/meshcentral/meshcentral-data/config.json'
c = json.loads(p.read_text())
c['domains']['']['title']  = '$NEW_TITLE'
c['domains']['']['title2'] = 'Controller'
p.write_text(json.dumps(c, indent=2))
"
sudo systemctl restart meshcentral
```

**Verify:** refresh `https://$CONTROLLER_IP` — title shown on the login page.

---

### 2.9 systemd service — run-as user

**What it does:** the OS account that owns the MeshCentral process.

**Default:** `abood`
**Where:** `/etc/systemd/system/meshcentral.service` → `User=`

**Change it:**
```bash
NEW_USER="<linuxuser>"

# 1. Make sure the user exists and owns the data dir
sudo chown -R "$NEW_USER:$NEW_USER" ~/lab/meshcentral/meshcentral-data

# 2. Patch the unit
sudo sed -i "s|^User=.*|User=$NEW_USER|" /etc/systemd/system/meshcentral.service
sudo sed -i "s|WorkingDirectory=/home/[^/]*|WorkingDirectory=/home/$NEW_USER|" /etc/systemd/system/meshcentral.service
sudo sed -i "s|/home/[^/]*/lab|/home/$NEW_USER/lab|g" /etc/systemd/system/meshcentral.service

# 3. Reload + restart
sudo systemctl daemon-reload
sudo systemctl restart meshcentral
```

**Verify:**
```bash
ps -o user= -p "$(systemctl show -p MainPID --value meshcentral)"
```

---

### 2.10 Firewall ports

**What it does:** which TCP ports firewalld allows inbound.

**Default after install:** `80/tcp`, `443/tcp`
**Where:** firewalld

**Inspect:**
```bash
sudo firewall-cmd --list-all
```

**Open a port:**
```bash
sudo firewall-cmd --permanent --add-port=<PORT>/tcp
sudo firewall-cmd --reload
```

**Close a port:**
```bash
sudo firewall-cmd --permanent --remove-port=<PORT>/tcp
sudo firewall-cmd --reload
```

**Temporary (only until reboot):**
```bash
sudo firewall-cmd --add-port=8080/tcp   # used while 04_serve_files.sh is running
```

---

### 2.11 Ansible — install / upgrade / config

**What it does:** controls Ansible (installed via `pip3 install --user`).

**Default location:** `~/.local/bin/ansible*`
**Where:** PATH set in `config.env` and `~/.bashrc`

**Upgrade Ansible:**
```bash
pip3 install --user --upgrade ansible pywinrm
ansible-galaxy collection install --upgrade ansible.windows community.windows
```

**Set defaults so commands are shorter (optional):**
```bash
cat > ~/.ansible.cfg <<'EOF'
[defaults]
inventory = /home/abood/lab/hosts.ini
forks     = 50
host_key_checking = False
stdout_callback = yaml

[winrm]
operation_timeout_sec = 60
read_timeout_sec      = 70
EOF
```

After this, `ansible lab -m win_ping` works without `-i ~/lab/hosts.ini --forks 50`.

**Verify:**
```bash
which ansible && ansible --version | head -1
python3 -c "import winrm; print('pywinrm OK')"
ansible-galaxy collection list ansible.windows | tail -3
```

---

### 2.12 Backup the controller

**What it does:** snapshots `meshcentral-data/` (devices DB, users, certs).

**Where:** `~/lab/backups/`

**Manual backup:**
```bash
sudo systemctl stop meshcentral
mkdir -p ~/lab/backups
tar czf ~/lab/backups/meshcentral-$(date +%F-%H%M).tgz \
  -C ~/lab/meshcentral meshcentral-data
sudo systemctl start meshcentral
ls -lh ~/lab/backups/
```

**Schedule weekly (Sunday 03:00):**
```bash
crontab -e
# Add this line:
# 0 3 * * 0 systemctl stop meshcentral && tar czf /home/abood/lab/backups/meshcentral-$(date +\%F).tgz -C /home/abood/lab/meshcentral meshcentral-data && systemctl start meshcentral
```
(Cron runs as your user; the `systemctl` calls inside need the user to have
NOPASSWD sudo for those commands, or run the cron under root.)

**Restore on a new machine:** complete Phases 0–1 of `01_IMPLEMENTATION.md`,
**stop the service**, replace `meshcentral-data/` with the tarball contents,
start the service, then update IP per §2.1 if it changed.

---

## 3. Common scenarios (multi-setting changes)

### Scenario A: deploy this whole stack to a *new* lab on a *new* Nobara box

```bash
# On the NEW box (with ~/lab/ copied or git-cloned over):
nano ~/lab/config.env
# → set CONTROLLER_IP, LAB_RANGE_START/END to match the new lab

source ~/lab/config.env
~/lab/01_install_server.sh
# → opens MeshCentral on https://$CONTROLLER_IP

# In a browser: claim the admin account, create the "Lab" device group.

# Harden config.json (see §2.5 + §2.6) — set sessionKey + newAccounts:false.

# Stage the server-keyed agent
cp ~/lab/meshcentral/meshcentral-data/signedagents/MeshService64.exe ~/lab/files/

# Walk to each Windows device with USB → run 01_Enroll-LabDevice.bat
# Then back on the controller:
~/lab/02_add_devices.sh
~/lab/03_check_lab.sh
python3 ~/lab/collect_macs.py
```

That's the full new-lab path. Each lab gets its own `config.env` and its own
isolated MeshCentral; no two labs share state.

---

### Scenario B: the controller box's IP changed (DHCP rotation, network change)

Run the full procedure in §2.1. Order matters: update `config.env` → update
systemd unit → restart → re-stage agent → (optional) re-point existing agents.

---

### Scenario C: rotate the lab admin password before exams

Run the full procedure in §2.3 → "Rotate the password (fleet-wide)". One block.

---

### Scenario D: move the whole lab to a new IP subnet

```bash
NEW_PREFIX="192.168.1"

# 1. Update lab subnet bounds
sed -i "s|^export LAB_RANGE_START=.*|export LAB_RANGE_START=\"$NEW_PREFIX.1\"|"   ~/lab/config.env
sed -i "s|^export LAB_RANGE_END=.*|export LAB_RANGE_END=\"$NEW_PREFIX.254\"|"      ~/lab/config.env

# 2. If the controller's own IP also moved, run §2.1 first

# 3. Empty hosts.ini and re-discover everything
> ~/lab/hosts.ini
~/lab/02_add_devices.sh

# 4. Verify
~/lab/03_check_lab.sh
```

---

### Scenario E: hand the lab off to a different Linux user account

Run the full procedure in §2.9. Don't forget the `chown -R` on
`meshcentral-data/`.

---

## 4. Health-check ladder (run after any change)

```bash
source ~/lab/config.env

# 1. config loaded
echo "IP=$CONTROLLER_IP  RANGE=$LAB_RANGE_START..$LAB_RANGE_END  USER=$LAB_ADMIN_USER"

# 2. systemd
systemctl is-active meshcentral && systemctl is-enabled meshcentral

# 3. ports
ss -tlnp | grep -E ':443|:80|:4433'

# 4. web UI
curl -k -s -o /dev/null -w "Web UI: HTTP %{http_code}\n" "https://$CONTROLLER_IP"

# 5. config.json hardened
python3 -c "
import json, pathlib
c = json.loads((pathlib.Path.home()/'lab/meshcentral/meshcentral-data/config.json').read_text())
print('sessionKey:', 'set' if c['settings'].get('sessionKey') else 'MISSING')
print('newAccounts:', c['domains'][''].get('newAccounts', 'unset'))
"

# 6. Ansible reachable
ansible --version | head -1

# 7. Lab health
~/lab/03_check_lab.sh
```

If any step fails, fix it before moving on. Each step maps cleanly back to one
recipe in §2.

---

## 5. Don'ts

- Don't `restart meshcentral` without first validating `config.json`:
  `python3 -m json.tool < ~/lab/meshcentral/meshcentral-data/config.json`
- Don't delete `meshcentral-data/` — it holds the cert authority. Losing it
  means every enrolled agent has to be reinstalled with a fresh binary.
- Don't run MeshCentral as root. The `setcap` on the node binary is what lets
  user `abood` bind 80/443.
- Don't expose this server to the public internet without a real cert
  (Let's Encrypt) and a reverse proxy.
- Don't edit the systemd unit file without `daemon-reload` after.
