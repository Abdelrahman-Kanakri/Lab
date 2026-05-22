# Fresh-Start Guide

End-of-semester rebuild: every device gets factory-reset / cleaned, then re-enrolled from scratch. This is the only doc you need for that flow.

If anything below differs from what you actually see, **stop and read [`README.md`](README.md) for the full reference** — but the steps here are the canonical path.

---

## Active inventory of files (after the cleanup)

The active path uses just these:

```
~/lab/
├── 00_reset_controller.sh              ← wipe controller-side state (use only when re-installing)
├── 01_install_server.sh                ← install MeshCentral + systemd unit
├── 02_add_devices.sh                   ← discover + enroll new devices (calls playbooks/01_enroll.yml)
├── 03_check_lab.sh                     ← daily health snapshot
├── 04_verify_lab.sh                    ← end-state checker (run after every change)
├── 04_serve_files.sh                   ← occasional: HTTP server for file pushes
├── config.env                          ← (gitignored) your CONTROLLER_IP / subnet / creds
├── hosts.ini                           ← (gitignored) auto-managed inventory
│
├── playbooks/
│   ├── 01_enroll.yml                   ← installs Mesh Agent + disables sleep + enables WoL
│   ├── 02_verify_agents.yml            ← per-device health check
│   └── 03_uninstall_agents.yml         ← rollback
│
├── windows-scripts/
│   └── 01_Enroll-LabDevice.bat (+ .ps1)  ← USB-walked: creates INU + WinRM + harden
│
└── files/
    ├── Harden-LabDevice.ps1            ← used internally by playbooks (legacy retrofit)
    └── Enable-WoL.ps1                  ← used internally by playbooks (legacy retrofit)
```

Everything in `playbooks/inactive_kept_for_reference/`, `windows-scripts/inactive_kept_for_reference/`, and `transitions/` is **not used by the active flow**. It's kept on disk because some of it may be useful as a reference or in a future migration, but you can safely ignore it during a fresh install.

---

## Step-by-step

### 1. (If reusing the same controller box) Wipe controller state

Skip if the controller is brand new.

```bash
bash ~/lab/00_reset_controller.sh
```

This stops + uninstalls the meshcentral systemd unit, archives `meshcentral/`, `files/MeshService64.exe`, `hosts.ini`, `labels.txt` to `~/lab/backups/<timestamp>/`, then leaves a clean slate.

### 2. Confirm `config.env` is correct

```bash
cat ~/lab/config.env
```

Check:
- `CONTROLLER_IP` matches what `ip -4 addr show` reports for your lab interface
- `LAB_RANGE_START` / `LAB_RANGE_END` cover your devices' subnet
- `LAB_ADMIN_USER="INU"` and `LAB_ADMIN_PASS="2026"` (or whatever password you actually set in `windows-scripts/01_Enroll-LabDevice.ps1`)

If the controller's IP changed since you last ran it, **regenerate the cert** by deleting `meshcentral/meshcentral-data/` (the install script will recreate it).

### 3. Install MeshCentral

```bash
bash ~/lab/01_install_server.sh
```

This installs Node, MeshCentral, generates fresh certs (bound to the IP in `config.env`), stages the signed agent into `~/lab/files/MeshService64.exe`, opens the firewall, writes the systemd unit, and starts the service.

When it finishes:
1. Open `https://<CONTROLLER_IP>` in a browser (accept the self-signed cert)
2. Create the admin account (FIRST account becomes site admin)
3. Create a device group (e.g. "Lab")
4. Open that group → **Add Agent** → download the **server-keyed agent**
5. Save it as `~/lab/files/MeshService64.exe` (overwrite the generic one — the group-keyed agent will auto-place new devices in this group)

### 4. On each device: create Lab-Admin MANUALLY (one-time, before USB)

Only Lab-Admin is manual — you have to be signed in as some admin to run the elevated script in the first place. INU is created **by** the script.

From an admin PowerShell window on the device:

```
net user Lab-Admin 2026@admin /add
net localgroup Administrators Lab-Admin /add
```

Sign out of whatever first-boot user Windows created, sign back in as **Lab-Admin**, then move to Step 5.

### 5. USB-walk every device with the enrollment script

Plug a USB into each device, run `windows-scripts/01_Enroll-LabDevice.bat` (it self-elevates):

