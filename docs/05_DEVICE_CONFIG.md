# Per-Device Configuration Reference

What a properly-configured lab Windows device looks like, where every setting
lives, and how to change it cleanly — for one device or for all 50 at once.

The principle: **every device should look identical**. If you need to deviate
for one device, do it via Ansible/MeshCentral on that single host — don't
edit scripts ad-hoc, because the next re-enrollment will undo your change.

> ## The active model (read this first)
>
> The lab no longer uses any scripted **lockdown**, **scheduled sleep/shutdown**,
> or **bulk password-reset**. Those old scripts live in
> `windows-scripts/inactive_kept_for_reference/` and are **not** part of the
> registration flow — don't run them expecting them to be current. The active
> model is deliberately simple:
>
> - **Admin account** `Lab-Admin` / `2026@admin` (Administrators) — created
>   **manually**, used by Ansible. The single credential in `hosts.ini`.
> - **Student account** (Guests) — created by `01_Enroll-LabDevice.ps1`, which
>   **prompts** you for the username + password. Student restrictions come purely
>   from **Guests-group membership** — there is no lockdown script.
> - **Power**: never sleep / never hibernate / Fast Startup off / Wake-on-LAN on.
>   No scheduled sleep or shutdown tasks — devices stay awake and are woken or
>   shut down on demand via MeshCentral/Ansible.

---

## 1. Canonical device state

Every lab device, after a clean enrollment, is in this state:

| Area | Setting | Value | Set by |
|---|---|---|---|
| **Identity** | Admin user (Administrators) | `Lab-Admin` / `2026@admin` | created **manually**; verified by [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) |
| **Identity** | Student user (Guests) | operator-chosen at the prompt (default `INU`) | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) |
| **Identity** | All other local users | deleted | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) |
| **Remote mgmt** | WinRM service | Running, Automatic startup | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) |
| **Remote mgmt** | WinRM listener | HTTP on port 5985 | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) |
| **Remote mgmt** | Firewall rule `WinRM-HTTP-Lab` | Allow TCP 5985 inbound | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) |
| **Remote mgmt** | TrustedHosts | `*` | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) |
| **Remote mgmt** | MeshCentral agent | Service "Mesh Agent" running | [`playbooks/01_enroll.yml`](../playbooks/01_enroll.yml) |
| **Restrictions** | Student limits | via **Guests-group membership** only (no lockdown script) | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) |
| **Power** | Sleep / display / disk / hibernate timeouts | All `0` (never) | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) + [`playbooks/01_enroll.yml`](../playbooks/01_enroll.yml) |
| **Power** | Hibernation + Fast Startup | Off (`powercfg -h off`) | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) + [`playbooks/01_enroll.yml`](../playbooks/01_enroll.yml) |
| **Power** | Wake-on-LAN | Enabled on every UP physical NIC (best effort) | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) + [`playbooks/01_enroll.yml`](../playbooks/01_enroll.yml) |

---

## 2. The three places config can change

| Where you change it | When to use | Effort |
|---|---|---|
| **A. Script source** (`windows-scripts/*.ps1`, `playbooks/*.yml`) + re-run | Permanent change for all future devices | Walk to every device, or re-run the playbook |
| **B. Ansible** (push + run on existing devices) | Apply same change to all already-enrolled devices | One command from Linux |
| **C. MeshCentral terminal** (one device) | One-off fix on one machine only | Browser, single device |

**Rule of thumb:** for any change you want to outlive re-imaging, do A *and* B.
A makes the new setting the default for fresh devices; B applies it now to the
fleet.

---

## 3. Setting-by-setting reference

For each setting: where it's defined, how to change it, how to push it to all
devices, and how to verify.

### 3.1 Account credentials

There are two accounts, and they are changed in different places.

#### Admin account (`Lab-Admin`) — what Ansible logs in as

