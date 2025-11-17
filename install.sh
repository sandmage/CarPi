#!/usr/bin/env bash
set -euo pipefail

# Resolve the directory where install.sh lives and treat that as APP_DIR
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$SCRIPT_DIR"
VENV_DIR="$APP_DIR/venv"
UNIT_DIR="$HOME/.config/systemd/user"
SERVICE_NAME="audio-ducker"
PORT=5000

echo "=== CarPi Audio Ducker Installer ==="

mkdir -p "$APP_DIR" "$UNIT_DIR"

# ------------------------------------------------------------------------------
# [0/6] System packages: nginx + avahi-daemon for mDNS + HTTP on port 80
# ------------------------------------------------------------------------------
echo "[0/6] Installing system packages (nginx, avahi-daemon)..."
if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
fi

$SUDO apt-get update -y
$SUDO apt-get install -y git python3-pip python3-venv
$SUDO apt-get install -y nginx avahi-daemon


# ------------------------------------------------------------------------------
# [1/6] Python venv
# ------------------------------------------------------------------------------
echo "[1/6] Creating virtualenv (if missing)..."
if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
fi

# ------------------------------------------------------------------------------
# [2/6] Python deps
# ------------------------------------------------------------------------------
echo "[2/6] Installing Python dependencies..."
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install flask flask-socketio eventlet numpy jack-client
deactivate

# ------------------------------------------------------------------------------
# [3/6] systemd user service
# ------------------------------------------------------------------------------
echo "[3/6] Installing systemd user service..."

# Small wrapper so we can safely call pw-jack
cat > "$APP_DIR/run_carpi.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# Run the CarPi app under pw-jack so it attaches to PipeWire's JACK
exec pw-jack "$VENV_DIR/bin/python" "$APP_DIR/audio_ducker.py"
EOF

chmod +x "$APP_DIR/run_carpi.sh"

cat > "$UNIT_DIR/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Audio Ducking System (CarPi)
After=pipewire.service wireplumber.service default.target

[Service]
Type=simple
ExecStart=$APP_DIR/run_carpi.sh
WorkingDirectory=$APP_DIR
Restart=on-failure
RestartSec=3
Environment=CARPI_PORT=${PORT}

[Install]
WantedBy=default.target
EOF

# ------------------------------------------------------------------------------
# [4/6] Nginx reverse proxy on port 80 -> 127.0.0.1:5000
# ------------------------------------------------------------------------------
echo "[4/6] Configuring nginx reverse proxy..."

$SUDO tee /etc/nginx/sites-available/carpi >/dev/null <<EOF
server {
    listen 80;
    server_name carpi.local _;

    location / {
        proxy_pass http://127.0.0.1:${PORT};
        proxy_http_version 1.1;

        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

# Enable site and disable default
$SUDO ln -sf /etc/nginx/sites-available/carpi /etc/nginx/sites-enabled/carpi
$SUDO rm -f /etc/nginx/sites-enabled/default || true

$SUDO systemctl restart nginx

# ------------------------------------------------------------------------------
# [5/6] Avahi mDNS service for carpi.local
# ------------------------------------------------------------------------------
echo "[5/6] Configuring Avahi mDNS (carpi.local)..."

$SUDO mkdir -p /etc/avahi/services
$SUDO tee /etc/avahi/services/carpi.service >/dev/null <<EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h CarPi</name>
  <service>
    <type>_http._tcp</type>
    <port>80</port>
    <txt-record>path=/</txt-record>
  </service>
</service-group>
EOF

$SUDO systemctl restart avahi-daemon

# ------------------------------------------------------------------------------
# [6/6] carpi CLI + optional health timer
# ------------------------------------------------------------------------------
echo "[6/6] Installing carpi CLI..."
mkdir -p "$HOME/.local/bin"

if [[ -f "$APP_DIR/carpi" ]]; then
    # Inject the real APP_DIR path into the installed CLI
    sed "s|^APP_DIR=.*$|APP_DIR=\"${APP_DIR}\"|" "$APP_DIR/carpi" > "$HOME/.local/bin/carpi"
    chmod +x "$HOME/.local/bin/carpi"
else
    echo "Warning: carpi script not found in $APP_DIR; skipping CLI install."
fi

# Make sure ~/.local/bin is on PATH
if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

echo "Setting up optional health timer (if health_check.sh exists)..."
if [[ -f "$HOME/health_check.sh" ]]; then
    cat > "$UNIT_DIR/carpi-health.service" <<EOF
[Unit]
Description=CarPi health check

[Service]
Type=oneshot
ExecStart=%h/health_check.sh
EOF

    cat > "$UNIT_DIR/carpi-health.timer" <<EOF
[Unit]
Description=Run CarPi health check regularly

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s
Unit=carpi-health.service

[Install]
WantedBy=default.target
EOF

    systemctl --user enable --now carpi-health.timer || true
fi

echo "Reloading systemd user units..."
systemctl --user daemon-reload
systemctl --user enable --now "${SERVICE_NAME}.service"

echo
echo "=== Install complete ==="
echo "Service status:"
systemctl --user status "${SERVICE_NAME}.service" --no-pager --lines=5

echo
echo "You should now be able to open:"
echo "  http://carpi.local"
echo
echo "CLI (if PATH includes ~/.local/bin):"
echo "  carpi status"
echo "  carpi open-ui"
