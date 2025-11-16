# Audio Ducker for Raspberry Pi  
A real-time dual-source audio ducking engine with a modern Web UI, designed for in-car or home AV installations.  
Built around **JACK**, **PipeWire**, **Python**, and **Flask + WebSockets**.

This system automatically lowers (“ducks”) audio from a secondary source (ex: MS210x video grabber, radio, media player) whenever a primary source (ex: CarPlay, navigation, phone call audio) is detected — just like a professional broadcast mixer.

---

## ✨ Features

### 🔊 Audio Processing
- Real-time ducking with threshold, attack, release, hold, and depth (duck amount)
- Adjustable gain for primary, secondary, and output paths
- Optional compressor + limiter
- Zero-latency direct monitoring
- Safe shutdown and restart handling

### 🖥 Web UI Dashboard
- Live VU meters for primary, secondary, and master output
- Real-time settings sync via WebSockets
- Auto-reconnect and fallback HTTP polling
- Live system status indicators
- Instant Apply / Save system
- Autoconnect routing for JACK/ PipeWire

### 🔧 Auto-Routing & Stability Features
- Automatic JACK port connection on startup
- Auto-recovery if JACK restarts
- Metrics API + WebSocket streaming
- Clean systemd user service for always-on operation

---

## 🚀 Installing

### 1. Clone the repository
```bash
git clone https://github.com/<YOUR_USERNAME>/audio-ducker.git
cd audio-ducker
```

### 2. Run the installer  
```bash
chmod +x install.sh
./install.sh
```

This will:
- Install required packages  
- Create a Python venv in `~/audio-ducker/venv`  
- Install Python dependencies  
- Install + enable the systemd user service  
- Start the ducking engine  
- Launch the web dashboard  

---

## 🌐 Accessing the Web Interface

From the Pi:
```
http://localhost:5000
```

From another device:
```
http://<raspberry-pi-ip>:5000
```

---

## 🔊 Connecting Your Audio Sources

The system auto-routes for the common case:

- **Primary input** (CarPlay decoder / phone):  
  `system:capture_3` → `AudioDucker:primary_in_*`

- **Secondary input** (MS210x / video grabber):  
  `system:capture_1` → `AudioDucker:secondary_in_*`

- **Output** (Amp, DAC, USB sound card):  
  `AudioDucker:output_*` → `system:playback_*`

You can also adjust routing in the web UI or run:

```bash
pw-jack qjackctl
```

---

## 🧪 Verify After Reboot
Run this to confirm everything came back online correctly:

```bash
./validate_reboot.sh
```

(Installer generates this automatically.)

---

## 📁 Project Structure

```
audio-ducker/
│
├── audio_ducker.py           # Main engine
├── templates/
│     └── index.html          # Full Web UI
├── install.sh                # Installer
├── uninstall.sh              # Removes everything
├── README.md                 # This file
└── QUICKSTART.md             # Short version
```

---

## 🛠 Updating

To pull the newest version:

```bash
cd ~/audio-ducker
git pull
./install.sh
```

---

## 🧹 Uninstalling

```bash
./uninstall.sh
```

This stops the service, disables it, and removes installed files (but preserves your repo clone).

---

## 🛣 Roadmap

- Multiband Ducking  
- AI Voice Recognition Input Trigger  
- CarPlay / iOS Companion App  
- MIDI control surface integration  
- OTA Updates via the Web UI  
- mDNS discovery (`carpi.local`)  
- Car dashboard UI integration  

---

## ❤️ Credits

Built with:
- Python + NumPy + Flask + Socket.IO  
- JACK / PipeWire  
- Chart.js  
- Tailwind  
- Raspberry Pi  