This account is **created manually** on each device (the enrollment script only
verifies it exists — it does not create or set its password). The controller
side is configured in [`config.env`](../config.env):
```bash
export LAB_ADMIN_USER="Lab-Admin"
export LAB_ADMIN_PASS="2026@admin"
```
All shell scripts read these values and regenerate [`hosts.ini`](../hosts.ini)
from them, so you don't edit `hosts.ini` by hand. To **rotate** the admin
password fleet-wide, follow the procedure in
[`06_CONTROLLER_CONFIG.md`](06_CONTROLLER_CONFIG.md) → §2.3.

Verify:
```bash
ansible lab -i ~/lab/hosts.ini -m win_ping --forks 50
# Single device:
ansible <ip> -i ~/lab/hosts.ini -m win_shell -a "Get-LocalUser Lab-Admin | Format-List Name,Enabled,PasswordExpires"
```

#### Student account — what students log in as

Set **interactively** when you run [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1)
on each device: the script prompts (in red) for the username and password.
Use the **same values on every device**. To change them later, just re-run the
enrollment script on the device — it resets the student account's password to
whatever you type. Record the chosen username in `config.env` so
`04_verify_lab.sh` checks for the right account:
```bash
export STUDENT_USER="INU"   # the name you typed at the prompt
```

Verify:
```bash
ansible <ip> -i ~/lab/hosts.ini -m win_shell -a "Get-LocalUser INU | Format-List Name,Enabled,PasswordExpires"
```

---

### 3.2 WinRM port / transport

