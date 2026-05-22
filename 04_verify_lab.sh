#!/usr/bin/env bash
# 04_verify_lab.sh — single end-state checker.
#
# Reaches every device in hosts.ini and prints one row per device showing:
#   - reachable?
#   - INU local admin present?
#   - Mesh Agent service running?
#   - sleep + hibernate disabled?
#   - WoL state (cmdlet level — driver/BIOS may add more)
#
# Run after every onboarding session, after every harden, after re-installs.
# Anything that's not "OK" stands out at a glance.
#
# Usage:
#   bash 04_verify_lab.sh

set -euo pipefail
source "$(dirname "$0")/config.env"

OUT="/tmp/lab_verify_raw.txt"
ADMIN_USER="${LAB_ADMIN_USER:-Lab-Admin}"   # whichever local admin ansible uses
GUEST_USER="INU"                            # always INU regardless of admin flavour

echo "================================================================"
echo "  Lab end-state check"
echo "================================================================"
echo ""
echo "Probing $(grep -cE '^10\.' ~/lab/hosts.ini || echo 0) devices..."
echo ""

# One PowerShell payload per device — collects everything in a single line.
ansible lab -i ~/lab/hosts.ini -m win_shell -a "
    \$admin = if ((Get-LocalUser '${ADMIN_USER}' -ErrorAction SilentlyContinue) -and (Get-LocalGroupMember -Group Administrators -ErrorAction SilentlyContinue | Where-Object Name -match '\\\\${ADMIN_USER}\$')) { 'yes' } else { 'no' }
    \$inu   = if ((Get-LocalUser '${GUEST_USER}' -ErrorAction SilentlyContinue) -and (Get-LocalGroupMember -Group Guests         -ErrorAction SilentlyContinue | Where-Object Name -match '\\\\${GUEST_USER}\$')) { 'yes' } else { 'no' }
    \$svc = (Get-Service 'Mesh Agent' -ErrorAction SilentlyContinue).Status
    \$sleep_ac = (powercfg /q SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | Select-String 'Current AC').Line -replace '.*0x','0x'
    \$hib = (powercfg /a | Select-String -Pattern 'Hibernation has not been enabled' -Quiet)
    \$nic = Get-NetAdapter -Physical | Where-Object Status -eq Up | Select-Object -First 1
    \$wol = if (\$nic) { (Get-NetAdapterPowerManagement -Name \$nic.Name).WakeOnMagicPacket } else { 'no-nic' }
    \"ADMIN=\$admin INU=\$inu MESH=\$svc SLEEP_AC=\$sleep_ac HIB_OFF=\$hib WOL=\$wol\"
" --forks 30 2>&1 > "$OUT"

# Parse + tabulate
python3 <<PY
import re
with open("$OUT") as f: text = f.read()
rows = []
for ip, status, body in zip(*[iter(re.split(r'^(10\.\d+\.\d+\.\d+) \| (CHANGED|SUCCESS|UNREACHABLE|FAILED)', text, flags=re.M)[1:])]*3):
    if status in ('UNREACHABLE','FAILED'):
        rows.append((ip, '!', '-', '-', '-', '-', '-', '-')); continue
    line = body.strip().split('\n')[1] if '\n' in body.strip() else body.strip()
    fields = dict(p.split('=', 1) for p in line.split() if '=' in p)
    rows.append((ip, 'OK',
        fields.get('ADMIN','?'),
        fields.get('INU','?'),
        fields.get('MESH','?'),
        fields.get('SLEEP_AC','?'),
        fields.get('HIB_OFF','?'),
        fields.get('WOL','?'),
    ))

rows.sort(key=lambda r: tuple(int(p) for p in r[0].split('.')))

print(f"{'IP':14s} {'Reach':5s} {'${ADMIN_USER}':${#ADMIN_USER}s} {'${GUEST_USER}':${#GUEST_USER}s} {'Mesh':9s} {'SleepAC':10s} {'HibOff':6s} {'WoL':12s}")
print('-'*78)
ok_all = 0
for ip, reach, adm, inu, mesh, slp, hib, wol in rows:
    full_ok = (reach == 'OK' and adm == 'yes' and inu == 'yes' and mesh == 'Running' and slp == '0x00000000' and hib == 'True')
    if full_ok: ok_all += 1
    flag = '  ' if full_ok else '!!'
    print(f"{flag} {ip:11s} {reach:5s} {adm:5s} {inu:4s} {mesh:9s} {slp:10s} {hib:6s} {wol}")
print()
print(f"Fully-OK devices: {ok_all} / {len(rows)}")

bad = [r for r in rows if not (r[1] == 'OK' and r[2] == 'yes' and r[3] == 'yes' and r[4] == 'Running' and r[5] == '0x00000000' and r[6] == 'True')]
if bad:
    print()
    print("Action items:")
    for ip, reach, adm, inu, mesh, slp, hib, wol in bad:
        why = []
        if reach != 'OK':                     why.append('unreachable')
        else:
            if adm  != 'yes':                 why.append('Lab-Admin missing or not in Administrators')
            if inu  != 'yes':                 why.append('INU missing or not in Guests')
            if mesh != 'Running':             why.append(f'Mesh Agent {mesh or "missing"}')
            if slp  != '0x00000000':          why.append(f'sleep_ac={slp}')
            if hib  != 'True':                why.append('hibernation still on')
            if wol  not in ('Enabled',):      why.append(f'WoL={wol}')
        print(f"  {ip}: {', '.join(why)}")
PY
