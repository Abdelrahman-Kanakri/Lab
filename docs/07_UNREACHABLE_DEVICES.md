# Unreachable Devices — Triage & Recovery

When `02_add_devices.sh` finishes, any host that did **not** pass enrollment
(`unreachable=1` or `failed≥1` in the PLAY RECAP) is **kept out of**
`~/lab/hosts.ini` on purpose. This file is your guide to inspecting those
hosts and getting them back into the inventory.

---

## 1. Where the failed list lives

`02_add_devices.sh` writes two files at the end of every run:

| File | Contents |
|---|---|
| `/tmp/lab_enroll_success.txt` | IPs of hosts that enrolled cleanly (already merged into `hosts.ini`) |
| `/tmp/lab_enroll_failed.txt`  | Full PLAY RECAP line for every failed host (NOT in `hosts.ini`) |
| `/tmp/lab_enroll_log.txt`     | Full Ansible playbook output for the whole run |

These files are overwritten on every run, so do your investigation before
re-running the script.

---

## 2. Quick triage commands

### Just the IPs of failed hosts
```bash
awk '{print $1}' /tmp/lab_enroll_failed.txt
```

### Full PLAY RECAP lines, sorted by last octet
```bash
sort -t. -k4 -n /tmp/lab_enroll_failed.txt
```

### Count failures
```bash
wc -l < /tmp/lab_enroll_failed.txt
```

### See exactly what the playbook said about one specific host
Replace `10.3.5.73` with the IP you care about:
```bash
grep -E "10\.3\.5\.73" /tmp/lab_enroll_log.txt
```
For more context (the surrounding TASK that failed):
```bash
grep -nE "TASK \[|10\.3\.5\.73" /tmp/lab_enroll_log.txt | grep -B1 "10\.3\.5\.73"
```

---

## 3. Re-test only the failed hosts

Don't re-scan the whole subnet — build a tiny inventory from the failed list
and run `win_ping` against it.

```bash
source ~/lab/config.env

{
    echo "[retry]"
    awk '{print $1}' /tmp/lab_enroll_failed.txt
    echo ""
    echo "[retry:vars]"
    echo "ansible_user=$LAB_ADMIN_USER"
    echo "ansible_password=$LAB_ADMIN_PASS"
    echo "ansible_connection=winrm"
    echo "ansible_winrm_transport=ntlm"
    echo "ansible_winrm_server_cert_validation=ignore"
    echo "ansible_port=5985"
} > /tmp/retry.ini

ansible retry -i /tmp/retry.ini -m win_ping --forks 20
```

Read the output:

| Symptom | Likely cause |
|---|---|
| `SUCCESS` (works on retry) | Transient — the host was busy or mid-handshake. Just re-run `02_add_devices.sh`. |
| `UNREACHABLE … Read timed out` | Port 5985 is open but WinRM is not answering. The service crashed, or the network profile flipped to "Public". → §5 |
| `UNREACHABLE … connection refused` | WinRM is fully down (service stopped, or firewall closed the port). → §5 |
| `FAILED … access is denied / 401` | `INU` account is missing or password mismatch. → §6 |
| `UNREACHABLE … No route to host` | Host is actually offline / different subnet. → §7 |

---

## 4. Why MeshCentral can reach what WinRM can't

"Unreachable" in the PLAY RECAP means **unreachable via WinRM**. MeshCentral
uses a completely different connection path, so a host that's "unreachable"
to Ansible may still be fully controllable from the MeshCentral web UI.

### The two paths

```
WinRM / Ansible:    Controller  ──TCP 5985──►  Windows device
                    (controller knocks on the device's door — must succeed every time)

MeshCentral agent:  Controller  ◄──TCP 443──   Windows device
                    (device knocks on the controller, keeps the connection open 24/7)
```

The Mesh Agent installed on each device opens a long-lived outbound
WebSocket to the controller. When you click "Terminal" in the web UI,
commands flow **down that already-open tunnel** — no new connection is
made to the device. So nothing that breaks WinRM affects MeshCentral:

- Port 5985 closed? Doesn't matter — Mesh uses 443 outbound.
- WinRM service crashed? Mesh Agent is a separate service.
- Network profile flipped to "Public"? Outbound traffic still works.
- `INU` password wrong / account locked? Mesh runs as `SYSTEM`, no login.

### When MeshCentral works (and when it doesn't)

| Situation | WinRM (Ansible) | MeshCentral (web UI) |
|---|---|---|
| Device was previously enrolled, WinRM now broken | ❌ unreachable | ✅ use Terminal to fix WinRM |
| Device powered off | ❌ | ❌ no outbound connection |
| **Brand-new device, enrollment failed mid-run** | ❌ | ❌ Mesh Agent was never installed |
| Mesh Agent service stopped or uninstalled | ❌ if WinRM also broken | ❌ |
| Device on a different network but can still reach controller on 443 | ❌ | ✅ |

The critical case to recognize: **a brand-new device whose first enrollment
failed has no Mesh Agent yet** — the agent install is exactly what
enrollment was trying to do. You can't recover it through MeshCentral
because there's nothing to phone home. Physical access (re-run
`Enroll-LabDevice.bat` from the USB) is the only path back in.

### Quick check: is the device visible to MeshCentral right now?

```bash
cd ~/lab/meshcentral
node node_modules/meshcentral/meshctrl.js ListDevices --loginuser admin
```

