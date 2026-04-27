# Checking & Adding Devices to the Inventory

Day-to-day operations for managing the lab inventory. Two scripts cover everything:

- **[03_check_lab.sh](../03_check_lab.sh)** — read-only health snapshot (run anytime)
- **[02_add_devices.sh](../02_add_devices.sh)** — discover new devices and enroll them

> **Need to *change* something, not just check it?**
> - To adjust a setting **on the Linux controller** (controller IP, lab subnet,
>   admin password, MeshCentral port, etc.) →
>   [`06_CONTROLLER_CONFIG.md`](06_CONTROLLER_CONFIG.md)
> - To adjust a setting **on the Windows devices** (admin creds, lockdown,
>   power schedule, wallpaper, etc.) →
>   [`05_DEVICE_CONFIG.md`](05_DEVICE_CONFIG.md)
> - First-time build of a fresh controller →
>   [`01_IMPLEMENTATION.md`](01_IMPLEMENTATION.md)
> - Some hosts came back as `unreachable=1` / `failed≥1` →
>   [`07_UNREACHABLE_DEVICES.md`](07_UNREACHABLE_DEVICES.md)

---

## When to use each

| Situation | Run |
|---|---|
| Want to see "is everything OK right now?" | `check_lab.sh` |
| You walked to N new devices with the USB | `add_devices.sh` |
| Some devices got re-imaged | First `Enroll-LabDevice.bat` on each, then `add_devices.sh` |
| A teammate says "device X not responding" | `check_lab.sh` then look for X in the report |
| Before a scheduled exam to confirm readiness | `check_lab.sh` |
| Devices were powered off and now back on | `check_lab.sh` (no enrollment needed — agent auto-reconnects) |

---

## `check_lab.sh` — health snapshot

### What it shows

```
================================================================
  Lab Health Check  (2026-04-25 14:30:00)
================================================================

Inventory size: 28 devices

[1/3] WinRM reachability...
    reachable: 24   unreachable: 4
      10.3.5.16 | UNREACHABLE!
      10.3.5.37 | UNREACHABLE!
      10.3.5.84 | UNREACHABLE!
      10.3.5.93 | UNREACHABLE!

[2/3] Mesh Agent service status (only on reachable hosts)...
    running: 24   not running: 0

[3/3] Lock state (HKLM:\SOFTWARE\LabPolicy\StudentLock)...
    locked: 23   UNLOCKED: 1
    These hosts are NOT locked (probably need re-lock):
      10.3.5.122 UNLOCKED

================================================================
  Summary
  Inventory:        28
  WinRM reachable:  24
  Mesh Agent up:    24
  Locked:           23
================================================================
```

### Run it
```bash
~/lab/check_lab.sh
```

### How to read the output

| Section | Meaning | What to do |
|---|---|---|
| **Inventory size** | Total devices in `~/lab/hosts.ini` | If lower than expected → run `add_devices.sh` |
| **WinRM reachable** | Devices that responded to Ansible | UNREACHABLE = sleeping/off, usually fine; agent reconnects on wake |
| **Mesh Agent up** | Service status on reachable devices | Should match WinRM reachable count. Mismatch → re-enroll that host |
| **Locked** | Devices with `Locked=1` registry flag | UNLOCKED count > 0 → re-run lock playbook on those |

### Re-lock devices that drifted

If `check_lab.sh` reports `UNLOCKED` devices:
```bash
ansible <ip1>,<ip2> -i ~/lab/hosts.ini -m win_shell -a \
    "powershell -ExecutionPolicy Bypass -File C:\\Windows\\LabDeploy\\Lock-StudentDevice.ps1" \
    --forks 10
```

Or use the enrollment playbook (it ends with Lock):
```bash
ansible-playbook -i ~/lab/hosts.ini ~/lab/playbooks/enroll_with_unlock.yml --limit "<ip1>,<ip2>"
```

---

## `add_devices.sh` — discover and enroll

### When to run it

After you've physically run [Enroll-LabDevice.bat](../windows-scripts/Enroll-LabDevice.bat) on one or more new devices. It only enrolls hosts not already in `~/lab/hosts.ini`, so re-running is safe and cheap.

### What it does (6 phases)

