#!/bin/bash
# Audio Ducking System - Single File Installer
# Creates ~/audio-ducker with backend, UI, venv, and a systemd user service.

set -e

if [ "$EUID" -eq 0 ]; then
  echo "❌ Do NOT run as root. Use your normal user."
  exit 1
fi

INSTALL_DIR="$HOME/audio-ducker"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$SYSTEMD_USER_DIR/audio-ducker.service"
LOG_FILE="$INSTALL_DIR/audio-ducker.log"

echo "========================================="
echo " Audio Ducking System - Installer"
echo "========================================="
echo ""

echo "➡ Creating install directory: $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/templates"
mkdir -p "$SYSTEMD_USER_DIR"

echo ""
echo "➡ Installing system packages (may ask for sudo password)..."
sudo apt-get update -y
sudo apt-get install -y \
  python3 python3-venv python3-pip \
  jackd2 pipewire-jack qjackctl \
  curl git

echo ""
echo "➡ Writing backend: $INSTALL_DIR/audio_ducker.py"

cat > "$INSTALL_DIR/audio_ducker.py" << 'EOF'
#!/usr/bin/env python3
"""
Audio Ducking System for Raspberry Pi
- Uses JACK for low-latency audio routing and ducking
- Exposes a web UI via Flask + Socket.IO
"""

import os
import time
import json
import threading
from collections import deque

import numpy as np
import jack
from jack import JackOpenError

from flask import Flask, render_template, jsonify, request
from flask_socketio import SocketIO

# -----------------------------------------------------------------------------
# Flask / Socket.IO setup
# -----------------------------------------------------------------------------
app = Flask(__name__)
app.config['SECRET_KEY'] = 'audio-ducking-secret'

socketio = SocketIO(
    app,
    cors_allowed_origins="*",
    ping_timeout=60,
    ping_interval=25,
    async_mode="eventlet",
    logger=False,
    engineio_logger=False,
)

START_TIME = time.time()


