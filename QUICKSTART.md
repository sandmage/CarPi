# Quickstart — Audio Ducker for Raspberry Pi

The fastest way to get up and running.  
This assumes a clean Raspberry Pi OS system with internet access.

---

## 1. Clone & Install

```bash
git clone https://github.com/<YOUR_USERNAME>/audio-ducker.git
cd audio-ducker
chmod +x install.sh
./install.sh
```

This sets up:
- Python virtual environment  
- JACK + PipeWire support  
- Auto-routing  
- Systemd user service  
- Web dashboard  

---

## 2. Open the Web Interface

On the Pi:
```
http://localhost:5000
```

From another device:
```
http://<raspberry-pi-ip>:5000
```

You’ll see live VU meters, ducking controls, and system status.

---

## 3. Confirm Audio Routing

The installer auto-connects:

- **Primary Source → Ducker primary input**  
- **MS210x → Ducker secondary input**  
- **Ducker output → Amp / DAC**

To view:

```bash
pw-jack jack_lsp -c
```

---

## 4. Save Settings

Any time you adjust sliders or switches in the UI, the system writes them to:
```
~/audio-ducker/settings.json
```

They persist through reboot automatically.

---

## 5. Reboot Test (Optional but Recommended)

```bash
sudo reboot
```

After reboot:

```bash
./validate_reboot.sh
```

Should show ✔ ready, ✔ service running, ✔ audio connected.

---

## 6. Updating in the Future

```bash
cd ~/audio-ducker
git pull
./install.sh
```

---

You’re done — the ducking system now runs automatically on every boot.
