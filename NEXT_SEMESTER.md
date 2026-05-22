# Next-Semester Restore — Static IP Reassignment

Resume point after the 2025–26 semester. The lab was running on static IPs
`10.3.8.2`–`10.3.8.48` (44 active devices) but has since drifted to DHCP on
the controller's own subnet (`10.3.5.x`). When you come back next semester,
this is what you need to know to put it back on static.

---

## 1. State at the end of this semester (2026-05-20)

| What | Where it stands |
|---|---|
| Controller IP | `10.3.5.96/16` on `enp44s0` (see `config.env`) |
| Lab subnet (intended) | `10.3.8.0/24` (per `config.env` `LAB_RANGE_START`) |
| Lab subnet (actual) | Devices are on **DHCP-assigned `10.3.5.x` leases**, not `10.3.8.x` |
| `hosts.ini` | **STALE** — lists 44 IPs on `10.3.8.x` that no longer answer |
| `device_names.md` | Up-to-date snapshot of `MeshCentral name → static 10.3.8.x IP → Windows hostname` for all 46 devices |
| MeshCentral DB | Knows all 46 devices; `host` field per node = last-reported DHCP IP on `10.3.5.x` |
| Devices physically | Powered on, reachable on `10.3.5.x` via WinRM (sampled 5/5 OPEN on port 5985) |

### What we discovered mid-session

- Asked Ansible to flip static→DHCP via `playbooks/04_static_to_dhcp.yml`.
- Every host failed with `[Errno 113] No route to host` on `10.3.8.x` —
  not because Ansible couldn't talk to WinRM, but because nothing on the
  lab is on `10.3.8.x` anymore.
- MeshCentral's `host` field confirmed it: every device's last contact was
  from a `10.3.5.x` address.
- Conclusion: the static→DHCP flip has effectively already happened (likely
  Windows updates / image reset wiped the static binding at some point;
  none of our scripts in the active flow assigned static IPs — that was
  always documented as "out of scope, set manually" in `FRESH_START.md` §6).
- Only exception: device named `27` still shows `10.3.8.28` as its host.
  Either it kept its static binding, or it hasn't reconnected since the
  drift. Treat as a one-off when restoring.

---

## 2. The mapping you'll restore from

Source of truth for "this device gets this IP":

- **`~/lab/device_names.md`** — 46-row table. The `MeshCentral name` column
  is the human-friendly name (1, 2, 3, …, 47, with 32 missing because
  `10.3.8.33` was never enrolled). The `IP` column is the static IP that
  the named device had. The `Windows hostname` column (`DESKTOP-XXXX`) is
  what helps you physically identify the box if names ever desync.
- Naming convention: `name i ↔ IP 10.3.8.(i+1)`. Holds for every row.
- Missing octets in the static range: `.28`, `.33`, `.42` (`.28` and `.42`
  exist in MeshCentral but were never in `hosts.ini`; `.33` was never used).

If `device_names.md` ever gets lost, regenerate it from the MeshCentral DB:

```bash
python3 <<'PY'
import json, pathlib, re
db = pathlib.Path.home() / 'lab/meshcentral/meshcentral-data/meshcentral.db'
latest = {}
for line in db.read_text(errors='replace').splitlines():
    try: r = json.loads(line)
    except: continue
    if r.get('type') == 'node' and r.get('_id'):
        if r.get('$$deleted'): latest.pop(r['_id'], None)
        else: latest[r['_id']] = r
rows = []
for r in latest.values():
    m = re.search(r'10\.3\.\d+\.\d+', r.get('host',''))
    if m: rows.append((m.group(0), r.get('name','?'), r.get('rname','?')))
rows.sort(key=lambda t: tuple(int(p) for p in t[0].split('.')))
md = ["# Lab Device Names", "", f"{len(rows)} devices.", "",
      "| MeshCentral name | IP | Windows hostname |", "|---|---|---|"]
for ip, name, rname in rows:
    md.append(f"| {name} | {ip} | {rname} |")
(pathlib.Path.home() / 'lab/device_names.md').write_text("\n".join(md) + "\n")
PY
```

---

## 3. Restore plan (start of next semester)

### Step 0 — Rebuild / refresh the inventory against the current (DHCP) subnet

`hosts.ini` is stale right now — it lists `10.3.8.x` IPs that nothing
answers on, because the devices live on DHCP-assigned `10.3.5.x` leases.
You can't push static IPs back until Ansible can actually reach them, so
the very first thing to do is refresh the inventory against where the
devices ACTUALLY are today.

```bash
source ~/lab/config.env

# 1. Point config.env at the current (DHCP) subnet — usually 10.3.5.x
sed -i 's|^export LAB_RANGE_START=.*|export LAB_RANGE_START="10.3.5.1"|' ~/lab/config.env
sed -i 's|^export LAB_RANGE_END=.*|export LAB_RANGE_END="10.3.5.254"|'   ~/lab/config.env
source ~/lab/config.env

# 2. Wipe the stale hosts.ini so 02_add_devices.sh treats everything as new
> ~/lab/hosts.ini

# 3. Re-discover the entire fleet on the current subnet.
#    02_add_devices.sh scans /24, win_pings each found host, runs
#    playbooks/01_enroll.yml on auth-OK hosts, merges them in.
#    The enrollment playbook is idempotent — running it again on already-
#    enrolled devices does nothing harmful.
bash ~/lab/02_add_devices.sh

# 4. Sanity check: every device should now show OK across the board
bash ~/lab/04_verify_lab.sh
```

If `02_add_devices.sh` finds fewer than 46 hosts, the missing ones are
either powered off, on a different subnet, or have been re-imaged and lost
the `INU` credential. Triage per `docs/07_UNREACHABLE_DEVICES.md`.

