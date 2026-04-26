#!/usr/bin/env bash
# serve_files.sh — start HTTP server on port 8080 for in-lab file distribution
# Serves ~/lab/files/ so Windows devices can pull via Invoke-WebRequest
# Stop with Ctrl+C

source "$(dirname "$0")/config.env"

cd "$LAB_FILES"

echo "Serving $LAB_FILES on http://$CONTROLLER_IP:8080"
echo "Lab devices can fetch files like: http://$CONTROLLER_IP:8080/MeshService64.exe"
echo "Press Ctrl+C to stop."
echo ""
ls -lh "$LAB_FILES"
echo ""

python3 -m http.server 8080 --bind 0.0.0.0
