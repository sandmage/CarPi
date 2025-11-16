🔥 CarPi – Real-Time Audio Ducker for Raspberry Pi

A real-time dual-source audio ducking engine with a modern Web UI, designed for in-car audio systems or home AV processing.
Built around JACK, PipeWire, Python, and Flask + WebSockets.

This system automatically lowers (“ducks”) audio from a secondary source (ex: MS210x HDMI-to-USB capture, radio, media player) whenever a primary source (ex: CarPlay, navigation, phone call audio) becomes active — similar to a professional broadcast mixer.

⸻

✨ Features

🔊 Audio Processing
	•	Real-time ducking with:
	•	Threshold
	•	Attack
	•	Release
	•	Hold
	•	Duck depth (amount)
	•	Independent gain for:
	•	Primary
	•	Secondary
	•	Output path
	•	Optional Compressor & Limiter
	•	Fast, stable, low-latency audio pipeline
	•	Automatic safe recovery after JACK restarts

🖥 Web UI Dashboard
	•	Live VU meters (Primary / Secondary / Output)
	•	Real-time settings sync with WebSockets
	•	HTTP polling fallback for Safari/iOS
	•	System status indicators (CPU, Rate, Latency, Uptime)
	•	Autoconnect routing panel
	•	Restart system / View logs / Reset defaults

🔧 Auto-Routing & System Features
	•	Auto-connects JACK ports on boot
	•	Automatic JACK recovery
	•	Systemd user service for always-running operation
	•	Logging, metrics API, settings persistence

⸻

🚀 Installation

1. Clone the repository

git clone https://github.com/sandmage/CarPi.git

cd CarPi

2. Run the installer

chmod +x install.sh

./install.sh

What the installer does:
	•	Installs system dependencies
	•	Creates Python virtualenv
	•	Installs Python requirements
	•	Installs + enables the carpi.service systemd user service
	•	Auto-creates missing config
	•	Starts the CarPi audio engine
	•	Enables boot persistence

⸻

🌐 Accessing the Web Dashboard

On the Pi:

http://localhost:5000

From your phone or another device:

http://<raspberry-pi-ip>:5000

(mDNS carpi.local support coming soon)

⸻

🔊 Audio Routing (Default)

The installer autoconnects:

Primary source (CarPlay decoder)

system:capture_3 → CarPi:primary_in_L
system:capture_4 → CarPi:primary_in_R

Secondary source (MS210x Line-In / HDMI capture)

system:capture_1 → CarPi:secondary_in_L
system:capture_2 → CarPi:secondary_in_R

Output (Amp / DAC / AUX)

CarPi:output_L → system:playback_1
CarPi:output_R → system:playback_2

pw-jack qjackctl

or the Web UI’s “Reconnect Audio” button.

⸻

🧪 Post-Reboot Validation

If you want to confirm everything came up cleanly:

./reboot_check.sh

This validates:
	•	Service running?
	•	Ports connected?
	•	Audio flowing?
	•	Web UI reachable?

⸻

📁 Project Structure

CarPi/
│
├── audio_ducker.py           # Main DSP engine
├── templates/
│     └── index.html          # Web UI frontend
├── install.sh                # Installer
├── uninstall.sh              # Full removal script
├── autoconnect.sh            # JACK/PipeWire routing
├── reboot_check.sh           # Reboot validator
├── README.md                 # Full documentation
└── QUICKSTART.md             # Short instructions


⸻

🛠 Updating

To pull new updates and apply them:

cd ~/CarPi
git pull
./install.sh


⸻

🧹 Uninstalling

./uninstall.sh

Removes:
	•	systemd service
	•	virtualenv
	•	autoconnect scripts
	•	logs

(Your repo folder stays intact.)

⸻

🛣 Roadmap

Planned Features
	•	🎚️ Multiband Ducking
	•	🤖 AI-powered Voice-ID Routing Trigger
	•	📱 iOS / CarPlay Companion App
	•	🎛 MIDI/HID hardware control
	•	📡 mDNS discovery (carpi.local)
	•	🔄 OTA firmware & software updates
	•	🚘 In-car UI integration (Qt6 / Flutter / React-CarPlay)

⸻

❤️ Credits

Built using:
	•	Python + Flask + NumPy
	•	JACK / PipeWire
	•	Socket.IO
	•	Chart.js
	•	Raspberry Pi OS
	•	❤️ plus way too much coffee