# -----------------------------------------------------------------------------
# Audio Ducking Engine
# -----------------------------------------------------------------------------
class AudioDucker:
    def __init__(self):
        # IMPORTANT:
        # - no_start_server=True so we ONLY attach to an already-running JACK server
        #   (PipeWire JACK or jackd started by qjackctl)
        # - if there is no JACK server, this will raise JackOpenError
        self.client = jack.Client("AudioDucker", no_start_server=True)

        # Audio ports
        self.primary_in = self.client.inports.register("primary_in_L")
        self.primary_in_r = self.client.inports.register("primary_in_R")
        self.secondary_in = self.client.inports.register("secondary_in_L")
        self.secondary_in_r = self.client.inports.register("secondary_in_R")
        self.output_l = self.client.outports.register("output_L")
        self.output_r = self.client.outports.register("output_R")

        # Settings (saved to file)
        self.config_file = os.path.expanduser("~/audio_ducker_config.json")
        self.settings = self.load_settings()

        # Audio state
        self.primary_level = 0.0
        self.secondary_level = 0.0
        self.output_level = 0.0
        self.clipping = False

        self.duck_amount = 1.0  # 1.0 = no duck, 0.0 = full duck
        self.target_duck = 1.0

        # VU history (for simple peak-hold)
        self.primary_vu_history = deque(maxlen=20)
        self.secondary_vu_history = deque(maxlen=20)
        self.output_vu_history = deque(maxlen=20)

        # JACK callback
        self.client.set_process_callback(self.process)

        # Thread for metrics/status
        self.running = True
        self.monitor_thread = threading.Thread(
            target=self.monitor_loop, daemon=True
        )

    # -------------------
    # Config
    # -------------------
    def load_settings(self):
        """Load settings from file or use defaults."""
        defaults = {
            # Basic
            "primary_threshold_db": -40.0,
            "duck_amount_db": -20.0,
            "attack_time_ms": 50,
            "release_time_ms": 500,

            # Routing / sources (informational only for now)
            "primary_source": "carplay",
            "secondary_source": "line_in",
            "show_vu_meters": True,
            "output_device": "system",

            # Gains
            "primary_gain_db": 0.0,
            "secondary_gain_db": 0.0,
            "output_gain_db": 0.0,

            # Timing
            "hold_time_ms": 100,

            # Modes
            "ducking_mode": "standard",

            # Processing (placeholders for future DSP)
            "enable_limiter": True,
            "limiter_threshold_db": -1.0,
            "enable_compressor": False,
            "compressor_ratio": 4.0,
        }

        if os.path.exists(self.config_file):
            try:
                with open(self.config_file, "r") as f:
                    loaded = json.load(f)
                    defaults.update(loaded)
            except Exception:
                # Corrupt file? Ignore and use defaults.
                pass

        return defaults

    def save_settings(self):
        """Persist settings to disk."""
        try:
            with open(self.config_file, "w") as f:
                json.dump(self.settings, f, indent=2)
        except Exception as e:
            print(f"Error saving settings: {e}")

    # -------------------
    # Helpers
    # -------------------
    @staticmethod
    def db_to_linear(db):
        """Convert dB to linear amplitude."""
        return 10 ** (db / 20.0)

    @staticmethod
    def linear_to_db(linear):
        """Convert linear amplitude to dB."""
        if linear <= 0:
            return -100.0
        return 20 * np.log10(linear)

    @staticmethod
    def calculate_rms(audio_data):
        """Root-mean-square of a buffer."""
        if len(audio_data) == 0:
            return 0.0
        return float(np.sqrt(np.mean(audio_data ** 2)))

    # -------------------
    # JACK callback
    # -------------------
    def process(self, frames):
        """JACK audio process callback."""
        try:
            # Get inputs from JACK
            primary_l = np.array(self.primary_in.get_array(), dtype=np.float32)
            primary_r = np.array(self.primary_in_r.get_array(), dtype=np.float32)
            secondary_l = np.array(self.secondary_in.get_array(), dtype=np.float32)
            secondary_r = np.array(self.secondary_in_r.get_array(), dtype=np.float32)

            # Apply input gains
            primary_gain = self.db_to_linear(self.settings["primary_gain_db"])
            secondary_gain = self.db_to_linear(self.settings["secondary_gain_db"])

            primary_l *= primary_gain
            primary_r *= primary_gain
            secondary_l *= secondary_gain
            secondary_r *= secondary_gain

            # Measure RMS for meters
            primary_rms = max(
                self.calculate_rms(primary_l),
                self.calculate_rms(primary_r),
            )
            secondary_rms = max(
                self.calculate_rms(secondary_l),
                self.calculate_rms(secondary_r),
            )

            self.primary_level = primary_rms
            self.secondary_level = secondary_rms

            # Determine ducking based on primary level
            primary_db = self.linear_to_db(primary_rms)
            if primary_db > self.settings["primary_threshold_db"]:
                # Primary active → duck secondary
                self.target_duck = self.db_to_linear(self.settings["duck_amount_db"])
            else:
                # No primary → no duck
                self.target_duck = 1.0

            # Smooth ducking transition (attack / release)
            samplerate = self.client.samplerate
            attack_samples = (self.settings["attack_time_ms"] / 1000.0) * samplerate
            release_samples = (self.settings["release_time_ms"] / 1000.0) * samplerate

            if self.target_duck < self.duck_amount:
                # Attack (more duck)
                step = (self.duck_amount - self.target_duck) / max(attack_samples, 1)
                self.duck_amount = max(
                    self.target_duck,
                    self.duck_amount - step * frames,
                )
            else:
                # Release (less duck)
                step = (self.target_duck - self.duck_amount) / max(release_samples, 1)
                self.duck_amount = min(
                    self.target_duck,
                    self.duck_amount + step * frames,
                )

            # Apply ducking to secondary
            secondary_l_ducked = secondary_l * self.duck_amount
            secondary_r_ducked = secondary_r * self.duck_amount

            # Mix primary + ducked secondary
            output_l = primary_l + secondary_l_ducked
            output_r = primary_r + secondary_r_ducked

            # Output gain
            output_gain = self.db_to_linear(self.settings.get("output_gain_db", 0.0))
            output_l *= output_gain
            output_r *= output_gain

            # Prevent clipping (simple limiter)
            max_val = float(max(np.abs(output_l).max(), np.abs(output_r).max()))
            clipping = max_val > 1.0
            if clipping:
                output_l /= max_val
                output_r /= max_val

            # Track output level and clipping
            output_rms = max(
                self.calculate_rms(output_l),
                self.calculate_rms(output_r),
            )
            self.output_level = output_rms
            self.clipping = clipping

            # Write back to JACK outputs
            self.output_l.get_array()[:] = output_l
            self.output_r.get_array()[:] = output_r

        except Exception as e:
            print(f"Error in process callback: {e}")

    # -------------------
    # Monitor loop → WebSocket updates
    # -------------------
    def monitor_loop(self):
        """Background thread to send metrics & status via Socket.IO."""
        last_status_emit = 0.0

        while self.running:
            try:
                primary_db = self.linear_to_db(self.primary_level)
                secondary_db = self.linear_to_db(self.secondary_level)
                output_db = self.linear_to_db(self.output_level)

                self.primary_vu_history.append(primary_db)
                self.secondary_vu_history.append(secondary_db)
                self.output_vu_history.append(output_db)

                primary_peak = max(self.primary_vu_history) if self.primary_vu_history else primary_db
                secondary_peak = max(self.secondary_vu_history) if self.secondary_vu_history else secondary_db
                output_peak = max(self.output_vu_history) if self.output_vu_history else output_db

                metrics = {
                    "primary_level_db": float(primary_db),
                    "secondary_level_db": float(secondary_db),
                    "output_level_db": float(output_db),
                    "primary_peak_db": float(primary_peak),
                    "secondary_peak_db": float(secondary_peak),
                    "output_peak_db": float(output_peak),
                    "duck_amount": float(self.duck_amount),
                    "primary_active": bool(primary_db > self.settings["primary_threshold_db"]),
                    "clipping": bool(self.clipping),
                }

                # New UI event
                socketio.emit("metrics", metrics)

                # Legacy VU event
                socketio.emit("vu_update", {
                    "primary": float(primary_db),
                    "secondary": float(secondary_db),
                    "primary_peak": float(primary_peak),
                    "secondary_peak": float(secondary_peak),
                    "duck_amount": float(self.duck_amount),
                    "primary_active": bool(primary_db > self.settings["primary_threshold_db"]),
                })

                # Status (1 Hz)
                now = time.time()
                if now - last_status_emit >= 1.0:
                    last_status_emit = now
                    samplerate = self.client.samplerate or 48000
                    blocksize = self.client.blocksize or 256
                    latency_ms = (blocksize / float(samplerate)) * 1000.0

                    status = {
                        "running": self.running,
                        "samplerate": samplerate,
                        "blocksize": blocksize,
                        "uptime_seconds": int(now - START_TIME),
                        "latency_ms": float(latency_ms),
                        "cpu_usage": 0.0,
                    }
                    socketio.emit("status", status)

                time.sleep(0.01)

            except Exception as e:
                print("Error in monitor loop:", e)
                time.sleep(0.1)

    # -------------------
    # Lifecycle
    # -------------------
    def start(self):
        """Activate JACK client and monitoring thread."""
        self.client.activate()
        self.monitor_thread.start()
        print("Audio Ducker started")
        print(f"Primary input:   {self.primary_in.name}, {self.primary_in_r.name}")
        print(f"Secondary input: {self.secondary_in.name}, {self.secondary_in_r.name}")
        print(f"Output:          {self.output_l.name}, {self.output_r.name}")
        print("Connect audio using qjackctl or jack_connect")

    def stop(self):
        """Deactivate JACK and stop thread."""
        self.running = False
        self.client.deactivate()
        self.client.close()


