#!/usr/bin/env bash
# install_server.sh — one-shot MeshCentral server bootstrap for Nobara
# Usage: ./install_server.sh
# Idempotent: safe to re-run

set -euo pipefail

source "$(dirname "$0")/config.env"

echo "[1/7] Installing Node.js and npm..."
sudo dnf install -y nodejs npm

echo "[2/7] Installing MeshCentral into $MESH_DIR..."
mkdir -p "$MESH_DIR"
cd "$MESH_DIR"
if [ ! -d "node_modules/meshcentral" ]; then
    npm install meshcentral
else
    echo "    already installed, skipping"
fi

echo "[3/7] Granting Node permission to bind ports 80/443..."
NODE_PATH="$(readlink -f "$(command -v node)")"
if [ -z "$NODE_PATH" ] || [ ! -f "$NODE_PATH" ]; then
    echo "ERROR: node binary not found"
    exit 1
fi
echo "    node real path: $NODE_PATH"
sudo setcap 'cap_net_bind_service=+ep' "$NODE_PATH"

echo "[4/7] Generating certificates (first run)..."
if [ ! -d "$MESH_DIR/meshcentral-data" ]; then
    timeout 120 node node_modules/meshcentral || true
    echo "    cert generation complete"
else
    echo "    certs already exist, skipping"
fi

echo "[5/7] Writing systemd unit..."
sudo tee /etc/systemd/system/meshcentral.service > /dev/null <<EOF
[Unit]
Description=MeshCentral Server
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$MESH_DIR
ExecStart=/usr/bin/node $MESH_DIR/node_modules/meshcentral/meshcentral.js --cert $CONTROLLER_IP
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "[6/8] Opening firewall ports 80/443..."
if command -v firewall-cmd >/dev/null 2>&1; then
    sudo firewall-cmd --permanent --add-port=443/tcp
    sudo firewall-cmd --permanent --add-port=80/tcp
    sudo firewall-cmd --reload
else
    echo "    firewalld not found, skipping"
fi

echo "[7/8] Enabling and starting MeshCentral..."
sudo systemctl daemon-reload
sudo systemctl enable --now meshcentral
sleep 3
sudo systemctl status meshcentral --no-pager | head -15

echo "[8/8] Staging signed agent for device pushes..."
mkdir -p "$LAB_FILES"
SIGNED_AGENT="$MESH_DIR/meshcentral-data/signedagents/MeshService64.exe"
if [ -f "$SIGNED_AGENT" ]; then
    cp "$SIGNED_AGENT" "$LAB_FILES/MeshService64.exe"
    echo "    copied MeshService64.exe -> $LAB_FILES/"
else
    echo "    WARNING: signed agent not found yet."
    echo "    It is generated the first time MeshCentral runs. Wait ~30s for"
    echo "    the service to come up, then re-run this script, or copy it"
    echo "    manually:"
    echo "      cp $SIGNED_AGENT $LAB_FILES/"
fi

echo ""
echo "==================================================================="
echo "MeshCentral should now be running."
echo "Open:  https://$CONTROLLER_IP"
echo "Accept the self-signed cert and create the admin account."
echo "(First account created becomes site administrator.)"
echo ""
echo "Logs:  journalctl -u meshcentral -f"
echo "==================================================================="
