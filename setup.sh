#!/usr/bin/env bash
# =============================================================================
# setup.sh — Camera Recorder · One-shot install & run
# =============================================================================
# Pulls the latest code from GitHub and sets up:
#   • Backend  : FastAPI on port 8765 (systemd service, auto-restart)
#   • Frontend : dash_admin on port 9598 (systemd service, auto-restart)
#
# Usage (run as your normal user, NOT root):
#   bash setup.sh
#
# To update code and restart services later:
#   bash setup.sh --update
# =============================================================================
set -euo pipefail

# ── ╔══════════════════════════════╗ ──────────────────────────────────────────
# ── ║      CONFIGURATION           ║ — Edit these if needed
# ── ╚══════════════════════════════╝ ──────────────────────────────────────────

GITHUB_REPO="https://github.com/HaldunMatar/cameras_recording.git"
INSTALL_DIR="$HOME/cameras_recording"       # where the repo is cloned/pulled

BACKEND_SERVICE="cam-recorder"
BACKEND_PORT=8765
BACKEND_DIR="$INSTALL_DIR/cam_backend"

FRONTEND_SERVICE="cam-dashboard"
FRONTEND_PORT=9598
FRONTEND_DIR="$INSTALL_DIR/dash_admin"
FRONTEND_HOST="0.0.0.0"                    # listens on all interfaces

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

banner() { echo -e "\n${CYAN}${BOLD}==> $1${RESET}"; }
ok()     { echo -e "    ${GREEN}✓  $1${RESET}"; }
warn()   { echo -e "    ${YELLOW}⚠  $1${RESET}"; }
err()    { echo -e "    ${RED}✗  $1${RESET}"; exit 1; }

UPDATE_ONLY=false
[[ "${1:-}" == "--update" ]] && UPDATE_ONLY=true

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — System packages
# ═════════════════════════════════════════════════════════════════════════════
banner "[1/7] System packages"

sudo apt-get update -qq

# git, curl
sudo apt-get install -y git curl

# Python
sudo apt-get install -y python3 python3-venv

# ffmpeg (needed by backend for camera streams)
sudo apt-get install -y ffmpeg

# Node.js — check if already installed, install LTS via NodeSource if not
if ! command -v node &>/dev/null; then
    echo "    Installing Node.js LTS..."
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - >/dev/null 2>&1
    sudo apt-get install -y nodejs
fi
ok "python3 $(python3 --version 2>&1 | awk '{print $2}')"
ok "node    $(node --version)"
ok "npm     $(npm --version)"
ok "ffmpeg  $(ffmpeg -version 2>&1 | head -1 | awk '{print $3}')"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 — Clone or update repo
# ═════════════════════════════════════════════════════════════════════════════
banner "[2/7] Repository"

if [ -d "$INSTALL_DIR/.git" ]; then
    echo "    Pulling latest code..."
    git -C "$INSTALL_DIR" pull --ff-only
    ok "Repo updated → $INSTALL_DIR"
else
    echo "    Cloning $GITHUB_REPO..."
    git clone "$GITHUB_REPO" "$INSTALL_DIR"
    ok "Repo cloned → $INSTALL_DIR"
fi

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 — Backend: Python venv + dependencies
# ═════════════════════════════════════════════════════════════════════════════
banner "[3/7] Backend — Python virtualenv"

cd "$BACKEND_DIR"

if [ ! -d "venv" ]; then
    python3 -m venv venv
    ok "Virtualenv created"
fi

venv/bin/pip install --quiet --upgrade pip
venv/bin/pip install --quiet -r requirements.txt
ok "Python dependencies installed"

# Recordings directory
mkdir -p "$BACKEND_DIR/recordings"
ok "Recordings dir → $BACKEND_DIR/recordings"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 — Frontend: npm install
# ═════════════════════════════════════════════════════════════════════════════
banner "[4/7] Frontend — npm install"

cd "$FRONTEND_DIR"
npm install --silent
ok "npm packages installed"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5 — Backend systemd service
# ═════════════════════════════════════════════════════════════════════════════
banner "[5/7] Backend service  (port $BACKEND_PORT)"

