# INU Lab Remote Management

Centralized control of 50 Windows lab devices from a Linux (Nobara) controller, using **MeshCentral** (web UI + agent) and **Ansible** (scripted operations).

Files are numbered by **order of use** — `01_*` first, `02_*` next, etc.

---

## Folder map (in order of use)

```
~/lab/
├── README.md                              ← you are here
├── config.env                             ← edit this ONCE (CONTROLLER_IP)
├── hosts.ini                              ← Ansible inventory (auto-managed)
│
├── 01_install_server.sh                   ← STEP 1: bootstrap MeshCentral server
├── 02_add_devices.sh                      ← STEP 2: discover + enroll new devices
├── 03_check_lab.sh                        ← daily: health snapshot
├── 04_serve_files.sh                      ← occasional: HTTP server for file pushes
│
├── docs/
│   ├── 01_IMPLEMENTATION.md               ← full step-by-step build guide
│   ├── 02_MANAGE_DEVICES.md               ← daily ops (check + add devices)
│   ├── 03_JOBMATE_LINUX.md                ← onboard a Linux teammate
│   └── 04_JOBMATE_WINDOWS.md              ← onboard a Windows teammate
│
├── playbooks/
│   ├── 01_enroll_with_unlock.yml          ← MAIN: handles locked devices
│   ├── 02_verify_agents.yml               ← check agent status everywhere
│   ├── 03_enroll_meshcentral.yml          ← alt: simpler, only for unlocked devices
│   └── 04_uninstall_agents.yml            ← rollback (remove all agents)
│
├── windows-scripts/                       ← copy this whole folder to USB
│   ├── 01_Enroll-LabDevice.bat (+ .ps1)   ← FIRST on every device — creates labadmin/2026 + WinRM
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
│   └── meshagent.exe                      ← MeshCentral agent (server-keyed)
│
├── meshcentral/                           ← server install (~580 MB)
└── backups/
```

---

## Order of operations

### First-time setup (Linux controller)
1. Edit `config.env` — set `CONTROLLER_IP`
2. Run `01_install_server.sh` — installs and starts MeshCentral
3. Open `https://<CONTROLLER_IP>` → create admin → make `Lab` group → download `meshagent.exe` to `files/`

### First-time setup (each lab device, physical)
1. USB → run `windows-scripts/01_Enroll-LabDevice.bat` — creates labadmin + WinRM
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
- **[LAB_DAY_CHECKLIST.md](LAB_DAY_CHECKLIST.md)** — original on-site checklist (kept for reference)
- **[MESHCENTRAL_SETUP.md](MESHCENTRAL_SETUP.md)** — original MeshCentral reference (kept for reference)

---

## Conventions

- **Controller IP**: `10.3.5.96` — edit in [config.env](config.env)
- **Lab subnet**: `10.3.5.0/24`
- **Local admin on every lab device**: `labadmin` / password `2026`
- **Lockdown signal**: registry key `HKLM:\SOFTWARE\LabPolicy\StudentLock`, `Locked=1` means hardened

---

## Convention for the numbering

- **`01_` to `04_`** in root = the 4 entry-point shell scripts in usage order
- **`01_` to `04_`** in `docs/` = read in this order to learn the system
- **`01_` to `04_`** in `playbooks/` = `01` is what you run most; `04` is rollback
- **`01_` to `07_`** in `windows-scripts/` = `01` mandatory; `02–04` typical setup; `05–07` maintenance/alternatives
- **`legacy/`** = superseded files kept for reference, not used in current flow
- **No prefix** = config files (`config.env`, `hosts.ini`) or files referenced by other scripts