> **Why not just rebuild from MeshCentral's last-known IPs?** Faster, but
> the IPs in the DB are from the agents' last phone-home — they may have
> expired or been re-leased over the break. The full subnet scan in step 3
> is the authoritative source.

### Step 1 — Match each DHCP IP back to its intended static IP

This is the part that needs the `device_names.md` mapping. There are two
join keys:

- **MAC address** — most reliable. Match `Mesh `rname` / hostname` →
  device's MAC → assign the static IP from `device_names.md`.
- **MeshCentral name** — works if names didn't change. The Mesh display
  name carries from old DB through to new lease.

Quick way to get DHCP IP → Mesh name → intended static IP:

```bash
python3 <<'PY'
import json, pathlib, re
db = pathlib.Path.home() / 'lab/meshcentral/meshcentral-data/meshcentral.db'
latest = {}
for line in db.read_text(errors='replace').splitlines():
    try: r = json.loads(line)
    except: continue
    if r.get('type') == 'node' and r.get('_id'):
        if r.get('$$deleted'): latest.pop(r['_id'], None)
        else: latest[r['_id']] = r
print(f"{'Name':6s} {'DHCP IP (now)':16s} {'Intended static IP':18s} Hostname")
print('-'*70)
for r in sorted(latest.values(), key=lambda r: int(r.get('name','0')) if r.get('name','').isdigit() else 999):
    name = r.get('name','?')
    dhcp = r.get('host','?')
    try:
        n = int(name)
        intended = f"10.3.8.{n+1}"
    except: intended = '?'
    print(f"{name:6s} {dhcp:16s} {intended:18s} {r.get('rname','?')}")
PY
```

### Step 2 — Push static IPs back via Ansible

This is the part that's out of scope today (lab is unreachable for testing),
but the playbook shape is:

```yaml
# playbooks/05_dhcp_to_static.yml  (write this when you're ready)
- hosts: lab
  gather_facts: false
  vars:
    # Build a per-host map IP -> intended_static somewhere (group_vars,
    # host_vars, or inline lookup against device_names.md)
    intended_static: "{{ static_ip_map[inventory_hostname] }}"
    gateway: "10.3.8.1"   # set to the lab's actual gateway when restored
    dns:     "10.3.8.1"   # or your real DNS
    prefix:  24

  tasks:
    - name: Set static IP on the UP physical NIC
      win_shell: |
        $nic = Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Select -First 1
        Remove-NetIPAddress -InterfaceAlias $nic.Name -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetRoute     -InterfaceAlias $nic.Name -Confirm:$false -ErrorAction SilentlyContinue
        Set-NetIPInterface  -InterfaceAlias $nic.Name -Dhcp Disabled
        New-NetIPAddress    -InterfaceAlias $nic.Name -IPAddress {{ intended_static }} `
                            -PrefixLength {{ prefix }} -DefaultGateway {{ gateway }}
        Set-DnsClientServerAddress -InterfaceAlias $nic.Name -ServerAddresses {{ dns }}
      failed_when: false   # WinRM will drop the second the IP changes
      changed_when: true
```

The same gotchas as today's flip apply in reverse:

- WinRM session drops the instant the new IP binds. `failed_when: false`
  absorbs that — the change persists locally.
- After the run, every host's WinRM IP changes from `10.3.5.x` (DHCP) to
  `10.3.8.x` (static), so `hosts.ini` becomes stale immediately. Rebuild
  it from `device_names.md` directly rather than scanning, since the
  controller is on `10.3.5.96/16` and can route to `10.3.8.x` (verified
  with `ip route get 10.3.8.2` today).
- **Verify with `ipconfig` after every flip** — Windows silently falls
  back to APIPA if the static binding conflicts. This is documented in
  `FRESH_START.md` §6 ("Static IPs can fail silently").
- Don't trust `Mesh name` alone if the lab was re-imaged over the break —
  re-imaged machines will lose their Mesh node identity. Use MAC matching
  if `device_names.md` includes MACs (regenerate with
  `collect_macs.py` first if not).

### Step 3 — Verify

```bash
# Update config.env back to the lab subnet
sed -i 's|^export LAB_RANGE_START=.*|export LAB_RANGE_START="10.3.8.1"|' ~/lab/config.env
sed -i 's|^export LAB_RANGE_END=.*|export LAB_RANGE_END="10.3.8.254"|'   ~/lab/config.env

# Rebuild hosts.ini against the restored static range
bash ~/lab/02_add_devices.sh

# Confirm fleet state
bash ~/lab/04_verify_lab.sh
```

---

## 4. Artifacts created this session

- `~/lab/device_names.md` — 46-row name/IP/hostname table (the source of truth for the restore)
- `~/lab/playbooks/04_static_to_dhcp.yml` — the flip-to-DHCP playbook that turned out to be unnecessary. Kept on disk as a working reference for the reverse direction.
- `~/lab/NEXT_SEMESTER.md` — this file

## 5. What did NOT change

- No device was actually modified by `04_static_to_dhcp.yml` — every task
  failed at the network layer before reaching WinRM.
- `config.env` still points at the `10.3.8.x` subnet.
- `hosts.ini` still lists the old `10.3.8.x` IPs (stale, but harmless until
  the next time you try to run something against it).
- MeshCentral keeps working end-to-end — agents reconnect outbound on 443
  regardless of WinRM/IP changes.

## 6. Open question for next semester

Device `27` (last seen on `10.3.8.28`) — did it keep its static binding,
or has it just been offline? If still on static, it's a one-off to deal
with first (either leave it as the only static device, or remote into it
via Mesh and flip it to DHCP so the whole fleet starts from the same baseline).
