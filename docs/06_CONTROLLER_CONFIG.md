# Linux Controller Configuration Reference

Everything that defines the **Nobara controller box** itself: what it runs,
where the settings live, and how to change each one cleanly.

This is the controller-side equivalent of [`05_DEVICE_CONFIG.md`](05_DEVICE_CONFIG.md).
Use this when something about the **controller** needs to change (its IP, the
MeshCentral port, where files live, who owns the systemd service, etc.).

---

## 1. Canonical controller state

After a clean install, the Nobara box looks like this:

| Area | What | Default value | Set by |
|---|---|---|---|
| **Identity** | Controller IP on lab subnet | `10.3.5.96` | DHCP / static config + [`config.env`](../config.env) |
| **Identity** | Controller hostname | `ABK` (any) | OS install |
| **Identity** | User running everything | `abood` | OS install |
| **MeshCentral** | Install dir | `~/lab/meshcentral/` | [`01_install_server.sh`](../01_install_server.sh) |
| **MeshCentral** | systemd unit | `/etc/systemd/system/meshcentral.service` | [`01_install_server.sh`](../01_install_server.sh) |
| **MeshCentral** | Service runs as user | `abood` | systemd unit |
| **MeshCentral** | HTTPS port | `443` | `meshcentral-data/config.json` (default) |
| **MeshCentral** | HTTP redirect port | `80` | `meshcentral-data/config.json` (default) |
| **MeshCentral** | Agent (MPS) port | `4433` | `meshcentral-data/config.json` (default) |
| **MeshCentral** | Cert binding (CN) | `10.3.5.96` | systemd `ExecStart=... --cert <IP>` |
| **MeshCentral** | sessionKey | random 64-char hex | `meshcentral-data/config.json` |
| **MeshCentral** | New account signups | `false` (disabled) | `meshcentral-data/config.json` |
| **MeshCentral** | Admin login | `admin` (username) | First account created in web UI |
| **Ansible** | Install location | `~/.local/bin/ansible*` | `pip3 install --user ansible` |
| **Ansible** | Windows collection | installed | `ansible-galaxy collection install ansible.windows` |
| **Ansible** | WinRM library | `pywinrm` (~/.local) | `pip3 install --user pywinrm` |
| **Ansible** | Inventory | `~/lab/hosts.ini` | auto-managed by `02_add_devices.sh` |
| **Network** | Firewall — incoming | TCP `80`, `443` open (firewalld) | [`01_install_server.sh`](../01_install_server.sh) |
| **Network** | File-share HTTP | TCP `8080` (only when [`04_serve_files.sh`](../04_serve_files.sh) is running) | manual |
| **PATH** | `~/.local/bin` in PATH | yes | `~/.bashrc` + `config.env` |
| **Backup** | Backup dir | `~/lab/backups/` | manual / cron |

---

## 2. Where the config lives — file map

| File | Purpose | Edit it when |
|---|---|---|
| [`~/lab/config.env`](../config.env) | Single source of truth for paths and the controller IP. Sourced by every shell script. | Controller IP changes, paths move, you add new env-vars to share across scripts |
| `/etc/systemd/system/meshcentral.service` | systemd unit that auto-starts MeshCentral on boot | IP changes (the `--cert` arg), node binary path changes, you want to run as a different user |
| `~/lab/meshcentral/meshcentral-data/config.json` | MeshCentral server settings: ports, sessionKey, signups, branding, SMTP, LDAP, etc. | You want to change a MeshCentral feature |
| `~/lab/hosts.ini` | Ansible inventory + connection variables (user, password, transport) | Lab admin creds change, new device added |
| `~/.bashrc` | Adds `~/.local/bin` to interactive shell PATH | One-time during install |
| `firewalld` rules | Inbound port permissions | You change MeshCentral ports |
| `~/lab/meshcentral/meshcentral-data/signedagents/` | Server-keyed Windows agent binaries (auto-regenerated) | After IP change — re-copy `MeshService64.exe` to `~/lab/files/` |

---

## 3. `config.env` — variable reference

