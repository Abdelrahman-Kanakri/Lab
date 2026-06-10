# INU Lab Remote Management

Centralized control of ~50 Windows lab devices from a Linux (Nobara) controller, using **MeshCentral** (web UI + agent) and **Ansible** (scripted operations).

> **First time setting this up?** Read **[`FRESH_START.md`](FRESH_START.md)** — it walks the full end-to-end install in 8 steps. This README is the reference; `FRESH_START.md` is the recipe.

Files are numbered by **order of use** — `00_*` is teardown, `01_*` first install, `02_*` next, etc.

---

## Folder map

```
~/lab/
├── README.md                              ← reference (you are here)
├── FRESH_START.md                         ← end-of-semester rebuild recipe — START HERE
├── NEXT_SEMESTER.md                       ← restore plan: flip the lab from DHCP back to static IPs next term
├── device_names.md                        ← 46-row table: MeshCentral name ↔ static IP ↔ Windows hostname (source of truth for the restore)
├── .gitignore                             ← keeps runtime + secrets out of git
├── config.env.example                     ← TEMPLATE: cp to config.env, edit, source
├── config.env                             ← (gitignored) your real values — CONTROLLER_IP, password
├── hosts.ini                              ← (gitignored) Ansible inventory, auto-managed
│
├── 00_reset_controller.sh                 ← optional: wipe controller-side state for clean re-install
├── 01_install_server.sh                   ← STEP 1: bootstrap MeshCentral server
├── 02_add_devices.sh                      ← STEP 2: discover + enroll new devices (calls playbooks/01_enroll.yml)
├── 03_check_lab.sh                        ← daily: quick health snapshot
├── 04_verify_lab.sh                       ← end-state checker (one row per device, flags anything off-spec)
├── 04_serve_files.sh                      ← occasional: HTTP server for file pushes
├── collect_macs.py                        ← collect IP/hostname/MAC from every device → labels.txt + macs.txt
├── labels.txt                             ← (gitignored) IP / Hostname / MAC table — print for physical-label walk
├── macs.txt                               ← (gitignored) flat MAC list, one per line, for `wol -f macs.txt`
├── nodes_table.txt                        ← optional: hand-maintained physical position map
│
├── docs/
│   ├── 02_MANAGE_DEVICES.md               ← daily ops (check + add devices)
│   ├── 03_JOBMATE_LINUX.md                ← onboard a Linux teammate
│   ├── 04_JOBMATE_WINDOWS.md              ← onboard a Windows teammate
│   ├── 05_DEVICE_CONFIG.md                ← per-Windows-device config reference
│   ├── 06_CONTROLLER_CONFIG.md            ← Linux controller config reference (config.env, config.json)
│   └── 07_UNREACHABLE_DEVICES.md          ← recover hosts that failed enrollment
│
├── playbooks/
│   ├── 01_enroll.yml                      ← installs Mesh Agent + harden (sleep off, WoL on)
│   ├── 02_verify_agents.yml               ← per-device agent health check
│   ├── 03_uninstall_agents.yml            ← rollback (remove all agents)
│   ├── 04_static_to_dhcp.yml              ← end-of-semester: flip every UP physical NIC back to DHCP (breaks WinRM mid-run by design)
│   └── inactive_kept_for_reference/       ← superseded variants (lock/unlock dance, separate harden, labadmin transition)
│
├── windows-scripts/
│   ├── 01_Enroll-LabDevice.bat (+ .ps1)   ← THE ONLY active Windows-side script — USB-walked once per device
│   └── inactive_kept_for_reference/       ← old lock/unlock/schedule/reset/transition scripts; not part of any active flow
│
├── transitions/
│   └── 03_switch_to_inu.sh                ← only relevant if migrating a legacy labadmin install to INU
│
├── files/
│   ├── README.txt                         ← what gets served from here
│   ├── Harden-LabDevice.ps1               ← internal helper (used by some inactive playbooks for retrofit)
│   ├── Enable-WoL.ps1                     ← internal helper (used by some inactive playbooks for retrofit)
│   └── MeshService64.exe                  ← (gitignored) server-keyed agent, staged by 01_install_server.sh
│
├── meshcentral/                           ← (gitignored) server install + per-controller certs/DB (~580 MB)
└── backups/                               ← (gitignored) created by 00_reset_controller.sh and MeshCentral autobackups
```