# Write service file dynamically so it always matches the real paths/user
sudo tee /etc/systemd/system/${BACKEND_SERVICE}.service > /dev/null <<EOF
[Unit]
Description=Camera Recorder API
Documentation=$GITHUB_REPO
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$BACKEND_DIR

Environment="RECORDINGS_DIR=$BACKEND_DIR/recordings"
Environment="CONFIG_FILE=$BACKEND_DIR/config.json"
Environment="APP_CONFIG_FILE=$BACKEND_DIR/app_config.json"
Environment="HLS_DIR=/tmp/hls"

ExecStart=$BACKEND_DIR/venv/bin/uvicorn main:app \
    --host 0.0.0.0 \
    --port $BACKEND_PORT \
    --workers 1 \
    --log-level info

Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$BACKEND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable  "$BACKEND_SERVICE"
sudo systemctl restart "$BACKEND_SERVICE"
ok "Service $BACKEND_SERVICE enabled and started"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6 — Frontend systemd service
# ═════════════════════════════════════════════════════════════════════════════
banner "[6/7] Frontend service  (port $FRONTEND_PORT)"

sudo tee /etc/systemd/system/${FRONTEND_SERVICE}.service > /dev/null <<EOF
[Unit]
Description=Camera Recorder Dashboard
Documentation=$GITHUB_REPO
After=network-online.target ${BACKEND_SERVICE}.service
Wants=network-online.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$FRONTEND_DIR

Environment="HOST=$FRONTEND_HOST"
Environment="PORT=$FRONTEND_PORT"
Environment="NODE_ENV=production"

ExecStart=$(which npm) start

Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$FRONTEND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable  "$FRONTEND_SERVICE"
sudo systemctl restart "$FRONTEND_SERVICE"
ok "Service $FRONTEND_SERVICE enabled and started"

# ═════════════════════════════════════════════════════════════════════════════
# STEP 7 — Verify both services
# ═════════════════════════════════════════════════════════════════════════════
banner "[7/7] Verifying services..."
sleep 4

SERVER_IP=$(hostname -I | awk '{print $1}')

# Check backend
BACKEND_HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:$BACKEND_PORT/health" 2>/dev/null || echo "000")

# Check frontend (try to reach it; some npm apps return non-200 on /)
FRONTEND_STATUS=$(systemctl is-active "$FRONTEND_SERVICE" 2>/dev/null || echo "unknown")

echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${BOLD}  Camera Recorder — Setup Complete${RESET}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

if [ "$BACKEND_HTTP" = "200" ]; then
    echo -e "  ${GREEN}✅  Backend API${RESET}   http://$SERVER_IP:$BACKEND_PORT"
else
    echo -e "  ${YELLOW}⚠   Backend API${RESET}   HTTP $BACKEND_HTTP — may still be starting"
    echo -e "      journalctl -u $BACKEND_SERVICE -n 30"
fi

if [ "$FRONTEND_STATUS" = "active" ]; then
    echo -e "  ${GREEN}✅  Dashboard${RESET}      http://$SERVER_IP:$FRONTEND_PORT"
else
    echo -e "  ${YELLOW}⚠   Dashboard${RESET}     status=$FRONTEND_STATUS"
    echo -e "      journalctl -u $FRONTEND_SERVICE -n 30"
fi

echo ""
echo -e "${BOLD}  Useful commands:${RESET}"
echo "  sudo systemctl status  $BACKEND_SERVICE"
echo "  sudo systemctl status  $FRONTEND_SERVICE"
echo "  sudo systemctl restart $BACKEND_SERVICE"
echo "  sudo systemctl restart $FRONTEND_SERVICE"
echo "  journalctl -u $BACKEND_SERVICE  -f"
echo "  journalctl -u $FRONTEND_SERVICE -f"
echo ""
echo -e "${BOLD}  To update code and restart:${RESET}"
echo "  bash $INSTALL_DIR/setup.sh --update"
echo ""
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