```bash
export CONTROLLER_IP="10.3.5.96"
export MESH_ADMIN="admin"
export LAB_RANGE_START="10.3.5.1"
export LAB_RANGE_END="10.3.5.254"
export PATH="$HOME/.local/bin:$PATH"
export LAB_DIR="$HOME/lab"
export LAB_FILES="$LAB_DIR/files"
export LAB_PLAYBOOKS="$LAB_DIR/playbooks"
export MESH_DIR="$LAB_DIR/meshcentral"
```

| Variable | What | Read by | Notes |
|---|---|---|---|
| `CONTROLLER_IP` | The Nobara box's IP on the lab subnet | [`01_install_server.sh`](../01_install_server.sh), [`02_add_devices.sh`](../02_add_devices.sh), [`04_serve_files.sh`](../04_serve_files.sh) | If you change this you also need to update `/etc/systemd/system/meshcentral.service` (see §4) and re-copy the agent (see §6) |
| `MESH_ADMIN` | Intended MeshCentral admin username | (currently unused — informational) | Documents intent. The actual username is set when you claim the admin in the web UI |
| `LAB_RANGE_START` / `LAB_RANGE_END` | Documentation of the lab subnet bounds | (currently unused by scripts — see §10) | The scan in [`02_add_devices.sh`](../02_add_devices.sh) hardcodes its own `SUBNET=` — keep these in sync |
| `PATH` | Prepends `~/.local/bin` so scripts find `ansible` | every script that calls `ansible*` | Required because ansible is installed via `pip --user`, not dnf |
| `LAB_DIR` | Root of the lab tree | many scripts | Change only if you move the whole repo |
| `LAB_FILES` | Where binaries to push to devices live | [`04_serve_files.sh`](../04_serve_files.sh) | Default `~/lab/files/` |
| `LAB_PLAYBOOKS` | Where playbooks live | (currently unused by scripts) | Documents intent |
| `MESH_DIR` | MeshCentral install root | [`01_install_server.sh`](../01_install_server.sh) | Default `~/lab/meshcentral/` |

### How to apply a change to `config.env`

```bash
nano ~/lab/config.env
source ~/lab/config.env       # reload in the current shell
```

Anything started **after** the `source` sees the new values. Long-running
processes (like a running MeshCentral) do not re-read it — they need a restart
(see §4).

---

## 4. systemd unit — `meshcentral.service`

Location: `/etc/systemd/system/meshcentral.service`

