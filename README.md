# INU Lab Remote Management

Centralized control of 50 Windows lab devices from a Linux (Nobara) controller, using **MeshCentral** (web UI + agent) and **Ansible** (scripted operations).

Files are numbered by **order of use** — `01_*` first, `02_*` next, etc.

---

## Folder map (in order of use)

```
~/lab/
├── README.md                              ← you are here
├── .gitignore                             ← keeps runtime + secrets out of git
├── config.env.example                     ← TEMPLATE: cp to config.env, edit, source
├── config.env                             ← (gitignored) your real values — CONTROLLER_IP, password
├── hosts.ini                              ← (gitignored) Ansible inventory, auto-managed
│
├── 01_install_server.sh                   ← STEP 1: bootstrap MeshCentral server
├── 02_add_devices.sh                      ← STEP 2: discover + enroll new devices
├── 03_check_lab.sh                        ← daily: health snapshot
├── 04_serve_files.sh                      ← occasional: HTTP server for file pushes
├── collect_macs.py                        ← collect MACs over WinRM → macs.txt (for WoL)
├── macs.txt                               ← (gitignored) generated, one MAC per line
│
├── docs/
│   ├── 01_IMPLEMENTATION.md               ← full step-by-step build guide
│   ├── 02_MANAGE_DEVICES.md               ← daily ops (check + add devices)
│   ├── 03_JOBMATE_LINUX.md                ← onboard a Linux teammate
│   ├── 04_JOBMATE_WINDOWS.md              ← onboard a Windows teammate
│   ├── 05_DEVICE_CONFIG.md                ← per-Windows-device config reference
│   ├── 06_CONTROLLER_CONFIG.md            ← Linux controller config reference (config.env, config.json)
│   └── 07_UNREACHABLE_DEVICES.md          ← recover hosts that failed enrollment
│
├── playbooks/
│   ├── 01_enroll_with_unlock.yml          ← MAIN: handles locked devices
│   ├── 02_verify_agents.yml               ← check agent status everywhere
│   ├── 03_enroll_meshcentral.yml          ← alt: simpler, only for unlocked devices
│   └── 04_uninstall_agents.yml            ← rollback (remove all agents)
│
├── windows-scripts/                       ← copy this whole folder to USB
│   ├── 01_Enroll-LabDevice.bat (+ .ps1)   ← FIRST on every device — creates INU/2026 + WinRM
│   ├── 02_Run-Lock.bat (+ Lock-StudentDevice.ps1)              ← apply lockdown
│   ├── 03_Run-ScheduleSleepSetup.bat (+ Setup-SleepSchedule.ps1) ← 08:00 wake / 16:00 sleep
│   ├── 04_Run-ResetPasswords.bat (+ Reset-Passwords.ps1)        ← unify all-user passwords
│   ├── 05_Run-Unlock.bat (+ Unlock-StudentDevice.ps1)           ← maintenance: lift restrictions
│   ├── 06_Run-ScheduleRemove.bat (+ Remove-ShutdownSchedule.ps1) ← maintenance: clear schedule
│   ├── 07_Run-ScheduleSetup.bat (+ Setup-ShutdownSchedule.ps1)  ← alt to 03 (force shutdown vs sleep)
│   └── legacy/                            ← old Digispark bootstrap, superseded by 01
│       ├── bootstrap.ps1
│       ├── runPS1.bat
│       ├── bootstrap_v2.ps1
│       └── Enable-WinRM.bat
│
├── files/
│   ├── README.txt                         ← what gets served from here
│   └── MeshService64.exe                  ← (gitignored) server-keyed agent, staged by installer
│
├── meshcentral/                           ← (gitignored) server install + per-controller certs/DB (~580 MB)
└── backups/                               ← (gitignored) MeshCentral autobackups
```

> **Why so much is gitignored.** `meshcentral/`, `files/MeshService64.exe`, `hosts.ini`,
> `macs.txt`, and `config.env` are all per-controller runtime data. The certs and
> signed agent are bound to ONE specific server identity — sharing them across
> two installs makes both controllers fight for the same logical devices.
> The clone-and-go flow regenerates all of it locally, fresh, on whichever box
> runs `01_install_server.sh`.

