#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="audio-ducker.service"
UNIT_PATH="$HOME/.config/systemd/user/$SERVICE_NAME"
APP_DIR="$HOME/audio-ducker"
VENV_DIR="$APP_DIR/venv"
LOG_FILE="$APP_DIR/audio-ducker.log"
CONFIG_FILE_HOME="$HOME/audio_ducker_config.json"
CONFIG_FILE_APP="$APP_DIR/audio_ducker_config.json"
AUTOCONNECT="$HOME/autoconnect.sh"
REBOOT_CHECK="$HOME/reboot_check.sh"

echo "=== CarPi / Audio Ducker Uninstaller ==="
echo

# 1) Stop & disable systemd user service
if command -v systemctl >/dev/null 2>&1; then
    echo "[*] Stopping user service (if running)..."
    systemctl --user stop "$SERVICE_NAME" 2>/dev/null || true

    echo "[*] Disabling user service..."
    systemctl --user disable "$SERVICE_NAME" 2>/dev/null || true

    echo "[*] Reloading systemd user daemon..."
    systemctl --user daemon-reload || true
else
    echo "[!] systemctl not found; skipping service stop/disable."
fi

# 2) Remove systemd unit file
if [ -f "$UNIT_PATH" ]; then
    echo "[*] Removing systemd unit: $UNIT_PATH"
    rm -f "$UNIT_PATH"
else
    echo "[i] No unit file at $UNIT_PATH (already removed?)."
fi

echo

# 3) Optional cleanup helpers
cleanup_path() {
    local path="$1"
    local label="$2"

    if [ -e "$path" ]; then
        read -r -p "Remove $label at '$path'? [y/N] " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            echo "[*] Removing $label..."
            rm -rf "$path"
        else
            echo "[i] Keeping $label."
        fi
    fi
}

cleanup_path "$VENV_DIR"        "Python virtualenv"
cleanup_path "$LOG_FILE"        "log file"
cleanup_path "$CONFIG_FILE_HOME" "home config file"
cleanup_path "$CONFIG_FILE_APP"  "app config file in repo"
cleanup_path "$AUTOCONNECT"     "autoconnect script"
cleanup_path "$REBOOT_CHECK"    "reboot check script"

echo
echo "=== Uninstall complete ==="
echo "Your git repo at '$APP_DIR' has been left intact."
echo "You can remove the folder manually if you no longer need the code."