```ini
[Unit]
Description=MeshCentral Server
After=network.target

[Service]
Type=simple
User=abood
WorkingDirectory=/home/abood/lab/meshcentral
ExecStart=/usr/bin/node /home/abood/lab/meshcentral/node_modules/meshcentral/meshcentral.js --cert 10.3.5.96
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

| Line | Purpose | When to change |
|---|---|---|
| `User=abood` | OS user that owns the MeshCentral process | If you switch the lab admin to a different OS account |
| `WorkingDirectory=` | Where MeshCentral runs from (must contain `node_modules/meshcentral`) | If you move `~/lab/meshcentral/` |
| `ExecStart=` `--cert 10.3.5.96` | Tells MeshCentral which IP to bind its TLS cert to | **Always** when controller IP changes |
| `ExecStart=` path | Absolute path to node binary | If you switch node versions or install path |
| `Restart=always` | Auto-restart on crash | rarely changed |

### Apply a change
```bash
sudo nano /etc/systemd/system/meshcentral.service
sudo systemctl daemon-reload
sudo systemctl restart meshcentral
sudo systemctl status meshcentral --no-pager | head -10
```

### Verify
```bash
systemctl is-enabled meshcentral     # → enabled
systemctl is-active meshcentral      # → active
ss -tlnp | grep -E ':443|:80|:4433'  # all three should be listening
```

### Logs
```bash
journalctl -u meshcentral -f         # follow live
journalctl -u meshcentral -n 100     # last 100 lines
journalctl -u meshcentral --since "1 hour ago"
```

---

## 5. MeshCentral `config.json`

Path: `~/lab/meshcentral/meshcentral-data/config.json`

This is the MeshCentral application config, separate from `config.env` (which
is for shell scripts).

### The underscore convention

A key prefixed with `_` is **disabled** (parser ignores it). This is how
MeshCentral ships sample values you can opt into — remove the leading `_` to
activate.

Example — these two lines are NOT the same:
```json
"_sessionKey": "MyReallySecretPassword1"   // ignored, MeshCentral picks a random one each restart
"sessionKey":  "MyReallySecretPassword1"   // active, used as the session signing key
```

### Settings to know about

```json
{
  "settings": {
    "sessionKey": "<openssl rand -hex 32>",
    "port": 443,
    "redirport": 80,
    "agentport": 4433,
    "exactports": true,
    "_LANonly": true,
    "_WANonly": true,
    "_minify": true
  },
  "domains": {
    "": {
      "title": "INU Lab",
      "title2": "Controller",
      "newAccounts": false,
      "userNameIsEmail": false,
      "_minify": true
    }
  },
  "_letsencrypt": { "...": "..." },
  "_smtp": { "...": "..." }
}
```

| Setting | Effect | When to change |
|---|---|---|
| `settings.sessionKey` | Signs browser session cookies. Without it, restarts log everyone out | Set ONCE during install. Rotating it logs everyone out |
| `settings.port` | HTTPS port | Move off 443 (e.g. to 8443) — also requires firewall + agent regen |
| `settings.redirport` | Plain-HTTP → HTTPS redirect port | Match your `port` change (e.g. 8080) |
| `settings.agentport` | Port the MeshAgent connects on | Default reuses the HTTPS port; split for traffic separation |
| `settings.exactports` | Refuse to silently fall back to higher ports | Set `true` if you want to fail loudly when bind fails |
| `settings.LANonly` | Bind only to LAN interfaces | Set `true` if controller is on multiple networks |
| `domains."".title` / `title2` | Browser tab + login screen branding | Cosmetic |
| `domains."".newAccounts` | Allow strangers to create accounts via the web UI | **Always set to `false` after you claim admin** |
| `domains."".userNameIsEmail` | Username is the email address | `false` keeps short usernames like `admin` |
| `letsencrypt.*` | Real cert from Let's Encrypt instead of self-signed | Only if controller has a public hostname |
| `smtp.*` | Outbound email for password resets / 2FA | If you want self-service password reset |

Full schema: `~/lab/meshcentral/node_modules/meshcentral/sample-config-advanced.json`

### Apply a change
```bash
nano ~/lab/meshcentral/meshcentral-data/config.json
# Validate that JSON is still parseable
python3 -m json.tool < ~/lab/meshcentral/meshcentral-data/config.json > /dev/null && echo "JSON OK"
sudo systemctl restart meshcentral
journalctl -u meshcentral -n 30 --no-pager   # confirm clean startup
```

### Verify
```bash
# Hit the server and confirm it answers
curl -k https://localhost/ -o /dev/null -s -w "HTTP %{http_code}\n"

# If you changed ports
ss -tlnp | grep <NEW_PORT>
```

---

## 6. Changing the controller IP — full procedure

The IP appears in **four** places — all four must agree or things break.

```bash
NEW_IP=10.3.5.50

# 1. Update central config
sed -i "s|^export CONTROLLER_IP=.*|export CONTROLLER_IP=\"$NEW_IP\"|" ~/lab/config.env

# 2. Update systemd unit
sudo sed -i "s|--cert [0-9.]*|--cert $NEW_IP|" /etc/systemd/system/meshcentral.service
sudo systemctl daemon-reload
sudo systemctl restart meshcentral

# 3. Re-copy the agent — MeshCentral regenerates signedagents/ on startup
sleep 5
cp ~/lab/meshcentral/meshcentral-data/signedagents/MeshService64.exe ~/lab/files/

# 4. (optional) Re-point already-enrolled agents (must be done while OLD IP still works)
source ~/lab/config.env
ansible lab -i ~/lab/hosts.ini -m win_shell \
  -a "& 'C:\\Program Files\\Mesh Agent\\MeshAgent.exe' -meshaction:changeserver -server:wss://$NEW_IP:443/agent.ashx" \
  --forks 50