```
01_Enroll-LabDevice.bat
```

The script:
1. **Verifies** Lab-Admin exists + is in Administrators (HARD FAIL if not — go back to Step 4)
2. **Creates INU (password 2026) in Guests** if it doesn't exist; if it does, leaves the password alone but ensures Guests-only group membership (no Users, no Administrators)
3. Deletes every other non-built-in local user (the original first-boot user goes here)
4. Enables WinRM + opens firewall TCP 5985
5. Disables sleep / hibernate / Fast Startup
6. Enables Wake-on-LAN on every UP NIC

After this the device is fully prepared — no other Windows-side script is needed.

Notes:
- The script prints the device's current IP at the end. Write it down + match to a physical label, or use `04_verify_lab.sh` later to dump a labelling table.
- WoL "no software path accepted" in the script output means **that device needs a one-time BIOS visit** to enable WoL — software cannot fix this remotely.

### 6. Set static IPs on every device

Out of scope for the scripts (DHCP-based labs may skip this). If you do go static, **verify with `ipconfig` immediately after** — Windows often silently falls back to APIPA / DHCP if the static binding conflicts with anything.

### 7. Discover + enroll into MeshCentral

```bash
bash ~/lab/02_add_devices.sh
```

This scans the subnet, finds devices not yet in `hosts.ini`, win-pings each as Lab-Admin, and (after a confirmation prompt) runs `playbooks/01_enroll.yml` against the ones that pass auth. The enrollment playbook installs the Mesh Agent, applies the same harden steps as the USB script (idempotent, so this is safe even though they were already applied), and adds successes to `hosts.ini`.

### 8. Verify end-state

```bash
bash ~/lab/04_verify_lab.sh
```

Prints one row per device: reachable / Lab-Admin present / INU in Guests / Mesh Agent running / sleep AC=0 / hibernation off / WoL enabled. Anything that's not "OK" is flagged in an "Action items" block at the bottom.

### 9. Day-to-day from now on

```bash
bash ~/lab/03_check_lab.sh   # quick health snapshot
bash ~/lab/02_add_devices.sh # whenever you add new devices to the floor
bash ~/lab/04_verify_lab.sh  # whenever a device starts behaving oddly
```

---

## Things that bit us before — pre-empted in this build

Each of these has a fix already in the active scripts:

| Problem we hit | Where it's pre-empted |
|---|---|
| `read` hangs when ansible is piped via `tee` | `02_add_devices.sh` uses `read … </dev/tty` |
| Sleep/hibernate scheduled tasks left on devices | `01_enroll.yml` calls `powercfg -h off` and zeros every timeout |
| Fast Startup blocks WoL after shutdown | Same — `powercfg -h off` kills both |
| WoL cmdlet returns "Unsupported" on consumer NICs | `01_enroll.yml` tries cmdlet + advanced-property + 3 driver-level keys; reports per-device which paths accepted |
| NIC reconfig drops WinRM mid-call | WoL task uses `failed_when: false`; the change persists locally regardless of what ansible reports |
| hosts.ini drifts between teammates | `02_add_devices.sh` rewrites it canonically every time it runs |
| Static IP silently falls back to DHCP | Step 5 above — verify with `ipconfig` immediately |
| MAC unknown for devices that have never been online | Acceptable. WoL needs a MAC, and a never-online device can't tell us its MAC. Run `04_verify_lab.sh` or `collect_macs.py` while devices are reachable to bank MACs into `labels.txt` / `macs.txt`. |
| MeshCentral cert tied to one controller IP | Controller IP change → delete `meshcentral/meshcentral-data/` and re-run `01_install_server.sh` (cert regenerates) |
| Mixed-credential transitions | Not an issue for fresh installs; transition scripts moved to `transitions/` |

---

## What the inactive folders contain

- `windows-scripts/inactive_kept_for_reference/` — old lock/unlock/schedule/reset scripts. **Do not use.** Restrictions are now applied via Windows guest-account permissions instead.
- `playbooks/inactive_kept_for_reference/` — superseded enrollment variants and standalone harden/WoL playbooks (now baked into `01_enroll.yml`).
- `transitions/` — `03_switch_to_inu.sh` and friends. Only relevant if migrating a legacy install whose local admin is `labadmin` over to `INU`.