- IP appears with `conn=1` → agent is connected, use the web UI Terminal.
- IP appears with `conn=0` → agent was installed once but is offline now (device powered off, network down, or agent service stopped).
- IP doesn't appear at all → never enrolled. Walk to it.

---

## 5. Fix a host where WinRM is broken (port open but no answer)

This is the most common case. The fastest fix is to bypass WinRM and use
the **MeshCentral agent** as a side channel — if the device was previously
enrolled, Mesh Agent is still running on it (see §4 for why).

### Path A — via MeshCentral web UI (easiest)
1. Open `https://<CONTROLLER_IP>` in your browser (e.g. `https://10.3.5.96`).
2. Log in as `admin`.
3. Click the **Lab** group → click the dead host.
4. **Terminal** tab → **PowerShell**.
5. Run:
   ```powershell
   Enable-PSRemoting -Force
   Restart-Service WinRM
   Set-NetConnectionProfile -NetworkCategory Private
   ```
6. Re-run `~/lab/02_add_devices.sh`. The host will show up as "new" again
   (since it never made it into `hosts.ini`) and re-enroll cleanly.

### Path B — via meshctrl CLI
```bash
cd ~/lab/meshcentral
node node_modules/meshcentral/meshctrl.js Shell \
    --url wss://localhost --loginuser admin --loginpass <ADMIN_PASS> \
    --id <DEVICE_NODE_ID> \
    --run "Enable-PSRemoting -Force; Restart-Service WinRM"
```
Get `<DEVICE_NODE_ID>` from `… meshctrl.js ListDevices`.

### Path C — physical access
If Mesh Agent is also dead, you'll have to walk to the machine. Plug in the
USB and re-run `Enroll-LabDevice.bat` — it resets WinRM, the firewall rule,
and the `INU` account in one shot.

---

## 6. Fix a host where authentication fails (401 / access denied)

The `INU` account is either missing, has the wrong password, or got
locked out. Walk to the device (or use MeshCentral terminal) and run:

```powershell
$pass = ConvertTo-SecureString "2026" -AsPlainText -Force

if (Get-LocalUser -Name INU -ErrorAction SilentlyContinue) {
    Set-LocalUser -Name INU -Password $pass
} else {
    New-LocalUser -Name INU -Password $pass -PasswordNeverExpires -AccountNeverExpires
    Add-LocalGroupMember -Group "Administrators" -Member INU
}
```

Then re-run `~/lab/02_add_devices.sh`.

> If you've changed `LAB_ADMIN_PASS` in `config.env`, use that value here
> instead of `2026`.

---

## 7. Fix a host that's actually offline

Sanity-check it's powered on and on the lab network:

```bash
# ICMP ping (works only if the device's firewall allows it — many lab hosts don't)
ping -c 2 <IP>

# Layer-4 check on WinRM port (the same check 02_add_devices.sh uses)
timeout 3 bash -c "echo > /dev/tcp/<IP>/5985" && echo open || echo closed

# Check if it's responding on ANY common Windows port
for p in 135 139 445 3389 5985; do
    timeout 1 bash -c "echo > /dev/tcp/<IP>/$p" 2>/dev/null && echo "$p open"
done
```

If nothing answers, the device is genuinely off, asleep, on a different
subnet, or has been re-imaged with a different IP. Track it down by MAC:

```bash
# Force the lab subnet's ARP cache to refresh
nmap -sn $(echo $LAB_RANGE_START | cut -d. -f1-3).0/24 >/dev/null
arp -an | grep -i "<MAC>"
```

---

## 8. After the fix — verify

Once you think a host is back, prove it before re-running the enrollment
script:

```bash
ansible <IP> -i /tmp/retry.ini -m win_ping
```

Expected: `SUCCESS => { "ping": "pong" }`. If you get that, then:

```bash
~/lab/02_add_devices.sh
```

Pick `y` at the confirm prompt, watch the PLAY RECAP — the previously dead
hosts should now show `unreachable=0  failed=0` and land in `hosts.ini`.

Confirm with the health check:
```bash
~/lab/03_check_lab.sh
```

---

## 9. Common root causes — quick reference

| Cause | What you'll see in retry | Fix |
|---|---|---|
| WinRM service crashed | `Read timed out` | §5 — `Restart-Service WinRM` |
| Network profile flipped to "Public" | `Read timed out` or refused | §5 — `Set-NetConnectionProfile -NetworkCategory Private` |
| Machine doing heavy Windows Update | Times out, then works later | Wait 30 min, retry |
| Firewall rule deleted | Connection refused on 5985 | Re-run `Enroll-LabDevice.bat` |
| `INU` account renamed/deleted | 401 access denied | §6 |
| `INU` password rotated on device only | 401 access denied | §6 with current password |
| Host re-imaged | New MAC, possibly new IP | §7 — find by MAC |
| Host genuinely offline | All ports closed | Power on the box |
| **Brand-new device, first enrollment failed** | Any error in Step 5 | §4 — Mesh Agent isn't installed yet, walk to device with USB |

---

## 10. See also

- **[02_MANAGE_DEVICES.md](02_MANAGE_DEVICES.md)** — day-to-day check + add workflow
- **[05_DEVICE_CONFIG.md](05_DEVICE_CONFIG.md)** — what a clean device looks like (use this to know what "broken" means)
- **[06_CONTROLLER_CONFIG.md](06_CONTROLLER_CONFIG.md)** — controller-side settings, including `LAB_ADMIN_USER` / `LAB_ADMIN_PASS`
