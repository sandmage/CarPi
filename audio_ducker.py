#!/usr/bin/env python3
"""
Audio Ducking System for Raspberry Pi
- Uses JACK (via PipeWire-JACK) for low-latency audio routing and ducking
- Exposes a web UI via Flask + Socket.IO
- Includes:
  * Auto-routing (MS210x -> secondary, Chromium/CarPlay -> primary, Fosi Q6 outputs)
  * Connection watchdog that periodically re-applies connections
  * /api/autoconnect endpoint for UI button
  * /api/update endpoint for git pull + reinstall
"""

import os
import subprocess
import time
import json
import threading
from collections import deque

import numpy as np
import jack
from jack import JackOpenError

from flask import Flask, render_template, jsonify, request
from flask_socketio import SocketIO

APP_NAME = "CarPi Audio Ducker"
APP_VERSION = "0.9.0"
BUILD_INFO = "local-build"

# -----------------------------------------------------------------------------
# Flask / Socket.IO setup
# -----------------------------------------------------------------------------
app = Flask(__name__)
app.config["SECRET_KEY"] = "audio-ducking-secret"

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
# Audio routing configuration (JACK port names for autoconnect)
# -----------------------------------------------------------------------------
# These names come from your `pw-jack jack_lsp -c` output
AUDIO_CONNECTIONS = [
    # Secondary: MS210x -> AudioDucker secondary inputs
    (
        "MS210x Video Grabber [EasierCAP] Analog Stereo:capture_FL",
        "AudioDucker:secondary_in_L",
    ),
    (
        "MS210x Video Grabber [EasierCAP] Analog Stereo:capture_FR",
        "AudioDucker:secondary_in_R",
    ),

    # Primary: Chromium/CarPlay -> AudioDucker primary inputs
    # (adjust if your CarPlay JACK client name changes)
    ("Chromium:output_FL", "AudioDucker:primary_in_L"),
    ("Chromium:output_FR", "AudioDucker:primary_in_R"),

    # Outputs: AudioDucker -> Fosi Audio Q6 speakers
    (
        "AudioDucker:output_L",
        "Fosi Audio Q6 Analog Stereo:playback_FL",
    ),
    (
        "AudioDucker:output_R",
        "Fosi Audio Q6 Analog Stereo:playback_FR",
    ),
]