> **Why so much is gitignored.** `meshcentral/`, `files/MeshService64.exe`, `hosts.ini`, `macs.txt`, and `config.env` are all per-controller runtime data. The certs and signed agent are bound to ONE specific server identity — sharing them across two installs makes both controllers fight for the same logical devices. The clone-and-go flow regenerates all of it locally, fresh, on whichever box runs `01_install_server.sh`.

---

## Order of operations (active flow)

For a brand-new install, follow [`FRESH_START.md`](FRESH_START.md). The condensed version:

### Controller-side (Linux)
1. `git clone <repo> ~/lab && cd ~/lab`
2. `cp config.env.example config.env` — edit `CONTROLLER_IP`, `LAB_RANGE_START`, `LAB_RANGE_END`, `LAB_ADMIN_PASS`
3. `bash 01_install_server.sh` — installs MeshCentral, generates fresh certs, stages signed agent, starts systemd service
4. Open `https://<CONTROLLER_IP>` → create admin → make a device group → download the **group-keyed** agent → save as `~/lab/files/MeshService64.exe`

### Per-device (USB walk)
5. Run `windows-scripts/01_Enroll-LabDevice.bat` once on each device. It self-elevates and:
   - **prompts you for the student username + password** (use the SAME values on every device), then creates/updates that account in **Guests**
   - deletes every other non-built-in local user (keeps Lab-Admin + the student account)
   - enables WinRM (Automatic, firewall TCP 5985)
   - disables sleep / hibernate / Fast Startup
   - enables Wake-on-LAN on every UP physical NIC

### Bring devices into MeshCentral + finalize harden
6. `bash 02_add_devices.sh` — discovers, win-pings as INU, runs `playbooks/01_enroll.yml` against the ones that pass
7. `bash 04_verify_lab.sh` — confirm every device is fully OK

### Day-to-day
- `bash 03_check_lab.sh` — quick health snapshot anytime
- `bash 02_add_devices.sh` — whenever new devices land on the floor
- `bash 04_verify_lab.sh` — sanity check after any bulk change

---

## Quick reference

| Task | Command |
|---|---|
| Start server | `sudo systemctl start meshcentral` |
| Health snapshot | `bash ~/lab/03_check_lab.sh` |
| End-state checker | `bash ~/lab/04_verify_lab.sh` |
| Enroll new devices | `bash ~/lab/02_add_devices.sh` |
| Web UI | `https://<CONTROLLER_IP>` |
| Tail server logs | `journalctl -u meshcentral -f` |
| Bulk command on all devices | `ansible lab -i ~/lab/hosts.ini -m win_shell -a "Get-Date" --forks 30` |
| Wipe controller for clean re-install | `bash ~/lab/00_reset_controller.sh` |

---

## Conventions