---

## Order of operations

### First-time setup (Linux controller, on a fresh clone)
1. `git clone <repo> ~/lab && cd ~/lab`
2. `cp config.env.example config.env` — then edit `config.env` and set
   `CONTROLLER_IP`, `LAB_RANGE_START`, `LAB_RANGE_END`, and pick a `LAB_ADMIN_PASS`
3. Run `bash 01_install_server.sh` — installs MeshCentral, generates fresh certs,
   stages the signed agent into `files/`, opens firewall, starts the systemd service
4. Open `https://<CONTROLLER_IP>` → create admin → make `Lab` group

### First-time setup (each lab device, physical)
1. USB → run `windows-scripts/01_Enroll-LabDevice.bat` — creates INU + WinRM
2. (Optional) USB → `02_Run-Lock.bat` — apply lockdown
3. (Optional) USB → `03_Run-ScheduleSleepSetup.bat` — set sleep schedule

### Bring devices into MeshCentral
4. Back on Linux: run `02_add_devices.sh` — auto-enrolls everything new

### Day-to-day
- `03_check_lab.sh` — health snapshot anytime
- `02_add_devices.sh` — after adding new devices to the floor

---

## Quick reference

| Task | Command |
|---|---|
| Start server | `sudo systemctl start meshcentral` |
| Health snapshot | `~/lab/03_check_lab.sh` |
| Enroll new devices | `~/lab/02_add_devices.sh` |
| Web UI | `https://<CONTROLLER_IP>` (currently `https://10.3.5.96`) |
| Tail server logs | `journalctl -u meshcentral -f` |
| Bulk command on all devices | `ansible lab -i ~/lab/hosts.ini -m win_shell -a "Get-Date" --forks 50` |

---

## Documentation

- **[docs/01_IMPLEMENTATION.md](docs/01_IMPLEMENTATION.md)** — complete step-by-step build, including customization (Phase 7: changing IP / port / subnet)
- **[docs/02_MANAGE_DEVICES.md](docs/02_MANAGE_DEVICES.md)** — day-to-day inventory checks and adding new devices
- **[docs/03_JOBMATE_LINUX.md](docs/03_JOBMATE_LINUX.md)** — onboard a Linux teammate
- **[docs/04_JOBMATE_WINDOWS.md](docs/04_JOBMATE_WINDOWS.md)** — onboard a Windows teammate
- **[docs/05_DEVICE_CONFIG.md](docs/05_DEVICE_CONFIG.md)** — per-Windows-device config reference (every setting on a clean lab device)
- **[docs/06_CONTROLLER_CONFIG.md](docs/06_CONTROLLER_CONFIG.md)** — Linux controller config reference (config.env, systemd, MeshCentral config.json, firewall)
- **[docs/07_UNREACHABLE_DEVICES.md](docs/07_UNREACHABLE_DEVICES.md)** — triage and recover hosts that fail enrollment (`unreachable=1` / `failed≥1`)
- **[LAB_DAY_CHECKLIST.md](LAB_DAY_CHECKLIST.md)** — original on-site checklist (kept for reference)
- **[MESHCENTRAL_SETUP.md](MESHCENTRAL_SETUP.md)** — original MeshCentral reference (kept for reference)

---

## Conventions

- **Controller IP**: `10.3.5.96` — edit in [config.env](config.env)
- **Lab subnet**: `10.3.5.0/24`
- **Local admin on every lab device**: `INU` / password `2026`
- **Lockdown signal**: registry key `HKLM:\SOFTWARE\LabPolicy\StudentLock`, `Locked=1` means hardened

---

## Convention for the numbering

- **`01_` to `04_`** in root = the 4 entry-point shell scripts in usage order
- **`01_` to `04_`** in `docs/` = read in this order to learn the system
- **`01_` to `04_`** in `playbooks/` = `01` is what you run most; `04` is rollback
- **`01_` to `07_`** in `windows-scripts/` = `01` mandatory; `02–04` typical setup; `05–07` maintenance/alternatives
- **`legacy/`** = superseded files kept for reference, not used in current flow
- **No prefix** = config files (`config.env`, `hosts.ini`) or files referenced by other scripts
