#!/usr/bin/env bash
# add_devices.sh - find newly-enrolled lab devices and add them to MeshCentral
#
# Run this AFTER walking around with the Enroll-LabDevice.bat USB.
# It will:
#   1. Scan the lab subnet for hosts with WinRM open
#   2. Diff against ~/lab/hosts.ini to find what's new
#   3. Test auth on the new ones
#   4. Show you the list and ask to proceed
#   5. Run the enrollment playbook on the confirmed-working ones
#   6. Merge them into ~/lab/hosts.ini

set -euo pipefail
source "$(dirname "$0")/config.env"

SUBNET="10.3.5"
TMP_FOUND="/tmp/lab_scan_found.txt"
TMP_NEW="/tmp/lab_scan_new.txt"
TMP_READY="/tmp/lab_scan_ready.txt"
TMP_INI="/tmp/lab_scan_inventory.ini"

echo "================================================================"
echo "  Lab Device Discovery & Enrollment"
echo "================================================================"
echo ""

# ---- Step 1: scan ----
echo "[1/6] Scanning $SUBNET.0/24 for WinRM (5985)..."
> "$TMP_FOUND"
for i in $(seq 1 254); do
    ip="$SUBNET.$i"
    [ "$ip" = "$CONTROLLER_IP" ] && continue
    if timeout 1 bash -c "echo > /dev/tcp/$ip/5985" 2>/dev/null; then
        echo "$ip" >> "$TMP_FOUND"
    fi
done
TOTAL_FOUND=$(wc -l < "$TMP_FOUND")
echo "    found $TOTAL_FOUND hosts with WinRM open"

if [ "$TOTAL_FOUND" -eq 0 ]; then
    echo ""
    echo "No WinRM hosts found. Check that you ran Enroll-LabDevice.bat on devices."
    exit 1
fi

# ---- Step 2: diff ----
echo ""
echo "[2/6] Finding new devices (not yet in ~/lab/hosts.ini)..."
ALREADY="/tmp/lab_already.txt"
grep -oE "^$SUBNET\.[0-9]+" ~/lab/hosts.ini 2>/dev/null | sort -u > "$ALREADY"
comm -23 <(sort "$TMP_FOUND") "$ALREADY" > "$TMP_NEW"
NEW_COUNT=$(wc -l < "$TMP_NEW")
echo "    $NEW_COUNT new devices:"
sort -t. -k4 -n "$TMP_NEW" | sed 's/^/      /'

if [ "$NEW_COUNT" -eq 0 ]; then
    echo ""
    echo "Nothing new to enroll. All scanned devices are already in inventory."
    exit 0
fi

# ---- Step 3: test auth ----
echo ""
echo "[3/6] Testing labadmin/2026 auth on the $NEW_COUNT new hosts..."
{
    echo "[lab]"
    cat "$TMP_NEW"
    echo ""
    echo "[lab:vars]"
    echo "ansible_user=labadmin"
    echo "ansible_password=2026"
    echo "ansible_connection=winrm"
    echo "ansible_winrm_transport=ntlm"
    echo "ansible_winrm_server_cert_validation=ignore"
    echo "ansible_port=5985"
} > "$TMP_INI"

ansible lab -i "$TMP_INI" -m win_ping --forks 20 2>&1 \
  | grep -E "SUCCESS|UNREACHABLE|FAILED" \
  | awk '/SUCCESS/ {print $1; next} {print "      [skip] " $1 " " $2 " " $3}' \
  | tee /tmp/lab_auth_log.txt > /dev/null

# Extract the SUCCESS hosts
grep -v "skip" /tmp/lab_auth_log.txt | sort -u > "$TMP_READY"
READY_COUNT=$(wc -l < "$TMP_READY")
SKIPPED_COUNT=$(grep -c "skip" /tmp/lab_auth_log.txt || true)

echo "    auth OK on $READY_COUNT  /  failed on $SKIPPED_COUNT"
if [ "$SKIPPED_COUNT" -gt 0 ]; then
    grep "skip" /tmp/lab_auth_log.txt
    echo ""
    echo "    (skipped hosts likely need Enroll-LabDevice.bat re-run, or are non-lab)"
fi

if [ "$READY_COUNT" -eq 0 ]; then
    echo ""
    echo "No new devices passed auth. Aborting."
    exit 1
fi

# ---- Step 4: confirm ----
echo ""
echo "[4/6] Ready to enroll these in MeshCentral:"
sort -t. -k4 -n "$TMP_READY" | sed 's/^/      /'
echo ""
read -r -p "Proceed with enrollment? [y/N] " ans
if [[ ! "$ans" =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# ---- Step 5: enroll ----
echo ""
echo "[5/6] Running enrollment playbook..."
{
    echo "[lab]"
    cat "$TMP_READY"
    echo ""
    echo "[lab:vars]"
    echo "ansible_user=labadmin"
    echo "ansible_password=2026"
    echo "ansible_connection=winrm"
    echo "ansible_winrm_transport=ntlm"
    echo "ansible_winrm_server_cert_validation=ignore"
    echo "ansible_port=5985"
} > "$TMP_INI"

ansible-playbook -i "$TMP_INI" ~/lab/playbooks/01_enroll_with_unlock.yml \
    --forks "$READY_COUNT" 2>&1 | tail -25

# ---- Step 6: merge into hosts.ini ----
echo ""
echo "[6/6] Merging successful hosts into ~/lab/hosts.ini..."

ALL_HOSTS="/tmp/lab_all_hosts.txt"
{
    grep -oE "^$SUBNET\.[0-9]+" ~/lab/hosts.ini 2>/dev/null
    cat "$TMP_READY"
} | sort -u -t. -k4 -n > "$ALL_HOSTS"

{
    echo "# Auto-generated $(date -Iseconds) - lab devices verified enrolled in MeshCentral"
    echo ""
    echo "[lab]"
    cat "$ALL_HOSTS"
    echo ""
    echo "[lab:vars]"
    echo "ansible_user=labadmin"
    echo "ansible_password=2026"
    echo "ansible_connection=winrm"
    echo "ansible_winrm_transport=ntlm"
    echo "ansible_winrm_server_cert_validation=ignore"
    echo "ansible_port=5985"
} > ~/lab/hosts.ini

TOTAL=$(wc -l < "$ALL_HOSTS")
echo ""
echo "================================================================"
echo "  Done. ~/lab/hosts.ini now has $TOTAL devices."
echo "  Open https://$CONTROLLER_IP to see them in MeshCentral."
echo "================================================================"
