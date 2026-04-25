# Onboarding a Teammate — Linux Box

Set up a colleague's Linux machine to co-administer the lab from anywhere on the lab network. They'll have the same powers as the primary controller: Ansible commands + MeshCentral web access + CLI scripting.

Replace `<CONTROLLER_IP>` with the primary controller's IP (currently `10.3.5.96`).

---

## Prerequisites for the teammate

- Linux machine on the lab network (any distro — Fedora, Ubuntu, Debian, Arch all work)
- Sudo access on their box
- A MeshCentral account on the primary server (admin must create it — see Step 4 below)

---

## Step 1 — Install required tools

### Fedora / Nobara
```bash
sudo dnf install -y ansible nmap wol nodejs npm
pip install --user pywinrm
ansible-galaxy collection install ansible.windows community.windows
```

### Ubuntu / Debian
```bash
sudo apt update
sudo apt install -y ansible nmap wakeonlan nodejs npm python3-pip
pip install --user pywinrm
ansible-galaxy collection install ansible.windows community.windows
```

### Arch
```bash
sudo pacman -S ansible nmap wol nodejs npm python-pip
pip install --user pywinrm
ansible-galaxy collection install ansible.windows community.windows
```

### Verify (any distro)
```bash
ansible --version | head -1
python3 -c "import winrm; print('pywinrm OK')"
which nmap wol
```

---

## Step 2 — Get the lab folder

The teammate copies the entire `~/lab/` from the primary controller. Choose one method:

### Option A — Direct copy (if primary box has SSH server)
On the primary controller:
```bash
sudo dnf install -y openssh-server   # if not already installed
sudo systemctl enable --now sshd
```

On the teammate's box:
```bash
mkdir -p ~/lab
rsync -avz --exclude='meshcentral/node_modules' --exclude='meshcentral/meshcentral-backups' \
    abood@<CONTROLLER_IP>:/home/abood/lab/ ~/lab/
```

### Option B — Tarball over USB / shared folder
On the primary controller:
```bash
tar czf /tmp/lab-bundle.tar.gz \
    --exclude='lab/meshcentral/node_modules' \
    --exclude='lab/meshcentral/meshcentral-backups' \
    -C /home/abood lab
```

Move `/tmp/lab-bundle.tar.gz` to the teammate's box (USB or scp), then:
```bash
tar xzf lab-bundle.tar.gz -C ~/
chmod +x ~/lab/*.sh
```

---

## Step 3 — Configuration tweaks on the teammate's box

The teammate **does not run their own MeshCentral server**. They use the primary one over the network.

Edit [~/lab/config.env](../config.env):
```bash
# CONTROLLER_IP points to the PRIMARY server (not their own box)
export CONTROLLER_IP="<CONTROLLER_IP>"
```

Verify [~/lab/hosts.ini](../hosts.ini) has the current device list and credentials. If the teammate's copy is stale, the primary admin should send them the latest.

The teammate will **not** run `install_server.sh` — they're a client, not a server.

---

## Step 4 — Get a MeshCentral account

The primary admin creates an account for the teammate:

1. Open `https://<CONTROLLER_IP>` (logged in as primary admin)
2. **My Account → Manage Users → New Account**
3. Set username + temporary password → Save
4. Click the new user → check **Server Administrator** if they need full power (otherwise leave it for read-only)
5. Open the `Lab` device group → **Group Permissions** → add the new user with desired permissions (typically: View, Connect, Manage)

The teammate then opens `https://<CONTROLLER_IP>` and logs in with their credentials.

---

## Step 5 — Verify the teammate's box can reach the lab

```bash
# Health check — should see all devices reachable
~/lab/check_lab.sh

# One-shot ping
ansible lab -i ~/lab/hosts.ini -m win_ping --forks 50
```

If anything fails:
- Auth errors → confirm `hosts.ini` has the right credentials and is up to date
- Network errors → confirm the teammate's box is on the lab subnet (`10.3.5.0/24`)
- "command not found" → re-run Step 1 install commands

---

## What the teammate can now do

### From terminal (Ansible)
```bash
~/lab/check_lab.sh                                                   # health snapshot
~/lab/add_devices.sh                                                 # enroll new devices
ansible lab -i ~/lab/hosts.ini -m win_ping                           # ping all
ansible lab -i ~/lab/hosts.ini -m win_command -a "shutdown /s /t 0"  # shutdown all
ansible-playbook -i ~/lab/hosts.ini ~/lab/playbooks/verify_agents.yml
```

### From browser (MeshCentral)
- Open `https://<CONTROLLER_IP>`
- Remote desktop, terminal, file transfer, power management — all interactive

---

## What they should NOT do

- **Do not** run `install_server.sh` — they don't host the server
- **Do not** edit `meshcentral/meshcentral-data/` — it's the primary server's state
- **Do not** push large changes to `~/lab/hosts.ini` without coordinating with the primary admin (otherwise inventory diverges between machines)

---

## Keeping in sync

When the primary admin enrolls new devices, `~/lab/hosts.ini` updates on the primary box only. To keep the teammate's copy current, periodically:

```bash
# On teammate's box
rsync -avz abood@<CONTROLLER_IP>:/home/abood/lab/hosts.ini ~/lab/hosts.ini
```

Or share the file via your preferred mechanism (Git, NextCloud, USB, email).