**Default: HTTP on 5985 with NTLM auth.** Switch to HTTPS on 5986 if you
need encrypted WinRM (most labs don't — the network is already isolated).

#### Where to change
On each Windows device (one-time, locally as Admin):
```powershell
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=`"$env:COMPUTERNAME`"; CertificateThumbprint=`"$($cert.Thumbprint)`"}"
New-NetFirewallRule -Name 'WinRM-HTTPS' -DisplayName 'WinRM HTTPS' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5986
```

Then on the controller, [`hosts.ini`](../hosts.ini):
```ini
[lab:vars]
ansible_port=5986
ansible_winrm_scheme=https
ansible_winrm_server_cert_validation=ignore
```

And in [`02_add_devices.sh`](../02_add_devices.sh) change `5985` → `5986` in
the WinRM scan and inline inventory blocks.

#### Verify
```bash
ansible lab -i ~/lab/hosts.ini -m win_ping --forks 50
```

---

### 3.3 Power behaviour

The active power policy is "**never sleep, never hibernate, Wake-on-LAN on**",
applied by both [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1)
and [`playbooks/01_enroll.yml`](../playbooks/01_enroll.yml). There are **no
scheduled wake/sleep/shutdown tasks** — devices stay awake and you wake or shut
them down on demand from MeshCentral or Ansible.

#### Change it for the whole fleet
Edit the `powercfg` block in [`playbooks/01_enroll.yml`](../playbooks/01_enroll.yml)
(and the matching block in the enrollment script for future USB walks), then
re-run the playbook:
```bash
ansible-playbook -i ~/lab/hosts.ini ~/lab/playbooks/01_enroll.yml --forks 30
```

#### Shut down / reboot / wake on demand
```bash
# Shut down all devices
ansible lab -i ~/lab/hosts.ini -m win_command -a "shutdown /s /t 0" --forks 50
# Reboot one device
ansible 10.3.5.X -i ~/lab/hosts.ini -m win_command -a "shutdown /r /t 0"
# Wake an offline device: MeshCentral UI → right-click grey device → Wake-up
# (or `wol -f ~/lab/macs.txt` once MACs are banked)
```

#### Verify
```bash
ansible lab -i ~/lab/hosts.ini -m win_shell \
  -a "powercfg /a" --forks 50
# 04_verify_lab.sh also reports sleep timeout, hibernation, and WoL per device.
```

---

### 3.4 MeshCentral agent

Server-keyed binary at `~/lab/files/MeshService64.exe`. Installed as Windows
service `Mesh Agent`.

#### Reinstall on a single device
```bash
source ~/lab/config.env
ansible <ip> -i ~/lab/hosts.ini -m win_copy \
  -a "src=~/lab/files/MeshService64.exe dest=C:\\Windows\\Temp\\MeshService64.exe"
ansible <ip> -i ~/lab/hosts.ini -m win_shell \
  -a "C:\\Windows\\Temp\\MeshService64.exe -fullinstall"
```

#### Verify
```bash
ansible lab -i ~/lab/hosts.ini -m win_shell \
  -a "Get-Service 'Mesh Agent' | Select Status,StartType" \
  --forks 50
```

#### If the controller IP changed
The existing agent points at the old IP. Two options:
1. Re-point in place (while old IP still reachable):
   ```bash
   ansible lab -i ~/lab/hosts.ini -m win_shell \
     -a "& 'C:\\Program Files\\Mesh Agent\\MeshAgent.exe' -meshaction:changeserver -server:wss://<NEW_IP>:443/agent.ashx" \
     --forks 50
   ```
2. Re-enroll with the new server-keyed binary (see
   [`FRESH_START.md`](../FRESH_START.md) — reinstall the server and re-stage the agent).

---

## 4. End-to-end "verify a fresh device" checklist

After enrolling a new device, the simplest check is the fleet-wide end-state
checker:
```bash
bash ~/lab/04_verify_lab.sh
```
It prints one row per device — reachable / `Lab-Admin` present / student account
in Guests / Mesh Agent running / sleep timeout 0 / hibernation off / WoL — and
flags anything off-spec.

To inspect a single fresh device directly:
```bash
source ~/lab/config.env
HOST=10.3.5.NEW

ansible $HOST -i ~/lab/hosts.ini -m win_shell -a @"
Write-Host '--- Identity (student account) ---'
Get-LocalUser $env:STUDENT_USER | Format-List Name,Enabled,PasswordExpires
Write-Host '--- WinRM ---'
Get-Service WinRM | Format-List Name,Status,StartType
Write-Host '--- Mesh Agent ---'
Get-Service 'Mesh Agent' | Format-List Status,StartType
Write-Host '--- Power ---'
powercfg /a
"@
```

Empty `--- Mesh Agent ---` means the playbook didn't complete — re-run
`bash ~/lab/02_add_devices.sh`.

---

## 5. Common workflows (copy-paste)

```bash
source ~/lab/config.env

# Reset the student password on a device (re-run enrollment, or push directly)
ansible 10.3.5.X -i ~/lab/hosts.ini -m win_user \
  -a "name=$STUDENT_USER password=NewStudentPass update_password=always password_never_expires=yes groups=Guests"

# Rotate the Lab-Admin password fleet-wide
NEWPW='Spring2026!'
ansible lab -i ~/lab/hosts.ini -m win_user \
  -a "name=Lab-Admin password=$NEWPW update_password=always password_never_expires=yes groups=Administrators" --forks 50
sed -i "s|^export LAB_ADMIN_PASS=.*|export LAB_ADMIN_PASS=\"$NEWPW\"|" ~/lab/config.env
# hosts.ini is regenerated from config.env by the helper scripts.

# Reboot one device
ansible 10.3.5.X -i ~/lab/hosts.ini -m win_command -a "shutdown /r /t 0"

# Reboot all devices
ansible lab -i ~/lab/hosts.ini -m win_command -a "shutdown /r /t 0" --forks 50

# Shut down all devices (end of day)
ansible lab -i ~/lab/hosts.ini -m win_command -a "shutdown /s /t 0" --forks 50

# Health snapshot
bash ~/lab/03_check_lab.sh
```

---

## 6. What NOT to do

- **Don't change `Lab-Admin` to a domain account.** The whole flow assumes a
  local admin; switching to a domain account requires re-doing WinRM auth,
  the playbook, and `hosts.ini`.
- **Don't give the student account anything beyond Guests.** Adding it to Users
  or Administrators removes the restrictions the lab relies on — the enrollment
  script deliberately enforces Guests-only.
- **Don't disable WinRM after enrollment** — Ansible loses the device.
  MeshCentral keeps working, but you lose batch-management until you re-enable.
- **Don't enable RDP "for convenience"** unless you also harden the firewall —
  port 3389 from the lab subnet is not the same threat model as MeshCentral
  over 443.
```
