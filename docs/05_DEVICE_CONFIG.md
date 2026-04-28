# Per-Device Configuration Reference

What a properly-configured lab Windows device looks like, where every setting
lives, and how to change it cleanly — for one device or for all 50 at once.

The principle: **every device should look identical**. If you need to deviate
for one device, do it via Ansible/MeshCentral on that single host — don't
edit scripts ad-hoc, because the next re-enrollment will undo your change.

---

## 1. Canonical device state

Every lab device, after a clean enrollment, is in this state:

| Area | Setting | Default value | Set by |
|---|---|---|---|
| **Identity** | Local admin user | `INU` | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) |
| **Identity** | Local admin password | `2026` | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) |
| **Identity** | All other local users password | `2026` | [`04_Reset-Passwords.ps1`](../windows-scripts/04_Reset-Passwords.ps1) |
| **Remote mgmt** | WinRM service | Running, Automatic startup | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) |
| **Remote mgmt** | WinRM listener | HTTP on port 5985 | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) |
| **Remote mgmt** | Firewall rule `WinRM-HTTP-Lab` | Allow TCP 5985 inbound | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) |
| **Remote mgmt** | TrustedHosts | `*` | [`01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1) |
| **Remote mgmt** | MeshCentral agent | Service "Mesh Agent" running | [`playbooks/01_enroll_with_unlock.yml`](../playbooks/01_enroll_with_unlock.yml) |
| **Lockdown** | Lock state marker | `HKLM:\SOFTWARE\LabPolicy\StudentLock\Locked = 1` | [`02_Lock-StudentDevice.ps1`](../windows-scripts/02_Lock-StudentDevice.ps1) |
| **Lockdown** | Microsoft Store | Blocked | [`02_Lock-StudentDevice.ps1`](../windows-scripts/02_Lock-StudentDevice.ps1) |
| **Lockdown** | MSI installs (everyone) | `DisableMSI = 2` | [`02_Lock-StudentDevice.ps1`](../windows-scripts/02_Lock-StudentDevice.ps1) |
| **Lockdown** | EXE/MSI from `Downloads`, `Desktop`, `%TEMP%`, `AppData` | Blocked via SRP | [`02_Lock-StudentDevice.ps1`](../windows-scripts/02_Lock-StudentDevice.ps1) |
| **Lockdown** | Wallpaper change | Disabled | [`02_Lock-StudentDevice.ps1`](../windows-scripts/02_Lock-StudentDevice.ps1) |
| **Lockdown** | Lock-screen change | Disabled | [`02_Lock-StudentDevice.ps1`](../windows-scripts/02_Lock-StudentDevice.ps1) |
| **Lockdown** | Right-click → Set as background | Hidden | [`02_Lock-StudentDevice.ps1`](../windows-scripts/02_Lock-StudentDevice.ps1) |
| **Lockdown** | Password change (Ctrl-Alt-Del) | Blocked | [`02_Lock-StudentDevice.ps1`](../windows-scripts/02_Lock-StudentDevice.ps1) |
| **Lockdown** | Registry editor (non-admin) | Blocked | [`02_Lock-StudentDevice.ps1`](../windows-scripts/02_Lock-StudentDevice.ps1) |
| **Power** | Timezone | Jordan Standard Time (UTC+3) | [`03_Setup-SleepSchedule.ps1`](../windows-scripts/03_Setup-SleepSchedule.ps1) |
| **Power** | Hibernate | Off | [`03_Setup-SleepSchedule.ps1`](../windows-scripts/03_Setup-SleepSchedule.ps1) |
| **Power** | Wake timers | Enabled (AC + DC) | [`03_Setup-SleepSchedule.ps1`](../windows-scripts/03_Setup-SleepSchedule.ps1) |
| **Power** | Wake task | 08:00 Sat–Wed | [`03_Setup-SleepSchedule.ps1`](../windows-scripts/03_Setup-SleepSchedule.ps1) |
| **Power** | Auto-sleep task | 16:00 daily | [`03_Setup-SleepSchedule.ps1`](../windows-scripts/03_Setup-SleepSchedule.ps1) |
| **Power** | Idle sleep | Disabled (the scheduled task forces sleep instead) | [`03_Setup-SleepSchedule.ps1`](../windows-scripts/03_Setup-SleepSchedule.ps1) |

**Alternative power profile:** if you want hard shutdowns instead of sleep,
swap [`03_Setup-SleepSchedule.ps1`](../windows-scripts/03_Setup-SleepSchedule.ps1)
for [`07_Setup-ShutdownSchedule.ps1`](../windows-scripts/07_Setup-ShutdownSchedule.ps1).
It also blocks the Shutdown UI between 08:00 and 16:00 on active weekdays.
This requires BIOS-level "Wake on RTC" to power back on the next morning.

---

## 2. The three places config can change

| Where you change it | When to use | Effort |
|---|---|---|
| **A. Script source** (`windows-scripts/*.ps1`) + USB re-walk | Permanent change for all future devices | Walk to every device |
| **B. Ansible** (push + run on existing devices) | Apply same change to all already-enrolled devices | One command from Linux |
| **C. MeshCentral terminal** (one device) | One-off fix on one machine only | Browser, single device |

**Rule of thumb:** for any change you want to outlive re-imaging, do A *and* B.
A makes the new setting the default for fresh devices; B applies it now to the
fleet.

---

## 3. Setting-by-setting reference

For each setting: where it's defined, how to change it, how to push it to all
devices, and how to verify.

### 3.1 Lab admin username / password

**Defines who Ansible logs in as on every Windows device.**

#### Where to change
[`windows-scripts/01_Enroll-LabDevice.ps1`](../windows-scripts/01_Enroll-LabDevice.ps1):
```powershell
$user = "INU"
$pass = ConvertTo-SecureString "2026" -AsPlainText -Force
```

[`hosts.ini`](../hosts.ini):
```ini
[lab:vars]
ansible_user=INU
ansible_password=2026
```

Also update the inline credentials in:
- [`02_add_devices.sh`](../02_add_devices.sh) (two `ansible_user/ansible_password` blocks)
- [`03_check_lab.sh`](../03_check_lab.sh) (one block)
- [`collect_macs.py`](../collect_macs.py) (`USER` / `PASSWORD` constants near top)

#### Apply to existing devices (without re-walking USB)
```bash
source ~/lab/config.env
ansible lab -i ~/lab/hosts.ini -m win_user \
  -a "name=INU password=NewPassword update_password=always password_never_expires=yes groups=Administrators" \
  --forks 50
# Then update hosts.ini with the new password and re-test:
ansible lab -i ~/lab/hosts.ini -m win_ping --forks 50
```

#### Verify
```bash
ansible lab -i ~/lab/hosts.ini -m win_ping --forks 50
# Or on a single device:
ansible <ip> -i ~/lab/hosts.ini -m win_shell -a "Get-LocalUser INU | Format-List Name,Enabled,PasswordExpires"
```

---

### 3.2 Reset all local user passwords

**Unifies every enabled local user's password — useful before exams.**

#### Where to change
[`windows-scripts/04_Reset-Passwords.ps1`](../windows-scripts/04_Reset-Passwords.ps1):
```powershell
$UnifiedPassword = "2026"
```

#### Apply to all devices
USB walk: `04_Run-ResetPasswords.bat` on each device (interactive — asks
"YES" to confirm).

Or push remotely (no prompt):
```bash
source ~/lab/config.env
ansible lab -i ~/lab/hosts.ini -m win_shell -a "
  \$pw = ConvertTo-SecureString '2026' -AsPlainText -Force;
  Get-LocalUser | Where-Object Enabled -eq \$true | ForEach-Object {
    Set-LocalUser -Name \$_.Name -Password \$pw -PasswordNeverExpires \$true
  }
" --forks 50
```

#### Verify
```bash
ansible lab -i ~/lab/hosts.ini -m win_shell \
  -a "Get-LocalUser | Where-Object Enabled -eq \$true | Select Name,PasswordExpires" \
  --forks 50
```

---

### 3.3 WinRM port / transport

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

### 3.4 Lockdown profile (what's blocked)

**The most-edited script.** Each lockdown rule is a separate registry write
in [`02_Lock-StudentDevice.ps1`](../windows-scripts/02_Lock-StudentDevice.ps1).
Comment out (or delete) any block to drop that restriction.

| Block to relax | Comment out (lines) |
|---|---|
| Microsoft Store stays accessible | STEP 1 (lines 32–39) |
| Allow MSI installs (admins only) | Change `DisableMSI` from `2` to `1` (line 48) |
| Allow MSI installs (everyone) | Comment out STEP 2 (lines 41–55) |
| Allow installer execution from Downloads | Comment out STEP 3 (lines 57–99) |
| Allow wallpaper change | Comment out STEP 5 (lines 173–235) |
| Allow password change at lock screen | Comment out STEP 6 line `DisableChangePassword` |
| Allow regedit for non-admins | Comment out STEP 7 line `DisableRegistryTools` |
| Re-enable Task Manager (already on) | (no change — it's not blocked) |

**Do not edit other STEPs piecemeal** — each STEP is internally consistent.
If you remove half a STEP you'll get partial enforcement.

#### Apply to existing devices
USB walk: `02_Run-Lock.bat` on each device.

Or push the script via Ansible and run remotely:
```bash
source ~/lab/config.env

# Stage the script
ansible lab -i ~/lab/hosts.ini -m win_copy \
  -a "src=~/lab/windows-scripts/02_Lock-StudentDevice.ps1 dest=C:\\Users\\Public\\Lock.ps1" \
  --forks 50

# Run it
ansible lab -i ~/lab/hosts.ini -m win_shell \
  -a "powershell -ExecutionPolicy Bypass -File C:\\Users\\Public\\Lock.ps1" \
  --forks 50

# Cleanup
ansible lab -i ~/lab/hosts.ini -m win_file \
  -a "path=C:\\Users\\Public\\Lock.ps1 state=absent" --forks 50
```

#### Verify
```bash
# Lock state marker
ansible lab -i ~/lab/hosts.ini -m win_shell \
  -a "(Get-ItemProperty 'HKLM:\\SOFTWARE\\LabPolicy\\StudentLock').Locked" \
  --forks 50

# Specific block, e.g. MSI install policy
ansible lab -i ~/lab/hosts.ini -m win_shell \
  -a "(Get-ItemProperty 'HKLM:\\SOFTWARE\\Policies\\Microsoft\\Windows\\Installer').DisableMSI" \
  --forks 50
```

The fastest fleet-wide check is `~/lab/03_check_lab.sh` — its third pane
reports `Locked` / `UNLOCKED` per host.

#### Roll back lockdown (one device or all)
USB: `05_Run-Unlock.bat` on the device.

Or via Ansible:
```bash
ansible lab -i ~/lab/hosts.ini -m win_copy \
  -a "src=~/lab/windows-scripts/05_Unlock-StudentDevice.ps1 dest=C:\\Users\\Public\\Unlock.ps1" --forks 50
ansible lab -i ~/lab/hosts.ini -m win_shell \
  -a "powershell -ExecutionPolicy Bypass -File C:\\Users\\Public\\Unlock.ps1" --forks 50
```

---

### 3.5 Power schedule — wake/sleep/shutdown times

**Two mutually-exclusive profiles:** sleep (script `03`) or shutdown (script `07`).
Pick one and use it on every device — mixing them creates conflicting tasks.

#### Where to change (sleep profile)
Top of [`03_Setup-SleepSchedule.ps1`](../windows-scripts/03_Setup-SleepSchedule.ps1):
```powershell
$StartHour      = 8     # wake at 08:00
$StartMinute    = 0
$SleepHour      = 16    # auto-sleep at 16:00
$SleepMinute    = 0
$ActiveDays  = @("Saturday","Sunday","Monday","Tuesday","Wednesday")  # wake + sleep
$PassiveDays = @("Thursday","Friday")                                  # sleep only
```

[`07_Setup-ShutdownSchedule.ps1`](../windows-scripts/07_Setup-ShutdownSchedule.ps1)
has the same variables — change them in the file you actually use.

#### Apply
USB: re-run the corresponding `Run-*.bat`. Or push via Ansible (analogous to
3.4).

The script removes any old `\LabSchedule\` tasks before creating new ones, so
re-running is safe.

#### Verify
```bash
# List the scheduled tasks
ansible lab -i ~/lab/hosts.ini -m win_shell \
  -a "Get-ScheduledTask -TaskPath '\\LabSchedule\\' | Select TaskName,State" \
  --forks 50
```

#### Remove the schedule (one device or all)
USB: `06_Run-ScheduleRemove.bat` on the device.

#### Caveat: timezone
Both scripts force timezone to **Jordan Standard Time (UTC+3)** before creating
tasks. If your lab is in a different timezone, edit:
```powershell
Set-TimeZone -Id "Jordan Standard Time"
```
to your zone (e.g. `"Eastern Standard Time"`, `"Arabian Standard Time"`).
List available zones with:
```powershell
Get-TimeZone -ListAvailable | Select Id
```

#### Caveat: BIOS for shutdown profile
The shutdown profile (`07_*`) needs **"RTC Wake Alarm" enabled in BIOS** on
each device to power back on after auto-shutdown. The sleep profile (`03_*`)
does **not** need any BIOS changes — wake-from-sleep works through Windows
alone. Sleep is the recommended profile for that reason.

---

### 3.6 Wallpaper / lock-screen image

The lockdown script forces the Windows default. To set your own:

Edit [`02_Lock-StudentDevice.ps1`](../windows-scripts/02_Lock-StudentDevice.ps1)
near the top of STEP 4 / STEP 5:
```powershell
$defaultWallpaper  = "C:\Windows\Web\Wallpaper\Windows\img0.jpg"
$defaultLockScreen = "C:\Windows\Web\Screen\img100.jpg"
```

Replace with paths that **exist on every device** (or push your image first):
```bash
ansible lab -i ~/lab/hosts.ini -m win_copy \
  -a "src=~/lab/files/lab-wallpaper.jpg dest=C:\\Windows\\Web\\Wallpaper\\Lab\\lab.jpg" \
  --forks 50
```
Then change the script:
```powershell
$defaultWallpaper = "C:\Windows\Web\Wallpaper\Lab\lab.jpg"
```
And re-run `02_Run-Lock.bat` (or push via Ansible per 3.4).

---

### 3.7 MeshCentral agent

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
2. Re-enroll with the new server-keyed binary (see Phase 7.1 in
   [`docs/01_IMPLEMENTATION.md`](01_IMPLEMENTATION.md)).

---

## 4. End-to-end "verify a fresh device" checklist

After enrolling a new device, run this on the controller to confirm every
canonical setting is in place:

```bash
source ~/lab/config.env
HOST=10.3.5.NEW

ansible $HOST -i ~/lab/hosts.ini -m win_shell -a @"
Write-Host '--- Identity ---'
Get-LocalUser INU | Format-List Name,Enabled,PasswordExpires
Write-Host '--- WinRM ---'
Get-Service WinRM | Format-List Name,Status,StartType
Write-Host '--- Mesh Agent ---'
Get-Service 'Mesh Agent' | Format-List Status,StartType
Write-Host '--- Lock state ---'
(Get-ItemProperty 'HKLM:\SOFTWARE\LabPolicy\StudentLock' -ErrorAction SilentlyContinue) | Format-List Locked,LockedAt
Write-Host '--- Schedule ---'
Get-ScheduledTask -TaskPath '\LabSchedule\' -ErrorAction SilentlyContinue | Format-Table TaskName,State
Write-Host '--- Timezone ---'
(Get-TimeZone).Id
"@
```

Every section should show populated values. Empty `--- Mesh Agent ---` means
the playbook didn't complete — re-run `~/lab/02_add_devices.sh`.

---

## 5. Common workflows (copy-paste)

```bash
source ~/lab/config.env

# Re-lock every device that drifted to UNLOCKED
ansible lab -i ~/lab/hosts.ini -m win_copy \
  -a "src=~/lab/windows-scripts/02_Lock-StudentDevice.ps1 dest=C:\\Users\\Public\\Lock.ps1" --forks 50
ansible lab -i ~/lab/hosts.ini -m win_shell \
  -a "powershell -ExecutionPolicy Bypass -File C:\\Users\\Public\\Lock.ps1" --forks 50

# Unlock a single device for maintenance
ansible 10.3.5.X -i ~/lab/hosts.ini -m win_copy \
  -a "src=~/lab/windows-scripts/05_Unlock-StudentDevice.ps1 dest=C:\\Users\\Public\\Unlock.ps1"
ansible 10.3.5.X -i ~/lab/hosts.ini -m win_shell \
  -a "powershell -ExecutionPolicy Bypass -File C:\\Users\\Public\\Unlock.ps1"

# Rotate the lab admin password fleet-wide
NEWPW='Spring2026!'
ansible lab -i ~/lab/hosts.ini -m win_user \
  -a "name=INU password=$NEWPW update_password=always password_never_expires=yes" --forks 50
sed -i "s/^ansible_password=.*/ansible_password=$NEWPW/" ~/lab/hosts.ini

# Push a new wallpaper to all devices
ansible lab -i ~/lab/hosts.ini -m win_copy \
  -a "src=~/lab/files/lab-wallpaper.jpg dest=C:\\Windows\\Web\\Wallpaper\\Lab\\lab.jpg" --forks 50

# Reboot one device
ansible 10.3.5.X -i ~/lab/hosts.ini -m win_command -a "shutdown /r /t 0"

# Reboot all devices
ansible lab -i ~/lab/hosts.ini -m win_command -a "shutdown /r /t 0" --forks 50

# Health snapshot
~/lab/03_check_lab.sh
```

---

## 6. What NOT to do

- **Don't edit registry keys directly on one device** for things the lockdown
  script controls — they'll get clobbered on the next run of
  `02_Run-Lock.bat`. Edit the script instead.
- **Don't mix sleep and shutdown profiles** on different devices — operators
  will assume one model.
- **Don't change `INU` to a domain account.** The whole flow assumes a
  local admin; switching to a domain account requires re-doing WinRM auth,
  the playbook, and `hosts.ini`.
- **Don't disable WinRM after enrollment** — Ansible loses the device.
  MeshCentral keeps working, but you lose batch-management until you re-enable.
- **Don't enable RDP "for convenience"** unless you also harden the firewall —
  port 3389 from the lab subnet is not the same threat model as MeshCentral
  over 443.