# Global instance
ducker = None


# -----------------------------------------------------------------------------
# Flask routes / API
# -----------------------------------------------------------------------------
@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/settings", methods=["GET"])
def api_get_settings():
    return jsonify(ducker.settings)


@app.route("/api/settings", methods=["POST"])
def api_update_settings():
    data = request.json or {}
    ducker.settings.update(data)
    ducker.save_settings()
    return jsonify({"status": "success"})


@app.route("/api/status", methods=["GET"])
def api_status():
    samplerate = ducker.client.samplerate or 48000
    blocksize = ducker.client.blocksize or 256
    latency_ms = (blocksize / float(samplerate)) * 1000.0
    now = time.time()

    return jsonify({
        "running": ducker.running,
        "samplerate": samplerate,
        "blocksize": blocksize,
        "uptime_seconds": int(now - START_TIME),
        "latency_ms": float(latency_ms),
        "cpu_usage": 0.0,
        "ports": {
            "primary_in": [ducker.primary_in.name, ducker.primary_in_r.name],
            "secondary_in": [ducker.secondary_in.name, ducker.secondary_in_r.name],
            "output": [ducker.output_l.name, ducker.output_r.name],
        },
    })


@app.route("/api/restart", methods=["POST"])
def api_restart():
    """Restart the audio-ducker service via systemd (if available)."""
    try:
        import subprocess
        subprocess.Popen(["systemctl", "--user", "restart", "audio-ducker"])
        return jsonify({"status": "restarting"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/logs", methods=["GET"])
def api_logs():
    """Return logs if we can read them from the log file."""
    log_path = os.path.expanduser("~/audio-ducker/audio-ducker.log")
    try:
        if not os.path.exists(log_path):
            return jsonify({"logs": ["No log file found at " + log_path]})
        with open(log_path, "r") as f:
            lines = f.read().splitlines()
        # Last ~200 lines
        return jsonify({"logs": lines[-200:]})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/reset-settings", methods=["POST"])
def api_reset_settings():
    """Reset settings to defaults (and delete config file)."""
    try:
        if os.path.exists(ducker.config_file):
            os.remove(ducker.config_file)
        ducker.settings = ducker.load_settings()
        ducker.save_settings()
        return jsonify({"status": "success", "settings": ducker.settings})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


# -----------------------------------------------------------------------------
# Main entrypoint
# -----------------------------------------------------------------------------
def main():
    global ducker
    print("Starting Audio Ducking System...")

    try:
        ducker = AudioDucker()
    except JackOpenError as e:
        print("Failed to initialize JACK client:")
        print("  ", e)
        print("Is a JACK or PipeWire-JACK server running?")
        # Exit cleanly (status 0) so systemd doesn't hammer restart loops.
        return

    ducker.start()

    print("\nStarting web interface on http://0.0.0.0:5000")
    print("Access from other devices at http://<raspberry-pi-ip>:5000\n")

    try:
        socketio.run(app, host="0.0.0.0", port=5000, debug=False, use_reloader=False)
    except KeyboardInterrupt:
        print("\nShutting down...")
    finally:
        ducker.stop()


if __name__ == "__main__":
    main()
EOF

chmod +x "$INSTALL_DIR/audio_ducker.py"

echo ""
echo "➡ Writing simple web UI: $INSTALL_DIR/templates/index.html"

cat > "$INSTALL_DIR/templates/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>Audio Ducking System</title>
  <script src="https://cdn.socket.io/4.5.4/socket.io.min.js"></script>
  <style>
    body {
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #0f172a;
      color: #e5e7eb;
      margin: 0;
      padding: 2rem;
    }
    h1 {
      margin-bottom: 0.5rem;
    }
    .card {
      background: #020617;
      border-radius: 0.75rem;
      padding: 1.5rem;
      box-shadow: 0 20px 30px rgba(0,0,0,0.5);
      max-width: 900px;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
      gap: 1rem;
      margin-top: 1rem;
    }
    .meter-label {
      display: flex;
      justify-content: space-between;
      font-size: 0.8rem;
      color: #9ca3af;
      margin-bottom: 0.25rem;
    }
    .meter {
      position: relative;
      height: 20px;
      background: #020617;
      border-radius: 999px;
      overflow: hidden;
      border: 1px solid #1f2937;
    }
    .meter-inner {
      position: absolute;
      top: 0;
      left: 0;
      height: 100%;
      width: 0%;
      background: linear-gradient(90deg,#22c55e,#eab308,#ef4444);
      transition: width 80ms linear;
    }
    .controls label {
      display: block;
      font-size: 0.85rem;
      margin-top: 0.75rem;
    }
    input[type="range"] {
      width: 100%;
    }
    .status {
      margin-top: 1rem;
      font-size: 0.8rem;
      color: #9ca3af;
    }
    button {
      background: #4f46e5;
      border: none;
      border-radius: 999px;
      padding: 0.5rem 1rem;
      color: white;
      font-size: 0.9rem;
      cursor: pointer;
      margin-right: 0.5rem;
    }
    button:disabled {
      opacity: 0.5;
      cursor: default;
    }
    .row {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 1rem;
      margin-top: 0.75rem;
      flex-wrap: wrap;
    }
    .value-pill {
      background: #020617;
      border-radius: 999px;
      padding: 0.25rem 0.5rem;
      font-size: 0.75rem;
      border: 1px solid #1f2937;
    }
    .clipping {
      color: #ef4444;
      font-weight: 600;
    }
  </style>
</head>
<body>
  <h1>Audio Ducking System</h1>
  <p>Live monitor &amp; controls for your JACK / PipeWire audio ducking engine.</p>

  <div class="card">
    <div class="grid">
      <div>
        <div class="meter-label">
          <span>Primary</span>
          <span id="primary-db">-∞ dB</span>
        </div>
        <div class="meter"><div id="primary-meter" class="meter-inner"></div></div>
      </div>
      <div>
        <div class="meter-label">
          <span>Secondary</span>
          <span id="secondary-db">-∞ dB</span>
        </div>
        <div class="meter"><div id="secondary-meter" class="meter-inner"></div></div>
      </div>
      <div>
        <div class="meter-label">
          <span>Output</span>
          <span id="output-db">-∞ dB</span>
        </div>
        <div class="meter"><div id="output-meter" class="meter-inner"></div></div>
      </div>
    </div>

    <div class="row">
      <span>Duck amount</span>
      <span class="value-pill"><span id="duck-amount-label">0 dB</span></span>
    </div>

    <div class="grid controls">
      <div>
        <label>
          Primary threshold (dB)
          <input type="range" id="primary-threshold" min="-80" max="0" step="1">
          <span id="primary-threshold-label"></span>
        </label>
        <label>
          Duck amount (dB)
          <input type="range" id="duck-amount" min="-40" max="0" step="1">
          <span id="duck-amount-slider-label"></span>
        </label>
      </div>
      <div>
        <label>
          Primary gain (dB)
          <input type="range" id="primary-gain" min="-24" max="24" step="1">
          <span id="primary-gain-label"></span>
        </label>
        <label>
          Secondary gain (dB)
          <input type="range" id="secondary-gain" min="-24" max="24" step="1">
          <span id="secondary-gain-label"></span>
        </label>
        <label>
          Output gain (dB)
          <input type="range" id="output-gain" min="-24" max="24" step="1">
          <span id="output-gain-label"></span>
        </label>
      </div>
    </div>

    <div class="row">
      <div>
        <button id="btn-save">Save Settings</button>
        <button id="btn-reset">Reset Defaults</button>
      </div>
      <div id="clipping-indicator" class="clipping" style="display:none;">
        CLIPPING!
      </div>
    </div>

    <div class="status" id="status-line">
      Waiting for status...
    </div>
  </div>

  <script>
    const socket = io();

    let currentSettings = null;

    function dbToPercent(db) {
      const CLIP_DB = 0;
      const FLOOR_DB = -80;
      if (db <= FLOOR_DB) return 0;
      if (db >= CLIP_DB) return 100;
      return ((db - FLOOR_DB) / (CLIP_DB - FLOOR_DB)) * 100;
    }

    function formatDb(db) {
      if (db <= -90) return "-∞ dB";
      return db.toFixed(1) + " dB";
    }

    function applySettingsToUI() {
      if (!currentSettings) return;
      const s = currentSettings;

      const threshold = document.getElementById("primary-threshold");
      const duck = document.getElementById("duck-amount");
      const pg = document.getElementById("primary-gain");
      const sg = document.getElementById("secondary-gain");
      const og = document.getElementById("output-gain");

      threshold.value = s.primary_threshold_db;
      duck.value = s.duck_amount_db;
      pg.value = s.primary_gain_db;
      sg.value = s.secondary_gain_db;
      og.value = s.output_gain_db;

      document.getElementById("primary-threshold-label").textContent =
        s.primary_threshold_db.toFixed(0) + " dB";
      document.getElementById("duck-amount-slider-label").textContent =
        s.duck_amount_db.toFixed(0) + " dB";
      document.getElementById("primary-gain-label").textContent =
        s.primary_gain_db.toFixed(0) + " dB";
      document.getElementById("secondary-gain-label").textContent =
        s.secondary_gain_db.toFixed(0) + " dB";
      document.getElementById("output-gain-label").textContent =
        s.output_gain_db.toFixed(0) + " dB";
    }

    function bindSettingSlider(id, key, labelId) {
      const el = document.getElementById(id);
      el.addEventListener("input", () => {
        if (!currentSettings) return;
        const val = parseFloat(el.value);
        currentSettings[key] = val;
        document.getElementById(labelId).textContent = val.toFixed(0) + " dB";
      });
    }

    bindSettingSlider("primary-threshold", "primary_threshold_db", "primary-threshold-label");
    bindSettingSlider("duck-amount", "duck_amount_db", "duck-amount-slider-label");
    bindSettingSlider("primary-gain", "primary_gain_db", "primary-gain-label");
    bindSettingSlider("secondary-gain", "secondary_gain_db", "secondary-gain-label");
    bindSettingSlider("output-gain", "output_gain_db", "output-gain-label");

    document.getElementById("btn-save").addEventListener("click", async () => {
      if (!currentSettings) return;
      await fetch("/api/settings", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(currentSettings)
      });
    });

    document.getElementById("btn-reset").addEventListener("click", async () => {
      const res = await fetch("/api/reset-settings", { method: "POST" });
      const json = await res.json();
      if (json.settings) {
        currentSettings = json.settings;
        applySettingsToUI();
      }
    });

    socket.on("connect", async () => {
      document.getElementById("status-line").textContent = "Connected to backend, loading settings...";
      try {
        const res = await fetch("/api/settings");
        const s = await res.json();
        currentSettings = s;
        applySettingsToUI();
        document.getElementById("status-line").textContent = "Connected.";
      } catch (e) {
        document.getElementById("status-line").textContent = "Error loading settings.";
      }
    });

    socket.on("metrics", (m) => {
      document.getElementById("primary-db").textContent = formatDb(m.primary_level_db);
      document.getElementById("secondary-db").textContent = formatDb(m.secondary_level_db);
      document.getElementById("output-db").textContent = formatDb(m.output_level_db);

      document.getElementById("primary-meter").style.width =
        dbToPercent(m.primary_level_db) + "%";
      document.getElementById("secondary-meter").style.width =
        dbToPercent(m.secondary_level_db) + "%";
      document.getElementById("output-meter").style.width =
        dbToPercent(m.output_level_db) + "%";

      const duckDb = currentSettings ? currentSettings.duck_amount_db : 0;
      document.getElementById("duck-amount-label").textContent =
        duckDb.toFixed(0) + " dB";

      const clip = document.getElementById("clipping-indicator");
      clip.style.display = m.clipping ? "block" : "none";
    });

    socket.on("status", (s) => {
      const t = [];
      t.push(s.running ? "Running" : "Stopped");
      if (s.samplerate) t.push(s.samplerate + " Hz");
      if (s.latency_ms) t.push(s.latency_ms.toFixed(1) + " ms buffer");
      if (s.uptime_seconds) t.push("Uptime " + Math.floor(s.uptime_seconds) + "s");
      document.getElementById("status-line").textContent = t.join(" • ");
    });

    socket.on("disconnect", () => {
      document.getElementById("status-line").textContent = "Disconnected from backend.";
    });
  </script>
</body>
</html>
EOF

echo ""
echo "➡ Creating Python virtual environment..."

cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install flask flask-socketio eventlet numpy jack-client
deactivate

echo ""
echo "➡ Creating systemd user service: $SERVICE_FILE"

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Audio Ducking System
After=pipewire.service jack.service

[Service]
Type=simple
Environment=PYTHONUNBUFFERED=1
Environment=LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu/pipewire-0.3/jack:\$LD_LIBRARY_PATH
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/audio_ducker.py
Restart=on-failure
RestartSec=3
WorkingDirectory=$INSTALL_DIR
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=default.target
EOF

echo ""
echo "➡ Enabling and starting systemd user service..."

systemctl --user daemon-reload
systemctl --user enable audio-ducker
systemctl --user restart audio-ducker

echo ""
echo "➡ Checking service status..."
systemctl --user status audio-ducker --no-pager --full || true

echo ""
echo "========================================="
echo " Install complete!"
echo "-----------------------------------------"
echo " Web UI:   http://<raspberry-pi-ip>:5000"
echo " Logs:     $LOG_FILE"
echo ""
echo " NOTE:"
echo "  - This backend expects a JACK/PipeWire-JACK server to be running."
echo "  - If you use PipeWire, make sure your desktop session has PipeWire"
echo "    JACK enabled, or start jackd via qjackctl."
echo ""
echo " You can replace the generated templates/index.html with your own"
echo " fancier UI at any time – just keep the Socket.IO event names and"
echo " /api endpoints the same."
echo "========================================="
