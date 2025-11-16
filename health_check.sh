#!/usr/bin/env bash
#
# Simple health check for CarPi audio-ducker.service

set -euo pipefail

SERVICE_NAME="audio-ducker"
PORT="${CARPI_PORT:-5000}"
LOG_FILE="$HOME/audio-ducker/audio-ducker.log"

echo "== CarPi Health Check $(date -Iseconds) =="

# 1) Check service state
if ! systemctl --user is-active --quiet "$SERVICE_NAME"; then
    echo "Service $SERVICE_NAME is NOT active. Attempting restart..."
    systemctl --user restart "$SERVICE_NAME"
    sleep 3
    if ! systemctl --user is-active --quiet "$SERVICE_NAME"; then
        echo "ERROR: Service still not active after restart."
        exit 1
    fi
    echo "Service restarted successfully."
fi

# 2) Check HTTP /api/status
STATUS_JSON=$(curl -sS --max-time 2 "http://localhost:${PORT}/api/status" || true)
if [[ -z "$STATUS_JSON" ]]; then
    echo "WARNING: /api/status did not respond or was empty."
else
    echo "Status OK: /api/status responded."
fi

# 3) Check metrics for sanity
METRICS_JSON=$(curl -sS --max-time 2 "http://localhost:${PORT}/api/metrics" || true)
if [[ -z "$METRICS_JSON" ]]; then
    echo "WARNING: /api/metrics did not respond or was empty."
else
    echo "Metrics OK: /api/metrics responded."
fi

# 4) Optionally: look for obvious failures in the log
if [[ -f "$LOG_FILE" ]]; then
    if grep -qE "Traceback|JackOpenError|ERROR" "$LOG_FILE"; then
        echo "WARNING: Detected error patterns in log."
    fi
fi

echo "Health check complete."