```

After this:
- Web UI is at `https://$NEW_IP`
- New device enrollments use the regenerated `~/lab/files/MeshService64.exe`
- Existing devices were re-pointed in step 4

---

## 7. Changing MeshCentral ports

```bash
NEW_HTTPS=8443
NEW_HTTP=8080

# 1. Edit MeshCentral config
nano ~/lab/meshcentral/meshcentral-data/config.json
# Inside "settings": "port": 8443, "redirport": 8080, "exactports": true

# 2. Firewall
sudo firewall-cmd --permanent --remove-port=443/tcp
sudo firewall-cmd --permanent --remove-port=80/tcp
sudo firewall-cmd --permanent --add-port=$NEW_HTTPS/tcp
sudo firewall-cmd --permanent --add-port=$NEW_HTTP/tcp
sudo firewall-cmd --reload

# 3. Below 1024 needs setcap; above 1024 doesn't
if [ "$NEW_HTTPS" -ge 1024 ]; then
    sudo setcap -r "$(readlink -f $(command -v node))" 2>/dev/null
fi

# 4. Restart + regenerate agents (port is baked into the binary)
sudo systemctl restart meshcentral
sleep 5
cp ~/lab/meshcentral/meshcentral-data/signedagents/MeshService64.exe ~/lab/files/
```

Already-enrolled agents need re-pointing (similar to §6 step 4) with the new
port in the URL.

---

## 8. Ansible setup

`ansible` lives at `~/.local/bin/ansible` — installed via `pip3 install --user`,
not `dnf`. Reasons: Nobara's dnf repo doesn't always carry a recent ansible,
and pip-user keeps it out of system locations.

### Verify
```bash
which ansible                                # → /home/abood/.local/bin/ansible
ansible --version | head -1                  # → ansible [core 2.X.Y]
python3 -c "import winrm; print('OK')"       # pywinrm
ansible-galaxy collection list ansible.windows
```

### Upgrade
```bash
pip3 install --user --upgrade ansible pywinrm
ansible-galaxy collection install --upgrade ansible.windows community.windows
```

### Add system-wide config (optional)

Create `~/.ansible.cfg` to set defaults:
```ini
[defaults]
inventory = /home/abood/lab/hosts.ini
forks     = 50
host_key_checking = False
stdout_callback = yaml

[winrm]
operation_timeout_sec = 60
read_timeout_sec      = 70
```

With this in place, you can drop the `-i ~/lab/hosts.ini --forks 50` from
every command.

---

## 9. Firewall (firewalld)

```bash
# What's open right now
sudo firewall-cmd --list-all

# Open MeshCentral defaults
sudo firewall-cmd --permanent --add-port=443/tcp
sudo firewall-cmd --permanent --add-port=80/tcp
sudo firewall-cmd --reload

# Open the file-server (only when 04_serve_files.sh is running)
sudo firewall-cmd --add-port=8080/tcp        # not --permanent: temporary

# Close a port
sudo firewall-cmd --permanent --remove-port=443/tcp
sudo firewall-cmd --reload
```

If `firewall-cmd` is not installed (firewalld not active), check with
`sudo systemctl status firewalld`. Some Nobara installs ship without it — in
which case there's no host firewall to configure.

---

## 10. Known inconsistencies (worth fixing)

These are real gaps — `config.env` exports values that scripts ignore. If you
change them, scripts that bypass `config.env` won't follow.

| Issue | Where | Fix |
|---|---|---|
| `LAB_RANGE_START` / `LAB_RANGE_END` not used by scan | [`02_add_devices.sh`](../02_add_devices.sh) line 16 hardcodes `SUBNET="10.3.5"` | Replace with: `SUBNET="${LAB_RANGE_START%.*}"` (derives `10.3.5` from `10.3.5.1`) |
| `MESH_ADMIN` not used | (no script reads it) | Either consume it in [`01_install_server.sh`](../01_install_server.sh)'s end-of-install message, or delete the variable |
| `LAB_PLAYBOOKS` not used | (no script reads it) | Cosmetic — leave or remove |
| Inline `labadmin/2026` credentials in [`02_add_devices.sh`](../02_add_devices.sh) and [`03_check_lab.sh`](../03_check_lab.sh) | bypass `config.env` | If you ever rotate the lab admin password, `sed -i` both files (or move the creds to `config.env`) |

