#!/usr/bin/env bash
# =============================================================================
# install.sh — Camera Recorder API setup
# Run once on your Ubuntu/Debian server.
# Usage:  bash install.sh
# =============================================================================
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
INSTALL_DIR="$HOME/cam_recorder"
SERVICE_NAME="cam-recorder"
PORT=8765

# ── 1. System packages ────────────────────────────────────────────────────────
echo ""
echo "==> [1/5] Installing system packages (python3, ffmpeg)..."
sudo apt-get update -qq
sudo apt-get install -y python3 python3-venv ffmpeg

# ── 2. Python virtualenv + deps ───────────────────────────────────────────────
echo ""
echo "==> [2/5] Creating Python virtualenv..."
python3 -m venv "$INSTALL_DIR/venv"
"$INSTALL_DIR/venv/bin/pip" install --quiet --upgrade pip
"$INSTALL_DIR/venv/bin/pip" install --quiet \
    -r "$INSTALL_DIR/requirements.txt"

# ── 3. Directories ────────────────────────────────────────────────────────────
echo ""
echo "==> [3/5] Creating recordings directory..."
mkdir -p "$INSTALL_DIR/recordings"

# ── 4. systemd service ────────────────────────────────────────────────────────
echo ""
echo "==> [4/5] Installing systemd service..."
sudo cp "$INSTALL_DIR/$SERVICE_NAME.service" \
    "/etc/systemd/system/$SERVICE_NAME.service"

# Patch the hard-coded /home/techniaa to match the actual running user
sudo sed -i "s|/home/techniaa|$HOME|g" \
    "/etc/systemd/system/$SERVICE_NAME.service"

sudo systemctl daemon-reload
sudo systemctl enable  "$SERVICE_NAME"
sudo systemctl restart "$SERVICE_NAME"

# ── 5. Verify ─────────────────────────────────────────────────────────────────
echo ""
echo "==> [5/5] Waiting 3 s for API to start..."
sleep 3

HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:$PORT/health" || echo "000")

echo ""
if [ "$HTTP" = "200" ]; then
    IP=$(hostname -I | awk '{print $1}')
    echo "✅  API is running!"
    echo ""
    echo "    URL      :  http://$IP:$PORT"
    echo "    Health   :  curl http://localhost:$PORT/health"
    echo "    Cameras  :  curl http://localhost:$PORT/cameras"
    echo "    Logs     :  journalctl -u $SERVICE_NAME -f"
    echo "    Stop     :  sudo systemctl stop $SERVICE_NAME"
    echo "    Restart  :  sudo systemctl restart $SERVICE_NAME"
else
    echo "⚠️   HTTP $HTTP — API may still be starting."
    echo "    Check logs with:  journalctl -u $SERVICE_NAME -n 50"
fi
echo ""
