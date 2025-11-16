#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$HOME/audio-ducker"
VENV_DIR="$APP_DIR/venv"
UNIT_DIR="$HOME/.config/systemd/user"
SERVICE_NAME="audio-ducker"
PORT=5000

echo "=== CarPi Audio Ducker Installer ==="

mkdir -p "$APP_DIR" "$UNIT_DIR"

echo "[1/5] Creating virtualenv (if missing)..."
if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
fi

echo "[2/5] Installing Python dependencies..."
# shellcheck disable=SC1090
source "$VENV_DIR/bin/activate"
pip install --upgrade pip
pip install flask flask-socketio eventlet numpy jack-client
deactivate

echo "[3/5] Installing systemd user service..."

cat > "$UNIT_DIR/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Audio Ducking System (CarPi)
After=pipewire.service wireplumber.service

[Service]
Type=simple
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/pw-jack $VENV_DIR/bin/python $APP_DIR/audio_ducker.py
Restart=on-failure
RestartSec=3
Environment=CARPI_PORT=${PORT}

[Install]
WantedBy=default.target
EOF

echo "[4/5] Installing carpi CLI..."
mkdir -p "$HOME/.local/bin"
if [[ -f "$APP_DIR/carpi" ]]; then
    cp "$APP_DIR/carpi" "$HOME/.local/bin/" || true
    chmod +x "$HOME/.local/bin/carpi" || true
fi

# Ensure ~/.local/bin is on PATH for future shells
if ! grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
fi

echo "[5/5] (Optional) Installing health timer..."
# Only if health_check.sh exists
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
echo "Web UI should be available at:"
echo "  http://<pi-ip>:${PORT}"
echo
echo "CLI (if PATH includes ~/.local/bin):"
echo "  carpi status"
echo "  carpi open-ui"