def run_autoconnect():
    """
    Try to (re)apply the JACK connections defined in AUDIO_CONNECTIONS
    using PipeWire's JACK layer (via pw-jack jack_connect).

    This is safe to run repeatedly and from a watchdog thread.
    """
    import subprocess

    connected = []
    failed = []

    for src, dst in AUDIO_CONNECTIONS:
        try:
            # Use pw-jack so we talk to PipeWire's JACK server
            result = subprocess.run(
                ["pw-jack", "jack_connect", src, dst],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            # jack_connect may print "already connected" — that's fine
            connected.append(
                {
                    "from": src,
                    "to": dst,
                    "returncode": result.returncode,
                    "stderr": result.stderr.strip(),
                }
            )
        except Exception as e:
            failed.append({"from": src, "to": dst, "error": str(e)})

    return {"connected": connected, "failed": failed}


# -----------------------------------------------------------------------------
# Audio Ducking Engine
# -----------------------------------------------------------------------------
class AudioDucker:
    def __init__(self):
        # Only attach to an already-running JACK server (PipeWire-JACK or jackd)
        # If there is no JACK, this raises JackOpenError and main() exits cleanly.
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

        # VU history (simple peak-hold)
        self.primary_vu_history = deque(maxlen=20)
        self.secondary_vu_history = deque(maxlen=20)
        self.output_vu_history = deque(maxlen=20)
        
        # Latest metrics snapshot for /api/metrics
        self.last_metrics = {
            "primary_level_db": -100.0,
            "secondary_level_db": -100.0,
            "output_level_db": -100.0,
            "primary_peak_db": -100.0,
            "secondary_peak_db": -100.0,
            "output_peak_db": -100.0,
            "duck_amount": 1.0,
            "primary_active": False,
            "clipping": False,
        }

        # JACK callback
        self.client.set_process_callback(self.process)

        # Threads
        self.running = True
        self.monitor_thread = threading.Thread(
            target=self.monitor_loop, daemon=True
        )
        self.connection_thread = threading.Thread(
            target=self.connection_watchdog, daemon=True
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

            # Routing / sources (informational)
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

            # Processing (placeholders)
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
               
                # Save snapshot for /api/metrics
                self.last_metrics = metrics

                # New UI event
                socketio.emit("metrics", metrics)

                # Legacy VU event (not strictly needed but harmless)
                socketio.emit(
                    "vu_update",
                    {
                        "primary": float(primary_db),
                        "secondary": float(secondary_db),
                        "primary_peak": float(primary_peak),
                        "secondary_peak": float(secondary_peak),
                        "duck_amount": float(self.duck_amount),
                        "primary_active": bool(
                            primary_db > self.settings["primary_threshold_db"]
                        ),
                    },
                )

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
    # Connection watchdog
    # -------------------
    def connection_watchdog(self):
        """
        Periodically re-run autoconnect.

        This:
          - Re-applies routing after JACK/PipeWire restarts
          - Fixes any dropped connections
        """
        while self.running:
            try:
                result = run_autoconnect()
                if result.get("failed"):
                    print("Autoconnect errors:", result["failed"])
            except Exception as e:
                print("Autoconnect exception:", e)
            # Re-apply every 10 seconds (safe & idempotent)
            time.sleep(10.0)

    # -------------------
    # Lifecycle
    # -------------------
    def start(self):
        """Activate JACK client and monitoring threads."""
        self.client.activate()
        self.monitor_thread.start()
        self.connection_thread.start()
        print("Audio Ducker started")
        print(f"Primary input:   {self.primary_in.name}, {self.primary_in_r.name}")
        print(f"Secondary input: {self.secondary_in.name}, {self.secondary_in_r.name}")
        print(f"Output:          {self.output_l.name}, {self.output_r.name}")
        print("Connect audio using qjackctl or jack_connect (autoconnect is also enabled).")

    def stop(self):
        """Deactivate JACK and stop threads."""
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

    return jsonify(
        {
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
        }
    )

@app.route("/api/metrics", methods=["GET"])
def api_metrics():
    """Return the latest metrics snapshot."""
    if ducker is None:
        return jsonify({})
    return jsonify(ducker.last_metrics)


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


@app.route("/api/autoconnect", methods=["POST"])
def api_autoconnect():
    """
    Manually trigger autoconnect from the web UI.
    """
    try:
        result = run_autoconnect()
        return jsonify({"status": "ok", **result})
    except Exception as e:
        return jsonify({"status": "error", "error": str(e)}), 500


@app.route("/api/update", methods=["POST"])
def api_update():
    """
    Pull latest code from Git and re-run install.sh.
    Returns JSON status + combined output.
    """
    import subprocess
    
    repo_dir = os.path.dirname(os.path.abspath(__file__))
    
    def run_cmd(cmd, cwd=None):
        result = subprocess.run(
            cmd,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        return result.returncode, result.stdout
    
    # 1) git pull
    code_git, out_git = run_cmd(["git", "pull", "--ff-only"], cwd=repo_dir)
    if code_git != 0:
        return jsonify({
            "status": "error",
            "step": "git_pull",
            "output": out_git,
        }), 500
    
    # 2) ./install.sh
    install_path = os.path.join(repo_dir, "install.sh")
    code_inst, out_inst = run_cmd(["bash", install_path], cwd=repo_dir)
    if code_inst != 0:
        return jsonify({
            "status": "error",
            "step": "install",
            "output": out_inst,
        }), 500
    
    return jsonify({
        "status": "ok",
        "output": out_git + "\n" + out_inst,
    })


# -----------------------------------------------------------------------------
# Main entrypoint
# -----------------------------------------------------------------------------
def main():
    global ducker
    print("Starting Audio Ducking System...")
    print(f"{APP_NAME} v{APP_VERSION} ({BUILD_INFO})")

    try:
        ducker = AudioDucker()
    except JackOpenError as e:
        print("Failed to initialize JACK client:")
        print("  ", e)
        print("Is a JACK or PipeWire-JACK server running?")
        # Exit cleanly (status 0) so systemd doesn't hammer restart loops.
        return

    ducker.start()

    # One immediate autoconnect attempt on startup
    try:
        result = run_autoconnect()
        if result.get("failed"):
            print("Initial autoconnect errors:", result["failed"])
    except Exception as e:
        print("Initial autoconnect exception:", e)

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
