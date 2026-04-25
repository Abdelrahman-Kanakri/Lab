# Onboarding a Teammate — Windows Box

Set up a colleague's Windows machine to co-administer the lab.

A Windows teammate has two paths:
1. **Browser only (recommended, simple)** — use the MeshCentral web UI for everything
2. **Browser + Ansible** — also run Ansible from Windows for terminal-based bulk ops (advanced)

For 95% of admin tasks, **path 1 is enough**. Path 2 is only for teammates who want to script bulk operations themselves.

Replace `<CONTROLLER_IP>` with the primary controller's IP (currently `10.3.5.96`).

---

## Path 1 — Browser-only access (simple)

### Prerequisites
- Windows machine on the lab network (`10.3.5.0/24`)
- A modern browser (Edge, Chrome, Firefox)
- A MeshCentral account on the primary server

### Step 1 — Get a MeshCentral account

The primary admin creates one (see `JOBMATE_LINUX.md` Step 4 for the procedure — it's identical regardless of teammate OS).

The teammate receives:
- A username + temporary password
- The URL `https://<CONTROLLER_IP>`

### Step 2 — First login

1. Open `https://<CONTROLLER_IP>`
2. Accept the self-signed cert warning (Advanced → Continue)
3. Log in with the credentials provided
4. Change the temporary password (Account → Security)
5. Optional: enable 2FA

### Step 3 — Use the lab

The teammate now has a complete admin console in their browser. From the `Lab` device group they can:

| Task | UI location |
|---|---|
| See which devices are online | Device group main view (green = online, grey = offline) |
| Remote desktop into a device | Click device → **Desktop** tab |
| Run PowerShell on a device | Click device → **Terminal** tab |
| Upload / download files | Click device → **Files** tab |
| View running processes | Click device → **Processes** tab |
| Power: shutdown / restart / wake | Right-click device(s) → **Power** |
| Run a command on many devices | Group → **Run Command** |
| Wake-on-LAN an offline device | Right-click grey device → **Wake-up** |

That's the entire workflow. No software install on the teammate's Windows box.

---

## Path 2 — Browser + Ansible (advanced)

If the teammate wants to script bulk operations from a Windows terminal, they need to install Ansible. Ansible was historically Linux-only, but **WSL** (Windows Subsystem for Linux) makes it straightforward.

### Step 1 — Install WSL + Ubuntu

In **PowerShell as Administrator**:
```powershell
wsl --install
```

This installs WSL2 + Ubuntu by default. Reboot if prompted. After reboot, finish the Ubuntu setup (create a Linux username/password).

### Step 2 — Inside the Ubuntu (WSL) shell, install the same Linux tools

Open the Ubuntu app from Start menu, then:
```bash
sudo apt update
sudo apt install -y ansible nmap wakeonlan python3-pip
pip install --user pywinrm
ansible-galaxy collection install ansible.windows community.windows
```

Verify:
```bash
ansible --version | head -1
python3 -c "import winrm; print('pywinrm OK')"
```

### Step 3 — Get the lab folder into WSL

Same as Linux teammate setup — see [JOBMATE_LINUX.md](JOBMATE_LINUX.md) Step 2.

The lab folder lives inside WSL at `~/lab/` (i.e. `\\wsl$\Ubuntu\home\<linuxuser>\lab\` from Windows Explorer).

### Step 4 — Configure and verify

```bash
# Inside WSL Ubuntu shell
nano ~/lab/config.env   # set CONTROLLER_IP=<CONTROLLER_IP>
~/lab/check_lab.sh      # confirm Ansible reaches lab devices
```

### Step 5 — Use it

Same commands as the Linux teammate:
```bash
~/lab/check_lab.sh
~/lab/add_devices.sh
ansible lab -i ~/lab/hosts.ini -m win_ping
```

---

## What the teammate can do (regardless of path)

- Remote control any lab device
- Run scripts and commands on any group of devices
- Manage power (wake / shutdown / restart)
- Transfer files
- Monitor processes

## What they should NOT do

- Don't share their MeshCentral credentials
- Don't disable 2FA on the primary admin account
- Don't modify `meshcentral-data/` on the primary server
- Don't push large changes to `~/lab/hosts.ini` (WSL path) without coordinating with the primary admin

---

## Cheat sheet for the Windows teammate

| Need | Do this |
|---|---|
| Quick remote desktop | Browser → device → Desktop tab |
| Quick remote shell | Browser → device → Terminal tab |
| Push a file to one device | Browser → device → Files tab → drag-and-drop |
| Push a file to many devices | Browser → group → Files → upload, then **Run Command**: `Copy-Item ...` |
| Wake a sleeping device | Browser → right-click grey device → Wake-up |
| Shutdown all at end of day | Browser → group → Power → Shutdown |
| Bulk PowerShell command | Browser → group → Run Command |
