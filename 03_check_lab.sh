#!/usr/bin/env bash
# check_lab.sh - quick health snapshot of the lab
# Reports:
#   - How many devices are in inventory
#   - How many of those are reachable right now
#   - Mesh Agent service status on each
# Use this anytime — read-only, safe to run repeatedly.

set -euo pipefail
source "$(dirname "$0")/config.env"

echo "================================================================"
echo "  Lab Health Check  ($(date '+%Y-%m-%d %H:%M:%S'))"
echo "================================================================"
echo ""

# Inventory size — match the lab subnet derived from config.env
SUBNET="${LAB_RANGE_START%.*}"
TOTAL=$(grep -cE "^${SUBNET//./\\.}\." ~/lab/hosts.ini || echo 0)
echo "Inventory size: $TOTAL devices"
echo ""

if [ "$TOTAL" -eq 0 ]; then
    echo "Empty inventory. Run ./add_devices.sh after walking around."
    exit 0
fi

echo "[1/2] WinRM reachability..."
ansible lab -i ~/lab/hosts.ini -m win_ping --forks 50 2>&1 \
  | grep -E "SUCCESS|UNREACHABLE|FAILED" \
  | awk '{print $1, $2}' \
  | sort -t. -k4 -n \
  | tee /tmp/lab_check_winrm.txt > /dev/null

WINRM_OK=$(grep -c SUCCESS /tmp/lab_check_winrm.txt || true)
WINRM_BAD=$(grep -cE "UNREACHABLE|FAILED" /tmp/lab_check_winrm.txt || true)
echo "    reachable: $WINRM_OK   unreachable: $WINRM_BAD"
if [ "$WINRM_BAD" -gt 0 ]; then
    grep -E "UNREACHABLE|FAILED" /tmp/lab_check_winrm.txt | sed 's/^/      /'
fi
echo ""

echo "[2/2] Mesh Agent service status (only on reachable hosts)..."
grep SUCCESS /tmp/lab_check_winrm.txt | awk '{print $1}' > /tmp/lab_check_reachable.txt

if [ -s /tmp/lab_check_reachable.txt ]; then
    {
        echo "[lab]"
        cat /tmp/lab_check_reachable.txt
        echo ""
        echo "[lab:vars]"
        echo "ansible_user=$LAB_ADMIN_USER"
        echo "ansible_password=$LAB_ADMIN_PASS"
        echo "ansible_connection=winrm"
        echo "ansible_winrm_transport=ntlm"
        echo "ansible_winrm_server_cert_validation=ignore"
        echo "ansible_port=5985"
    } > /tmp/lab_check.ini

    ansible lab -i /tmp/lab_check.ini -m win_shell \
        -a "(Get-Service 'Mesh Agent' -ErrorAction SilentlyContinue).Status" \
        --forks 50 2>&1 \
      | awk '/SUCCESS|FAILED/ {host=$1} /Running|Stopped|^$/ {if(NF>0) print host, $0}' \
      | sed 's/=>.*//' \
      | sort -t. -k4 -n > /tmp/lab_check_mesh.txt

    AGENT_RUN=$(grep -c "Running" /tmp/lab_check_mesh.txt || true)
    AGENT_OFF=$(grep -cE "Stopped|^$" /tmp/lab_check_mesh.txt || true)
    echo "    running: $AGENT_RUN   not running: $AGENT_OFF"
    if [ "$AGENT_OFF" -gt 0 ]; then
        grep -vE "Running" /tmp/lab_check_mesh.txt | sed 's/^/      /'
    fi
fi
echo ""
echo "================================================================"
echo "  Summary"
echo "================================================================"
echo "  Inventory:        $TOTAL"
echo "  WinRM reachable:  $WINRM_OK"
echo "  Mesh Agent up:    ${AGENT_RUN:-0}"
echo "================================================================"
