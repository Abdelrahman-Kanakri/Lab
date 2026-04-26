#!/usr/bin/env python3
"""
Collect MAC addresses from all lab Windows devices via WinRM/NTLM.
Reads hosts from ~/lab/hosts.ini and writes MACs to ~/lab/macs.txt.
Usage: python3 ~/lab/collect_macs.py
"""

import re
import sys
import socket
import winrm
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

HOSTS_INI = Path.home() / "lab" / "hosts.ini"
MACS_OUT   = Path.home() / "lab" / "macs.txt"
USER       = "labadmin"
PASSWORD   = "2026"
PORT       = 5985
THREADS    = 20

POWERSHELL = (
    "Get-NetAdapter -Physical | "
    "Where-Object { $_.Status -eq 'Up' } | "
    "Select-Object -ExpandProperty MacAddress"
)

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


def get_mac(host: str) -> tuple[str, list[str] | None, str]:
    try:
        session = winrm.Session(
            f"http://{host}:{PORT}/wsman",
            auth=(USER, PASSWORD),
            transport="ntlm",
            server_cert_validation="ignore",
        )
        result = session.run_ps(POWERSHELL)
        if result.status_code != 0:
            return host, None, result.std_err.decode(errors="replace").strip()
        macs = [
            ln.strip().replace("-", ":").upper()
            for ln in result.std_out.decode(errors="replace").splitlines()
            if re.match(r"([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}", ln.strip())
        ]
        return host, macs, ""
    except Exception as exc:
        return host, None, str(exc)


def main():
    if not HOSTS_INI.exists():
        sys.exit(f"ERROR: {HOSTS_INI} not found")

    hosts = load_hosts(HOSTS_INI)
    if not hosts:
        sys.exit("ERROR: no hosts found in [lab] section")

    print(f"Collecting MACs from {len(hosts)} devices ({THREADS} threads)...")

    all_macs: list[str] = []
    failed: list[str] = []

    with ThreadPoolExecutor(max_workers=THREADS) as pool:
        futures = {pool.submit(get_mac, h): h for h in hosts}
        for future in as_completed(futures):
            host, macs, err = future.result()
            if macs:
                print(f"  {host}: {', '.join(macs)}")
                all_macs.extend(macs)
            else:
                print(f"  {host}: FAILED — {err[:80]}")
                failed.append(host)

    if all_macs:
        MACS_OUT.write_text("\n".join(all_macs) + "\n")
        print(f"\nWrote {len(all_macs)} MAC(s) to {MACS_OUT}")
    else:
        print("\nNo MACs collected — are the devices online?")

    if failed:
        print(f"\nFailed ({len(failed)}): {', '.join(failed)}")

    print(f"\nDone. Success: {len(hosts) - len(failed)}  Failed: {len(failed)}")


if __name__ == "__main__":
    main()
