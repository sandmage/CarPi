# 🧹 Uninstalling CarPi / Audio Ducker

> Complete guide to safely removing the CarPi Audio Ducker system from your Raspberry Pi.

The uninstaller is safe, reversible, and preserves your repository for future reinstallation. You have full control over what gets removed.

---

## 📋 Table of Contents

- [Quick Uninstall](#-quick-uninstall)
- [What Gets Removed](#-what-gets-removed)
- [What Gets Preserved](#-what-gets-preserved)
- [Step-by-Step Uninstall](#-step-by-step-uninstall)
- [Verification](#-verification)
- [Partial Removal](#-partial-removal)
- [Complete Removal](#-complete-removal)
- [Reinstalling](#-reinstalling)
- [Troubleshooting](#-troubleshooting)

---

## 🚫 Quick Uninstall

For most users, this is all you need:

```bash
cd ~/CarPi
./uninstall.sh
```

**What this does:**
- ✅ Stops the running service
- ✅ Disables auto-start on boot
- ✅ Removes systemd service files
- ✅ Deletes configuration and log files
- ✅ Removes helper scripts
- ✅ Deletes Python virtual environment
- ❌ **Keeps** your source code and repository

**Time required:** ~30 seconds

---

## 🗑️ What Gets Removed

The uninstaller removes the following components:

### Service Components
```
~/.config/systemd/user/audio-ducker.service  # Systemd service file
```

### Configuration & Logs
```
~/audio_ducker_config.json                   # Main config file
~/CarPi/audio_ducker_config.json            # Repo config backup
~/CarPi/audio-ducker.log                    # Application logs
~/CarPi/carpi.log                           # Alternative log file
```

### Helper Scripts
```
~/autoconnect.sh                             # JACK routing script
~/reboot_check.sh                            # Validation script
```

### Python Environment
```
~/CarPi/venv/                               # Complete virtual environment
```

---

## 💾 What Gets Preserved

The uninstaller **keeps** the following to allow easy reinstallation:

### Source Code & Repository
```
~/CarPi/                                     # Main repository folder
~/CarPi/audio_ducker.py                     # Core application
~/CarPi/templates/                          # Web UI templates
~/CarPi/install.sh                          # Installer script
~/CarPi/uninstall.sh                        # This uninstaller
~/CarPi/README.md                           # Documentation
```

### Why?
- **Easy reinstallation** - Just run `./install.sh` again
- **Version control** - Keep your Git history
- **Customizations** - Preserve any code changes you made
- **Development** - Continue working on the project

---

## 📝 Step-by-Step Uninstall

### 1. Navigate to the CarPi Directory
```bash
cd ~/CarPi
```

### 2. Run the Uninstaller
```bash
./uninstall.sh
```

### 3. Review the Output
The uninstaller will display each action it takes:
```
Stopping audio-ducker service...
Disabling audio-ducker service...
Removing systemd service file...
Removing configuration files...
Removing helper scripts...
Removing Python virtual environment...
Uninstall complete!
```

### 4. Verify Removal (Optional)
```bash
systemctl --user status audio-ducker
```

**Expected output:**
```
Unit audio-ducker.service could not be found.
```

---

## ✅ Verification

### Check Service Status
Verify the service is completely removed:

```bash
systemctl --user status audio-ducker
```

**Success:** `Unit audio-ducker.service could not be found.`

### Check for Running Processes
Ensure no CarPi processes are running:

```bash
ps aux | grep audio_ducker
```

**Success:** Only shows the grep command itself.

### Check for Lingering Files
Verify configuration files are removed:

```bash
ls -la ~/audio_ducker_config.json
ls -la ~/.config/systemd/user/audio-ducker.service
```

**Success:** `No such file or directory`

### Check JACK Connections
Verify JACK ports are disconnected:

```bash
jack_lsp -c | grep CarPi
# or
pw-jack jack_lsp -c | grep CarPi
```

**Success:** No CarPi ports listed.

---

## 🔧 Partial Removal

If you only want to remove specific components:

### Stop Service Without Uninstalling
```bash
systemctl --user stop audio-ducker
systemctl --user disable audio-ducker
```

### Remove Only Logs
```bash
rm -f ~/CarPi/audio-ducker.log ~/CarPi/carpi.log
```

### Remove Only Configuration
```bash
rm -f ~/audio_ducker_config.json
rm -f ~/CarPi/audio_ducker_config.json
```

### Remove Only Virtual Environment
```bash
rm -rf ~/CarPi/venv
```

### Remove Only Helper Scripts
```bash
rm -f ~/autoconnect.sh ~/reboot_check.sh
```

---

## 🧨 Complete Removal

⚠️ **Warning:** This permanently deletes everything, including your source code and any customizations.

### Option 1: Delete Repository Only
```bash
rm -rf ~/CarPi
```

### Option 2: Complete Cleanup
Remove the repository and all systemd files:

```bash
# Remove repository
rm -rf ~/CarPi

# Remove any lingering systemd files
rm -f ~/.config/systemd/user/audio-ducker.service
rm -f ~/.config/systemd/user/carpi.service

# Reload systemd
systemctl --user daemon-reload

# Remove helper scripts (if they exist)
rm -f ~/autoconnect.sh ~/reboot_check.sh

# Remove any config files
rm -f ~/audio_ducker_config.json
rm -f ~/carpi_config.json
```

### Verify Complete Removal
```bash
# Check for any remaining files
find ~ -name "*audio*ducker*" -o -name "*carpi*" 2>/dev/null
find ~/.config/systemd/user/ -name "*audio*" -o -name "*carpi*" 2>/dev/null
```

---

## 🔄 Reinstalling

After uninstalling, you can easily reinstall CarPi:

### If You Kept the Repository
```bash
cd ~/CarPi
./install.sh
```

### If You Deleted the Repository
```bash
cd ~
git clone https://github.com/sandmage/CarPi.git
cd CarPi
./install.sh
```

**Your previous settings will be lost** if you deleted `audio_ducker_config.json`. The installer will create fresh defaults.

---

## 🔍 Troubleshooting

### Uninstaller Won't Run

**Error:** `Permission denied`

**Solution:**
```bash
chmod +x uninstall.sh
./uninstall.sh
```

### Service Won't Stop

**Error:** Service fails to stop

**Solution:** Force stop and disable:
```bash
systemctl --user stop audio-ducker --force
systemctl --user disable audio-ducker --force
systemctl --user daemon-reload
```

### Files Still Present After Uninstall

**Issue:** Configuration files remain

**Solution:** Manually remove them:
```bash
rm -f ~/audio_ducker_config.json
rm -f ~/CarPi/audio_ducker_config.json
rm -f ~/.config/systemd/user/audio-ducker.service
systemctl --user daemon-reload
```

### JACK Ports Still Showing

**Issue:** CarPi ports still visible in JACK

**Solution:** Restart JACK/PipeWire:
```bash
# For PipeWire
systemctl --user restart pipewire pipewire-pulse

# For JACK
killall jackd
# Then restart your JACK server
```

### Cannot Delete Virtual Environment

**Error:** `Directory not empty` or permission errors

**Solution:** Force removal:
```bash
chmod -R u+w ~/CarPi/venv
rm -rf ~/CarPi/venv
```

### Systemd Still Shows Service

**Issue:** Service still appears in `systemctl --user list-units`

**Solution:** Reload systemd daemon:
```bash
systemctl --user daemon-reload
systemctl --user reset-failed
```

---

## 📋 Uninstall Checklist

Use this checklist to ensure complete removal:

- [ ] Service stopped: `systemctl --user status audio-ducker` shows "could not be found"
- [ ] No running processes: `ps aux | grep audio_ducker` shows nothing
- [ ] Config files removed: `~/audio_ducker_config.json` deleted
- [ ] Log files removed: `~/CarPi/*.log` deleted
- [ ] Helper scripts removed: `~/autoconnect.sh` and `~/reboot_check.sh` deleted
- [ ] Virtual environment removed: `~/CarPi/venv/` deleted
- [ ] Systemd service removed: `~/.config/systemd/user/audio-ducker.service` deleted
- [ ] JACK ports cleared: No CarPi ports in `jack_lsp` output
- [ ] (Optional) Repository removed: `~/CarPi/` deleted

---

## 📞 Need Help?

If you encounter issues during uninstallation:

- **Check logs:** `journalctl --user -u audio-ducker -n 100`
- **GitHub Issues:** [Report a problem](https://github.com/sandmage/CarPi/issues)
- **Discussions:** [Ask the community](https://github.com/sandmage/CarPi/discussions)

---

## 🔙 Related Documentation

- [Installation Guide](README.md#installation)
- [Quick Start Guide](QUICKSTART.md)
- [Troubleshooting](README.md#troubleshooting)
- [Contributing](README.md#contributing)

---

<p align="center">
  <sub>Changed your mind? Reinstalling is just one command away!</sub>
</p>