```
[1/6] Scan 10.3.5.0/24 for WinRM (port 5985)
[2/6] Diff against ~/lab/hosts.ini → find what's new
[3/6] Test labadmin/2026 auth on the new hosts
[4/6] Show you the list and ask to proceed (y/N)
[5/6] Run enroll_with_unlock.yml on confirmed-working hosts
[6/6] Merge them into ~/lab/hosts.ini
```

### Run it
```bash
~/lab/add_devices.sh
```

### Example session

```
================================================================
  Lab Device Discovery & Enrollment
================================================================

[1/6] Scanning 10.3.5.0/24 for WinRM (5985)...
    found 32 hosts with WinRM open

[2/6] Finding new devices (not yet in ~/lab/hosts.ini)...
    4 new devices:
      10.3.5.48
      10.3.5.74
      10.3.5.88
      10.3.5.110

[3/6] Testing labadmin/2026 auth on the 4 new hosts...
    auth OK on 4  /  failed on 0

[4/6] Ready to enroll these in MeshCentral:
      10.3.5.48
      10.3.5.74
      10.3.5.88
      10.3.5.110

Proceed with enrollment? [y/N] y

[5/6] Running enrollment playbook...
    [PLAY RECAP showing 4 successes]

[6/6] Merging successful hosts into ~/lab/hosts.ini...

================================================================
  Done. ~/lab/hosts.ini now has 32 devices.
  Open https://10.3.5.96 to see them in MeshCentral.
================================================================
```

### What if step 3 shows auth failures?

```
[skip] 10.3.5.48 | UNREACHABLE!
```

That means WinRM is open but `labadmin/2026` doesn't authenticate. Causes:
- Enroll-LabDevice.bat wasn't actually run on that device → run it
- Enroll-LabDevice.bat was run but the user named themselves something else manually
- Non-lab device (staff machine that just happens to have WinRM enabled) → skip it

`add_devices.sh` automatically skips auth-failed hosts, so the enrollment continues with whatever passed.

---

## Manual flow (when scripts can't be used)

If you need to add ONE specific device by hand:

### 1. Confirm WinRM is reachable
```bash
timeout 2 bash -c "echo > /dev/tcp/<IP>/5985" && echo OPEN || echo CLOSED
```

### 2. Confirm Ansible auth
```bash
ansible <IP> -i ~/lab/hosts.ini -m win_ping
```

### 3. Run enrollment on that one host
```bash
ansible-playbook -i ~/lab/hosts.ini ~/lab/playbooks/enroll_with_unlock.yml --limit <IP>
```

### 4. Add the IP to inventory
Open [~/lab/hosts.ini](../hosts.ini) and add the IP under `[lab]`. Or:
```bash
sed -i "/^\[lab\]/a <IP>" ~/lab/hosts.ini
```

---

## Removing a device from the inventory

If a lab device is permanently retired:

### 1. Uninstall the agent (optional but clean)
```bash
ansible <IP> -i ~/lab/hosts.ini -m win_shell \
    -a "& 'C:\\Program Files\\Mesh Agent\\MeshAgent.exe' -fulluninstall"
```

### 2. Remove from inventory
Open [~/lab/hosts.ini](../hosts.ini) and delete the line. Or:
```bash
sed -i "/^<IP>$/d" ~/lab/hosts.ini
```

### 3. Remove from MeshCentral UI
Open `https://10.3.5.96` → Lab group → click device → **Delete Device**.

---

## Cheat sheet

```bash
# Quick health
~/lab/check_lab.sh

# Discover + enroll new
~/lab/add_devices.sh

# Just the WinRM scan (no enrollment)
for i in $(seq 1 254); do
    ip="10.3.5.$i"
    timeout 1 bash -c "echo > /dev/tcp/$ip/5985" 2>/dev/null && echo "$ip"
done

# Re-test all currently in inventory
ansible lab -i ~/lab/hosts.ini -m win_ping --forks 50

# Run a one-shot command on every reachable device
ansible lab -i ~/lab/hosts.ini -m win_shell -a "Get-Date" --forks 50

# Verify Mesh Agent on every device
ansible-playbook -i ~/lab/hosts.ini ~/lab/playbooks/verify_agents.yml
```