---

## 11. Backup the controller

```bash
# Stop briefly to get a consistent DB snapshot
sudo systemctl stop meshcentral
mkdir -p ~/lab/backups
tar czf ~/lab/backups/meshcentral-$(date +%F-%H%M).tgz \
  -C ~/lab/meshcentral meshcentral-data
sudo systemctl start meshcentral
```

What's in `meshcentral-data/`:
- All device records + group memberships
- All user accounts + 2FA secrets + sessionKey
- Self-signed CA + per-host TLS certs (regenerating these breaks every
  enrolled agent's trust)
- Stats and event logs

Schedule weekly:
```bash
crontab -e
# Add:
0 3 * * 0 cd /home/abood/lab && sudo systemctl stop meshcentral && tar czf backups/meshcentral-$(date +\%F).tgz -C meshcentral meshcentral-data && sudo systemctl start meshcentral
```

Restoring on a new machine: complete Phases 0–1 of [`01_IMPLEMENTATION.md`](01_IMPLEMENTATION.md),
**stop the service**, replace `meshcentral-data/` with the tarball contents,
start the service, then update the IP per §6 if it changed.

---

## 12. End-to-end "verify the controller is healthy" checklist

```bash
source ~/lab/config.env

# 1. config.env actually loaded
echo "Controller IP from env: $CONTROLLER_IP"

# 2. systemd
systemctl is-enabled meshcentral
systemctl is-active meshcentral

# 3. Ports
ss -tlnp | grep -E ':443|:80|:4433'

# 4. Web UI responding
curl -k -s -o /dev/null -w "Web UI: HTTP %{http_code}\n" https://$CONTROLLER_IP

# 5. config.json is hardened
python3 -c "
import json
c = json.load(open('$HOME/lab/meshcentral/meshcentral-data/config.json'))
sk = c['settings'].get('sessionKey', '')
na = c['domains']['']
print('sessionKey set:', bool(sk) and sk != 'MyReallySecretPassword1')
print('newAccounts off:', na.get('newAccounts') is False)
"

# 6. Ansible reachable
which ansible >/dev/null && ansible --version | head -1

# 7. Agent binary present and matches signedagents
sha256sum ~/lab/files/MeshService64.exe \
          ~/lab/meshcentral/meshcentral-data/signedagents/MeshService64.exe \
          | awk '{print $1}' | sort -u | wc -l   # should print 1

# 8. Inventory parseable
ansible-inventory -i ~/lab/hosts.ini --list >/dev/null && echo "hosts.ini OK"

# 9. Lab reachable
~/lab/03_check_lab.sh
```

Any line that fails → fix that one before moving on.

---

## 13. What NOT to do

- **Don't `sudo systemctl restart meshcentral` without first validating
  `config.json`** with `python3 -m json.tool < ...config.json`. A syntax error
  takes the server down until you fix it manually.
- **Don't delete `meshcentral-data/`** under any circumstance — the cert
  authority lives there. Losing it means every enrolled agent has to be
  reinstalled with a freshly-signed binary.
- **Don't change `User=` in the systemd unit** without also `chown -R`'ing
  `~/lab/meshcentral/meshcentral-data/` to the new user.
- **Don't run MeshCentral as root.** The `setcap` on the node binary is the
  reason it can bind 80/443 as user `abood`.
- **Don't rotate the `sessionKey` casually.** Doing it forces every browser
  session to log out and re-authenticate.
- **Don't open MeshCentral to the public internet** without putting it behind
  a real cert (Let's Encrypt) and a reverse proxy. The self-signed flow is
  fine on a private lab network — not anywhere else.
- **Don't edit the systemd unit file without `daemon-reload` after.** Your
  edit will be ignored on the next restart.
