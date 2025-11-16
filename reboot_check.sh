#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="audio-ducker"
APP_DIR="$HOME/audio-ducker"
LOG_FILE="$APP_DIR/audio-ducker.log"
WEB_URL_BASE="http://localhost:5000"

# Colors
GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

ok()   { echo -e "${GREEN}✔${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }
err()  { echo -e "${RED}✘${RESET} $*"; }

echo -e "${BOLD}${CYAN}=== Audio Ducker Reboot Validation ===${RESET}"
echo

FAIL=0

# 1. Systemd user service enabled?
echo -e "${BOLD}1) Checking systemd user service...${RESET}"
if systemctl --user is-enabled "$SERVICE_NAME" &>/dev/null; then
    ok "systemd --user service '$SERVICE_NAME' is enabled"
else
    err "service '$SERVICE_NAME' is NOT enabled (run: systemctl --user enable $SERVICE_NAME)"
    FAIL=1
fi

if systemctl --user is-active "$SERVICE_NAME" &>/dev/null; then
    ok "service '$SERVICE_NAME' is active (running)"
else
    err "service '$SERVICE_NAME' is NOT active (run: systemctl --user start $SERVICE_NAME)"
    FAIL=1
fi
echo

# 2. Linger enabled?
echo -e "${BOLD}2) Checking loginctl linger (user services after reboot)...${RESET}"
if loginctl show-user "$USER" 2>/dev/null | grep -q 'Linger=yes'; then
    ok "linger is enabled for user '$USER'"
else
    err "linger is NOT enabled for '$USER' (run: sudo loginctl enable-linger $USER)"
    FAIL=1
fi
echo

# 3. Log sanity check
echo -e "${BOLD}3) Checking recent log output...${RESET}"
if [[ -f "$LOG_FILE" ]]; then
    echo "Last 10 lines of $LOG_FILE:"
    tail -n 10 "$LOG_FILE" || true
    echo

    if grep -q "Audio Ducker started" "$LOG_FILE"; then
        ok "log shows 'Audio Ducker started'"
    else
        warn "did not see 'Audio Ducker started' in log (might be older log content)"
    fi

    if grep -q -Ei "Autoconnect watcher active|autoconnect" "$LOG_FILE"; then
        ok "log shows autoconnect watcher activity"
    else
        warn "did not see explicit autoconnect logs (may still be fine)"
    fi
else
    err "log file not found: $LOG_FILE"
    FAIL=1
fi
echo

# 4. Web API health (metrics + status)
echo -e "${BOLD}4) Checking web API endpoints...${RESET}"

check_http () {
    local path="$1"
    local label="$2"
    local url="${WEB_URL_BASE}${path}"

    HTTP_CODE=$(curl -sS -o /tmp/audio_ducker_check_$$.tmp -w "%{http_code}" "$url" || echo "000")
    if [[ "$HTTP_CODE" == "200" ]]; then
        ok "$label OK (HTTP 200)"
        echo -e "  Sample response:"
        head -n 1 /tmp/audio_ducker_check_$$.tmp
    else
        err "$label FAILED (HTTP $HTTP_CODE) for $url"
        FAIL=1
    fi
    rm -f /tmp/audio_ducker_check_$$.tmp
}

check_http "/api/metrics" "metrics endpoint"
echo
check_http "/api/status" "status endpoint"
echo

# 5. JACK / PipeWire JACK connections
echo -e "${BOLD}5) Checking JACK connections...${RESET}"

JACK_CMD=""
if command -v pw-jack &>/dev/null; then
    JACK_CMD="pw-jack jack_lsp -c"
elif command -v jack_lsp &>/dev/null; then
    JACK_CMD="jack_lsp -c"
fi

if [[ -z "$JACK_CMD" ]]; then
    warn "neither 'pw-jack' nor 'jack_lsp' found; skipping JACK connection check"
else
    echo "Using: $JACK_CMD"
    $JACK_CMD | sed 's/^/  /' || warn "jack_lsp returned non-zero (PipeWire/JACK might be idle)"

    # Very simple sanity checks for expected ports
    if $JACK_CMD 2>/dev/null | grep -q "AudioDucker:output_L"; then
        ok "AudioDucker JACK ports are visible"
    else
        err "AudioDucker JACK ports NOT visible"
        FAIL=1
    fi
fi
echo

# 6. Summary
echo -e "${BOLD}${CYAN}=== Summary ===${RESET}"
if [[ "$FAIL" -eq 0 ]]; then
    ok "All checks passed. System should survive reboot and come back working."
    exit 0
else
    err "Some checks failed. Fix the above issues before trusting reboot behavior."
    exit 1
fi
