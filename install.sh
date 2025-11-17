#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$HOME/audio-ducker"
VENV_DIR="$APP_DIR/venv"
UNIT_DIR="$HOME/.config/systemd/user"
SERVICE_NAME="audio-ducker"
PORT=5000

echo "=== CarPi Audio Ducker Installer ==="

mkdir -p "$APP_DIR" "$UNIT_DIR" "$HOME/.local/bin"

echo "[1/6] Creating virtualenv (if missing)..."
if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
fi

echo "[2/6] Installing Python dependencies..."
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install flask flask-socketio eventlet numpy jack-client
deactivate

echo "[3/6] Installing systemd user service..."

cat > "$UNIT_DIR/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Audio Ducking System (CarPi)
After=default.target

[Service]
Type=simple
ExecStart=/usr/bin/pw-jack $VENV_DIR/bin/python $APP_DIR/audio_ducker.py
WorkingDirectory=$APP_DIR
Restart=on-failure
RestartSec=3
Environment=CARPI_PORT=${PORT}

[Install]
WantedBy=default.target
EOF

echo "[4/6] Installing carpi CLI..."
cp "$APP_DIR/carpi" "$HOME/.local/bin/" 2>/dev/null || true
chmod +x "$HOME/.local/bin/carpi" 2>/dev/null || true

# Ensure ~/.local/bin is on PATH for future shells
if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

echo "[5/6] (Optional) Installing health timer..."
# Only if health_check.sh exists
if [[ -f "$HOME/health_check.sh" || -f "$APP_DIR/health_check.sh" ]]; then
    HEALTH_SCRIPT="\$HOME/health_check.sh"
    if [[ ! -f "$HOME/health_check.sh" && -f "$APP_DIR/health_check.sh" ]]; then
        HEALTH_SCRIPT="$APP_DIR/health_check.sh"
    fi

    cat > "$UNIT_DIR/carpi-health.service" <<EOF
[Unit]
Description=CarPi health check

[Service]
Type=oneshot
ExecStart=${HEALTH_SCRIPT}
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

echo "[6/6] Enabling mDNS (Avahi) for carpi.local..."
if command -v sudo >/dev/null 2>&1; then
    sudo apt-get update -y
    sudo apt-get install -y avahi-daemon avahi-utils

    sudo mkdir -p /etc/avahi/services

    sudo tee /etc/avahi/services/carpi.service >/dev/null <<EOF
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h CarPi</name>
  <service>
    <type>_http._tcp</type>
    <port>${PORT}</port>
    <txt-record>path=/</txt-record>
  </service>
</service-group>
EOF

    sudo systemctl restart avahi-daemon || true
    echo "mDNS enabled: try http://$(hostname).local:${PORT}"
else
    echo "sudo not available — skipping mDNS setup."
fi

echo "Reloading systemd user units..."
systemctl --user daemon-reload
systemctl --user enable --now "${SERVICE_NAME}.service"

echo
echo "=== Install complete ==="
echo "Service status:"
systemctl --user status "${SERVICE_NAME}.service" --no-pager --lines=5

echo
echo "Web UI should be available at:"
echo "  http://<pi-ip>:${PORT}"
echo "  or http://$(hostname).local:${PORT} (if mDNS works on your network)"
echo
echo "CLI (if PATH includes ~/.local/bin):"
echo "  carpi status"
echo "  carpi open-ui"
