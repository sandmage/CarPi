# 🔥 CarPi – Real-Time Audio Ducker for Raspberry Pi

> A professional-grade dual-source audio ducking engine with modern web interface, purpose-built for in-car audio systems and home AV setups.

CarPi automatically lowers ("ducks") background audio from secondary sources (music, radio, media players) when primary audio becomes active (CarPlay, navigation, phone calls) — just like a broadcast mixer, but for your car.

**Built with:** JACK Audio • PipeWire • Python • Flask • WebSockets

---

## 📋 Table of Contents

- [Features](#-features)
- [Prerequisites](#-prerequisites)
- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Configuration](#-configuration)
- [Audio Routing](#-audio-routing)
- [Web Dashboard](#-web-dashboard)
- [Troubleshooting](#-troubleshooting)
- [Updating](#-updating)
- [Uninstalling](#-uninstalling)
- [Project Structure](#-project-structure)
- [Roadmap](#-roadmap)
- [Contributing](#-contributing)
- [License](#-license)

---

## ✨ Features

### 🔊 Audio Processing Engine
- **Real-time ducking** with professional controls:
  - Threshold detection
  - Attack time (fade-down speed)
  - Release time (fade-up speed)
  - Hold time (minimum duck duration)
  - Duck depth (reduction amount in dB)
- **Independent gain controls** for Primary, Secondary, and Output paths
- **Optional dynamics processing** with Compressor & Limiter
- **Low-latency pipeline** optimized for real-time performance
- **Automatic JACK recovery** for reliable operation

### 🖥️ Web UI Dashboard
- **Live VU meters** showing real-time audio levels (Primary / Secondary / Output)
- **Real-time settings sync** via WebSockets with HTTP fallback for iOS/Safari
- **System monitoring** displaying CPU usage, sample rate, latency, and uptime
- **Audio routing panel** for easy port management
- **Quick actions**: Restart system, view logs, reset to defaults
- **Mobile-responsive design** for phone/tablet access

### 🔧 System Integration
- **Automatic port routing** on startup
- **Systemd service integration** for always-running operation
- **Boot persistence** survives reboots automatically
- **Configuration persistence** settings saved across restarts
- **RESTful API** for metrics and control
- **Comprehensive logging** for debugging and monitoring

---

## 🔧 Prerequisites

### Hardware
- Raspberry Pi 4 or newer (Pi 5 recommended)
- USB audio interface or DAC
- Audio capture device (e.g., MS210x HDMI-to-USB adapter)

### Software
- Raspberry Pi OS (Bullseye or newer)
- JACK Audio Connection Kit or PipeWire with JACK compatibility
- Python 3.7+
- Git

### Recommended Setup
```bash
# Update your system first
sudo apt update && sudo apt upgrade -y

# Ensure you have basic build tools
sudo apt install -y git python3-pip python3-venv
```

---

## 🚀 Installation

### 1. Clone the Repository
```bash
cd ~
git clone https://github.com/sandmage/CarPi.git
cd CarPi
```

### 2. Run the Installer
```bash
chmod +x install.sh
./install.sh
```

**The installer will:**
- ✅ Install system dependencies (JACK, Python packages, etc.)
- ✅ Create and configure Python virtual environment
- ✅ Install Python requirements (Flask, NumPy, Socket.IO, etc.)
- ✅ Set up and enable `carpi.service` systemd user service
- ✅ Generate default configuration file
- ✅ Start the CarPi audio engine
- ✅ Enable auto-start on boot

**Installation time:** ~5-10 minutes depending on your Pi model and internet connection.

---

## 🎯 Quick Start

### 1. Access the Web Dashboard

**On the Raspberry Pi:**
```
http://localhost:5000
```

**From another device on your network:**
```
http://<raspberry-pi-ip>:5000
```

**Finding your Pi's IP:**
```bash
hostname -I
```

### 2. Verify Audio Routing

Open the **Autoconnect** panel in the web UI and click **"Reconnect Audio"** to ensure all ports are properly connected.

### 3. Adjust Ducking Parameters

Start with these recommended settings:
- **Threshold:** -30 dB
- **Attack:** 50 ms
- **Release:** 500 ms
- **Hold:** 200 ms
- **Duck Depth:** -20 dB

Fine-tune based on your audio sources and preferences.

---

## ⚙️ Configuration

### Settings File
Settings are automatically saved to:
```
~/CarPi/settings.json
```

### Audio Routing Configuration
Edit the autoconnect script to match your audio interface:
```bash
nano ~/CarPi/autoconnect.sh
```

**Default routing:**
- **Primary In:** `system:capture_3/4` → CarPlay/Navigation
- **Secondary In:** `system:capture_1/2` → Music/Radio
- **Output:** `system:playback_1/2` → Amplifier/Speakers

### Advanced Configuration

**JACK buffer size and sample rate:**
```bash
# Edit JACK settings (if using JACK directly)
nano ~/.jackdrc
```

**Systemd service tweaks:**
```bash
systemctl --user edit carpi.service
```

---

## 🔊 Audio Routing

### Default Signal Flow

```
┌─────────────┐
│  CarPlay    │ → capture_3/4 → [Primary In] ─┐
└─────────────┘                                │
                                               ├→ [Ducker] → [Output] → playback_1/2 → 🔊 Speakers
┌─────────────┐                                │
│   Radio     │ → capture_1/2 → [Secondary]────┘
└─────────────┘
```

### Viewing Connections

**Command line (PipeWire):**
```bash
pw-jack qjackctl
```

**Web UI:**
Navigate to the **Autoconnect** panel in the dashboard.

### Custom Routing

Modify `autoconnect.sh` to match your specific hardware setup:
```bash
#!/bin/bash
# Example: Different capture ports
jack_connect system:capture_5 CarPi:primary_in_L
jack_connect system:capture_6 CarPi:primary_in_R
```

---

## 🌐 Web Dashboard

### Features Overview

| Feature | Description |
|---------|-------------|
| **VU Meters** | Real-time visual feedback of audio levels |
| **Ducking Controls** | Adjust threshold, attack, release, hold, depth |
| **Gain Controls** | Independent volume for primary, secondary, output |
| **System Stats** | CPU, sample rate, latency, uptime monitoring |
| **Dynamics** | Optional compressor and limiter |
| **Quick Actions** | Restart, view logs, reset settings |

### Mobile Access

The dashboard is fully responsive and works great on phones/tablets. Add it to your home screen for quick access!

**iOS:** Safari → Share → Add to Home Screen  
**Android:** Chrome → Menu → Add to Home Screen

---

## 🔍 Troubleshooting

### Service Won't Start

**Check service status:**
```bash
systemctl --user status carpi.service
```

**View logs:**
```bash
journalctl --user -u carpi.service -n 50
```

**Common fix - restart service:**
```bash
systemctl --user restart carpi.service
```

### No Audio Output

**1. Verify JACK is running:**
```bash
jack_lsp
```

**2. Check port connections:**
```bash
./autoconnect.sh
# or use the "Reconnect Audio" button in Web UI
```

**3. Verify audio interface:**
```bash
aplay -l  # List playback devices
arecord -l  # List capture devices
```

### Web UI Not Accessible

**1. Check if service is running:**
```bash
systemctl --user is-active carpi.service
```

**2. Verify port 5000 is listening:**
```bash
sudo netstat -tlnp | grep 5000
```

**3. Check firewall (if enabled):**
```bash
sudo ufw allow 5000/tcp
```

### High CPU Usage

- Reduce JACK buffer size (increases latency but lowers CPU)
- Disable compressor/limiter if not needed
- Check for other CPU-intensive processes

### Post-Reboot Validation

Use the included validation script:
```bash
./reboot_check.sh
```

This checks:
- ✅ Service running
- ✅ Ports connected
- ✅ Audio flowing
- ✅ Web UI accessible

---

## 🔄 Updating

Pull the latest changes and re-run the installer:

```bash
cd ~/CarPi
git pull
./install.sh
```

Your settings will be preserved.

---

## 🧹 Uninstalling

Complete removal:

```bash
cd ~/CarPi
./uninstall.sh
```

**This removes:**
- Systemd service
- Python virtual environment
- Autoconnect scripts
- Log files

**This keeps:**
- The repository folder (for manual deletion)
- Your `settings.json` (for backup)

---

## 📁 Project Structure

```
CarPi/
├── audio_ducker.py           # Core DSP engine and Flask server
├── templates/
│   └── index.html            # Web UI frontend (HTML/CSS/JS)
├── static/                   # (Auto-created) Static web assets
├── install.sh                # One-command installer
├── uninstall.sh              # Complete removal script
├── autoconnect.sh            # JACK port routing automation
├── reboot_check.sh           # Post-boot validation tool
├── requirements.txt          # Python dependencies
├── settings.json             # (Auto-created) User configuration
├── carpi.log                 # (Auto-created) Application logs
├── README.md                 # This file
└── LICENSE                   # Project license
```

---

## 🛣️ Roadmap

### Planned Features

- [ ] 🎚️ **Multiband Ducking** – Frequency-specific ducking for cleaner mixes
- [ ] 🤖 **AI Voice Detection** – Smarter routing based on voice activity
- [ ] 📱 **iOS/CarPlay App** – Native mobile interface
- [ ] 🎛️ **MIDI/HID Control** – Physical knobs and buttons support
- [ ] 📡 **mDNS Support** – Access via `carpi.local`
- [ ] 🔄 **OTA Updates** – Automatic firmware and software updates
- [ ] 🚘 **CarPlay UI Integration** – Native in-dash interface
- [ ] 📊 **Advanced Analytics** – Audio quality metrics and history
- [ ] 🎵 **Source Detection** – Auto-identify audio content type
- [ ] ☁️ **Cloud Sync** – Backup and restore settings across devices

### Completed ✅

- Real-time audio ducking engine
- Web-based dashboard with live meters
- Systemd service integration
- Automatic audio routing
- Configuration persistence

---

## 🤝 Contributing

Contributions are welcome! Whether it's bug reports, feature requests, or code contributions.

### How to Contribute

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/AmazingFeature`)
3. **Commit** your changes (`git commit -m 'Add some AmazingFeature'`)
4. **Push** to the branch (`git push origin feature/AmazingFeature`)
5. **Open** a Pull Request

### Bug Reports

Please include:
- CarPi version
- Raspberry Pi model
- OS version
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## ❤️ Credits

**Built with:**
- [Python](https://python.org) + [Flask](https://flask.palletsprojects.com/) + [NumPy](https://numpy.org)
- [JACK Audio Connection Kit](https://jackaudio.org/) / [PipeWire](https://pipewire.org/)
- [Socket.IO](https://socket.io/) for real-time communication
- [Chart.js](https://www.chartjs.org/) for beautiful visualizations
- [Raspberry Pi OS](https://www.raspberrypi.com/software/)

**Made with ❤️ (and way too much coffee)**

---

## 📞 Support

- **Issues:** [GitHub Issues](https://github.com/sandmage/CarPi/issues)
- **Discussions:** [GitHub Discussions](https://github.com/sandmage/CarPi/discussions)
- **Email:** [your-email@example.com]

---

<p align="center">
  <sub>If you find CarPi useful, consider giving it a ⭐️ on GitHub!</sub>
</p>
