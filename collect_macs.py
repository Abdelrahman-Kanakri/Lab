#!/usr/bin/env python3
"""
collect_macs.py — collect IP / hostname / MAC from every lab device via WinRM.

Reads hosts from ~/lab/hosts.ini, queries each over WinRM (NTLM), and writes:
  - ~/lab/labels.txt    table form, columns: IP  Hostname  MAC1[, MAC2…]
                        sorted by IP — print this for physical-label walks
  - ~/lab/macs.txt      one MAC per line, suitable for `wol -f macs.txt`

Usage:
  source ~/lab/config.env && python3 ~/lab/collect_macs.py

The script tries each device with the configured LAB_ADMIN_USER (Lab-Admin
for the post-fresh-install setup). Devices that are powered off or whose
WinRM credentials don't match are reported in a "FAILED" block so you know
exactly which IPs need attention.
"""

import os
import re
import sys
import winrm
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

HOSTS_INI  = Path.home() / "lab" / "hosts.ini"
LABELS_OUT = Path.home() / "lab" / "labels.txt"
MACS_OUT   = Path.home() / "lab" / "macs.txt"
USER       = os.environ.get("LAB_ADMIN_USER", "Lab-Admin")
PASSWORD   = os.environ.get("LAB_ADMIN_PASS", "2026@admin")
PORT       = 5985
THREADS    = 20

# Single PowerShell call returns three lines: HOST=, IP=, MACS=
POWERSHELL = r"""
$nics = Get-NetAdapter -Physical | Where-Object Status -eq 'Up'
$macs = ($nics | Select-Object -ExpandProperty MacAddress) -join ','
$ip   = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
         Where-Object { $_.InterfaceAlias -in $nics.Name }).IPAddress -join ','
"HOST=$($env:COMPUTERNAME)"
"IP=$ip"
"MACS=$macs"
"""

def load_hosts(ini_path: Path) -> list[str]:
    hosts = []
    in_section = False
    for line in ini_path.read_text().splitlines():
        line = line.strip()
        if line == "[lab]":
            in_section = True
            continue
        if line.startswith("["):
            in_section = False
            continue
        if in_section and re.match(r"^\d+\.\d+\.\d+\.\d+$", line):
            hosts.append(line)
    return hosts


def probe(host: str) -> tuple[str, dict | None, str]:
    try:
        session = winrm.Session(
            f"http://{host}:{PORT}/wsman",
            auth=(USER, PASSWORD),
            transport="ntlm",
            server_cert_validation="ignore",
        )
        result = session.run_ps(POWERSHELL)
        if result.status_code != 0:
            return host, None, result.std_err.decode(errors="replace").strip()[:120]
        out = result.std_out.decode(errors="replace")
        fields = {}
        for ln in out.splitlines():
            if "=" in ln:
                k, v = ln.split("=", 1)
                fields[k.strip()] = v.strip()
        macs = [
            m.strip().replace("-", ":").upper()
            for m in fields.get("MACS", "").split(",")
            if re.match(r"([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}", m.strip())
        ]
        return host, {
            "hostname": fields.get("HOST", "?"),
            "ip_reported": fields.get("IP", "?"),
            "macs": macs,
        }, ""
    except Exception as exc:
        return host, None, str(exc)[:120]


def main():
    if not HOSTS_INI.exists():
        sys.exit(f"ERROR: {HOSTS_INI} not found — run 02_add_devices.sh first.")

    hosts = load_hosts(HOSTS_INI)
    if not hosts:
        sys.exit("ERROR: no hosts found in [lab] section of hosts.ini")

    print(f"Collecting IP/hostname/MAC from {len(hosts)} devices "
          f"as user '{USER}' ({THREADS} threads)...")

    results: dict[str, dict] = {}
    failed: list[tuple[str, str]] = []

    with ThreadPoolExecutor(max_workers=THREADS) as pool:
        futures = {pool.submit(probe, h): h for h in hosts}
        for future in as_completed(futures):
            host, data, err = future.result()
            if data:
                results[host] = data
            else:
                failed.append((host, err))

    # Sort by last-octet for human readability
    def ipkey(ip: str) -> tuple[int, ...]:
        try: return tuple(int(p) for p in ip.split("."))
        except: return (9999,)

    ordered = sorted(results.items(), key=lambda kv: ipkey(kv[0]))

    # --- labels.txt: human-friendly table ---
    width_ip   = 14
    width_host = max(8, max((len(d["hostname"]) for d in results.values()), default=8))
    lines = [
        f"{'IP':<{width_ip}} {'Hostname':<{width_host}} MAC(s)",
        "-" * (width_ip + width_host + 30),
    ]
    for ip, d in ordered:
        lines.append(f"{ip:<{width_ip}} {d['hostname']:<{width_host}} {', '.join(d['macs']) or '?'}")
    if failed:
        lines.append("")
        lines.append(f"# Unreachable ({len(failed)}) — powered off or wrong creds:")
        for ip, err in sorted(failed, key=lambda kv: ipkey(kv[0])):
            lines.append(f"# {ip}   ({err})")
    LABELS_OUT.write_text("\n".join(lines) + "\n")
    print()
    print("\n".join(lines))
    print()
    print(f"Wrote labels table to {LABELS_OUT}")

    # --- macs.txt: flat list for `wol -f macs.txt` ---
    flat_macs = [m for _, d in ordered for m in d["macs"]]
    if flat_macs:
        MACS_OUT.write_text("\n".join(flat_macs) + "\n")
        print(f"Wrote {len(flat_macs)} MAC(s) to {MACS_OUT}")

    print(f"\nDone. Reachable: {len(results)}  Unreachable: {len(failed)}")


if __name__ == "__main__":
    main()
