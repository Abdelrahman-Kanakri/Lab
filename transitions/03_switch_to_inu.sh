#!/usr/bin/env bash
# 03_switch_to_inu.sh — migrate every lab device from `labadmin` to `INU`,
# fully remote, no walking required.
#
# Steps:
#   1. Read existing devices from ~/lab/hosts.ini
#   2. Pass 1 (as labadmin): create INU + add to Administrators
#   3. Verify: ansible win_ping as INU on EVERY device
#   4. Confirm with you
#   5. Pass 2 (as INU): delete labadmin user + profile
#   6. Flip config.env's LAB_ADMIN_USER to INU
#   7. Regenerate ~/lab/hosts.ini using INU as the unified credential
#
# Devices that fail pass 1 are NOT touched in pass 2.
# Re-running is safe: each step is idempotent.

set -euo pipefail
source "$(dirname "$0")/config.env"

SUBNET="${LAB_RANGE_START%.*}"
PB_DIR="$LAB_PLAYBOOKS"

INV_LABADMIN="/tmp/lab_switch_labadmin.ini"
INV_INU="/tmp/lab_switch_inu.ini"
LOG_PASS1="/tmp/lab_switch_pass1.log"
LOG_PING="/tmp/lab_switch_ping.log"
LOG_PASS2="/tmp/lab_switch_pass2.log"
READY_FOR_PASS2="/tmp/lab_switch_ready.txt"

write_inventory() {
    local hosts_file="$1" out="$2" user="$3" pass="$4"
    {
        echo "[lab]"
        cat "$hosts_file"
        echo ""
        echo "[lab:vars]"
        echo "ansible_user=$user"
        echo "ansible_password=$pass"
        echo "ansible_connection=winrm"
        echo "ansible_winrm_transport=ntlm"
        echo "ansible_winrm_server_cert_validation=ignore"
        echo "ansible_port=5985"
    } > "$out"
}

echo "================================================================"
echo "  Migrate labadmin -> INU on every device in hosts.ini"
echo "================================================================"
echo ""

# ---- Step 0: extract IP list from hosts.ini --------------------------
ALL_IPS="/tmp/lab_switch_all_ips.txt"
grep -oE "^$SUBNET\.[0-9]+" ~/lab/hosts.ini | sort -u -t. -k4 -n > "$ALL_IPS"
TOTAL=$(wc -l < "$ALL_IPS")

if [ "$TOTAL" -eq 0 ]; then
    echo "No devices in ~/lab/hosts.ini. Nothing to do."
    exit 0
fi

echo "Found $TOTAL devices in hosts.ini."
echo ""

# ---- Step 1: pass 1 — create INU as labadmin -------------------------
echo "[1/4] Pass 1: creating INU on each device (connecting as labadmin)..."
echo "      Devices already on INU will fail this step — that is expected."
echo ""

write_inventory "$ALL_IPS" "$INV_LABADMIN" "labadmin" "$LAB_ADMIN_PASS"

# Partial failure is the point — don't let pipefail abort.
ansible-playbook -i "$INV_LABADMIN" "$PB_DIR/09_create_inu.yml" \
    --forks 30 | tee "$LOG_PASS1" || true

echo ""

# ---- Step 2: verify INU works on every device ------------------------
echo "[2/4] Verifying INU credential works on each device..."
echo ""

write_inventory "$ALL_IPS" "$INV_INU" "INU" "$LAB_ADMIN_PASS"

ansible lab -i "$INV_INU" -m win_ping --forks 30 | tee "$LOG_PING" || true

grep "SUCCESS" "$LOG_PING" | awk '{print $1}' | sort -u -t. -k4 -n > "$READY_FOR_PASS2"
READY=$(wc -l < "$READY_FOR_PASS2")
NOT_READY=$((TOTAL - READY))

echo ""
echo "    INU works on $READY / $TOTAL devices"
if [ "$NOT_READY" -gt 0 ]; then
    echo ""
    echo "    The following devices will be SKIPPED in pass 2 (labadmin stays):"
    comm -23 "$ALL_IPS" "$READY_FOR_PASS2" | sed 's/^/      /'
    echo ""
    echo "    (Likely powered off, or the INU create step failed. Re-run later"
    echo "     when they are online to finish migrating them.)"
fi

if [ "$READY" -eq 0 ]; then
    echo ""
    echo "No devices passed INU verification. Aborting before pass 2."
    exit 1
fi

# ---- Step 3: confirm before destructive pass 2 -----------------------
echo ""
read -r -p "Proceed to delete labadmin on the $READY ready devices? [y/N] " ans </dev/tty
if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo "Cancelled. INU was created on $READY devices; labadmin still present."
    exit 0
fi

# ---- Step 4: pass 2 — delete labadmin as INU -------------------------
echo ""
echo "[3/4] Pass 2: deleting labadmin on the $READY verified devices..."

write_inventory "$READY_FOR_PASS2" "$INV_INU" "INU" "$LAB_ADMIN_PASS"

ansible-playbook -i "$INV_INU" "$PB_DIR/10_delete_labadmin.yml" \
    --forks 30 | tee "$LOG_PASS2" || true

# ---- Step 5: flip config.env + rewrite hosts.ini ---------------------
echo ""
echo "[4/4] Updating config.env and hosts.ini to use INU..."

# Only flip config.env if EVERY device migrated. Otherwise leave it on labadmin
# so the still-broken hosts can be reached for retry.
if [ "$NOT_READY" -eq 0 ]; then
    sed -i 's/^export LAB_ADMIN_USER=.*/export LAB_ADMIN_USER="INU"/' ~/lab/config.env
    echo "    config.env: LAB_ADMIN_USER -> INU"
else
    echo "    config.env: NOT changed (LAB_ADMIN_USER stays labadmin so the"
    echo "                $NOT_READY un-migrated hosts remain reachable)."
    echo "                Re-run this script once they are online; it will"
    echo "                flip the config when every device is on INU."
fi

# Always rewrite hosts.ini so its [lab:vars] reflects the (possibly updated) creds
source ~/lab/config.env
{
    echo "# Auto-generated $(date -Iseconds) - lab devices verified enrolled in MeshCentral"
    echo ""
    echo "[lab]"
    cat "$ALL_IPS"
    echo ""
    echo "[lab:vars]"
    echo "ansible_user=$LAB_ADMIN_USER"
    echo "ansible_password=$LAB_ADMIN_PASS"
    echo "ansible_connection=winrm"
    echo "ansible_winrm_transport=ntlm"
    echo "ansible_winrm_server_cert_validation=ignore"
    echo "ansible_port=5985"
} > ~/lab/hosts.ini

echo "    hosts.ini regenerated with $TOTAL devices, ansible_user=$LAB_ADMIN_USER"

echo ""
echo "================================================================"
echo "  Done. $READY / $TOTAL devices migrated to INU."
if [ "$NOT_READY" -gt 0 ]; then
    echo "  $NOT_READY device(s) still on labadmin — see list above."
fi
echo "================================================================"