- **Controller IP**: edit in [config.env](config.env)
- **Lab subnet**: derived from `LAB_RANGE_START` in `config.env`
- **Two local accounts** on every device:
  - `Lab-Admin` / `2026@admin` in **Administrators** — created **manually**; ansible connects as this. Keep it identical on every device (it's the single credential in `hosts.ini`).
  - the **student account** in **Guests** — created **by the enrollment script**, which prompts you for the username + password. Default suggestion is `INU` / `2026`, but you choose. **Use the same values on every device** so one set of credentials works lab-wide.
- **Single Windows-side script**: `windows-scripts/01_Enroll-LabDevice.bat` (everything else in `windows-scripts/inactive_kept_for_reference/` is unused)
- **Restrictions**: applied via the student account's Guests-group membership; no scripted lockdown

---

## Gotchas (things that bit us, so they don't bite you)

Each of these has a fix already in the active scripts; they're documented here so you know *why* the scripts look the way they do and what to watch for if you change them.

- **`ansible-playbook | tee` swallows stdin.** Any interactive `read` inside a shell script that pipes ansible output must read from `/dev/tty`: `read -r -p "ok? " ans </dev/tty`. Both `02_add_devices.sh` and `transitions/03_switch_to_inu.sh` already do this.
- **NIC reconfiguration breaks WinRM mid-call.** Anything that touches `Set-NetAdapterPowerManagement` / `Set-NetAdapterAdvancedProperty` can drop the WinRM session before the cmdlet returns. The change persists locally regardless. `playbooks/01_enroll.yml`'s WoL task uses `failed_when: false` to absorb this — re-run is always safe.
- **WoL is two-layer.** PowerShell's `Set-NetAdapterPowerManagement -WakeOnMagicPacket Enabled` returns "Unsupported" on most consumer NIC drivers — that does NOT mean WoL is impossible, only that the cmdlet doesn't expose it. The driver may still accept the equivalent advanced property; the BIOS may need a one-time visit.
- **Fast Startup blocks WoL after a clean shutdown.** Windows Home defaults Fast Startup ON, which hibernates instead of fully powering off — the NIC stays half-asleep. `powercfg -h off` (called in `01_enroll.yml` and the USB enroll script) disables both hibernation and Fast Startup.
- **Static IPs can fail silently.** A device may show "static IP set" in the UI but, if anything conflicts, Windows quietly falls back to APIPA / DHCP. Always verify with `ipconfig` after reassigning.
- **Devices can't be woken until we have their MAC.** A device that's never been online won't appear in `labels.txt` / `macs.txt`. Run `04_verify_lab.sh` or `collect_macs.py` while devices are reachable to bank MACs.
- **MeshCentral certs are bound to one controller IP.** If the controller IP changes, delete `meshcentral/meshcentral-data/` and re-run `01_install_server.sh` — the cert regenerates against the new IP.
- **Mixed-credential transition.** Not an issue for a fresh install. If you ever need to change `LAB_ADMIN_USER` across a populated lab, use `transitions/03_switch_to_inu.sh` — it migrates in two passes and only flips `config.env` after 100% migration.
- **MeshCentral DB is append-only.** Removing a device via the web UI marks it deleted but the DB file keeps growing. Periodic `meshctrl` compaction is fine; for end-of-semester wipes, just run `00_reset_controller.sh` and start fresh.

---

## Numbering convention

- **`00_`** = teardown / pre-install (rare to run)
- **`01_`** = mandatory first step
- **`02_`** = enrollment / day-to-day
- **`03_`** = health checks
- **`04_`** = verification + utilities
- **`inactive_kept_for_reference/`** = superseded files kept on disk but not part of any active flow
- **No prefix** = config files (`config.env`, `hosts.ini`) or library files referenced by other scripts

---

## Documentation

- **[FRESH_START.md](FRESH_START.md)** — the recipe for a clean install
- **[NEXT_SEMESTER.md](NEXT_SEMESTER.md)** — DHCP-to-static restore plan for the start of next semester (uses `device_names.md` as the source of truth)
- **[docs/02_MANAGE_DEVICES.md](docs/02_MANAGE_DEVICES.md)** — day-to-day inventory checks and adding new devices
- **[docs/03_JOBMATE_LINUX.md](docs/03_JOBMATE_LINUX.md)** — onboard a Linux teammate
- **[docs/04_JOBMATE_WINDOWS.md](docs/04_JOBMATE_WINDOWS.md)** — onboard a Windows teammate
- **[docs/05_DEVICE_CONFIG.md](docs/05_DEVICE_CONFIG.md)** — per-Windows-device config reference
- **[docs/06_CONTROLLER_CONFIG.md](docs/06_CONTROLLER_CONFIG.md)** — Linux controller config reference
- **[docs/07_UNREACHABLE_DEVICES.md](docs/07_UNREACHABLE_DEVICES.md)** — triage hosts that fail enrollment
