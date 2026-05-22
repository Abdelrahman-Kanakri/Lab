#!/usr/bin/env bash
# 00_reset_controller.sh — wipe controller-side state for a clean re-install.
#
# What this DOES:
#   1. Stop + disable the meshcentral systemd unit
#   2. Archive ~/lab/meshcentral/, ~/lab/files/MeshService64.exe,
#      ~/lab/hosts.ini, ~/lab/labels.txt to ~/lab/backups/<timestamp>/
#   3. Leave a clean slate so 01_install_server.sh runs fresh
#
# What this DOES NOT do:
#   - Touch any lab device. Devices keep their old Mesh Agent + INU user.
#     Run playbooks/inactive_kept_for_reference/04_uninstall_agents.yml first
#     if you want a full agent wipe before re-install.
#   - Modify config.env. Edit it manually after this if your subnet changed.
#
# Requires explicit confirmation. Idempotent.
#
# Usage:
#   bash 00_reset_controller.sh           # interactive confirmation prompt
#   bash 00_reset_controller.sh --yes     # skip prompt (for scripting)

set -euo pipefail
source "$(dirname "$0")/config.env" 2>/dev/null || true

YES=0
[ "${1:-}" = "--yes" ] && YES=1

echo "================================================================"
echo "  Controller reset — wipe local MeshCentral state"
echo "================================================================"
echo ""
echo "Will archive (then remove the originals) of:"
echo "  ~/lab/meshcentral/                     ($(du -sh ~/lab/meshcentral 2>/dev/null | cut -f1) of MeshCentral install + DB + certs)"
echo "  ~/lab/files/MeshService64.exe          (server-keyed agent installer)"
echo "  ~/lab/hosts.ini                        (Ansible inventory)"
echo "  ~/lab/labels.txt                       (per-device label table)"
echo ""
echo "All archived to: ~/lab/backups/$(date +%Y%m%d-%H%M%S)/"
echo ""
echo "After this you can run 01_install_server.sh on a clean slate."
echo ""

if [ "$YES" -ne 1 ]; then
    read -r -p "Proceed? [y/N] " ans </dev/tty
    if [[ ! "$ans" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$HOME/lab/backups/$STAMP"
mkdir -p "$BACKUP_DIR"

echo ""
echo "[1/3] Stopping + disabling meshcentral.service..."
sudo systemctl stop meshcentral 2>/dev/null || true
sudo systemctl disable meshcentral 2>/dev/null || true
echo "    stopped"

echo ""
echo "[2/3] Archiving state..."
for path in \
    "$HOME/lab/meshcentral" \
    "$HOME/lab/files/MeshService64.exe" \
    "$HOME/lab/files/MeshService64.log" \
    "$HOME/lab/hosts.ini" \
    "$HOME/lab/labels.txt" \
    "$HOME/lab/macs.txt"
do
    if [ -e "$path" ]; then
        rel="${path#$HOME/lab/}"
        target_dir="$BACKUP_DIR/$(dirname "$rel")"
        mkdir -p "$target_dir"
        mv "$path" "$target_dir/"
        echo "    archived $rel"
    fi
done

echo ""
echo "[3/3] Removing systemd unit..."
sudo rm -f /etc/systemd/system/meshcentral.service
sudo systemctl daemon-reload
echo "    removed /etc/systemd/system/meshcentral.service"

echo ""
echo "================================================================"
echo "  Done. Controller state archived to:"
echo "    $BACKUP_DIR"
echo ""
echo "  Next steps:"
echo "    1. Verify ~/lab/config.env still has the right CONTROLLER_IP"
echo "       (check with: ip -4 addr show | grep -oE '10\.[0-9.]+/')"
echo "    2. Run: bash ~/lab/01_install_server.sh"
echo "    3. Open https://\$CONTROLLER_IP and create the admin account"
echo "    4. USB-walk every device with windows-scripts/01_Enroll-LabDevice.bat"
echo "    5. Run: bash ~/lab/02_add_devices.sh"
echo "================================================================"
