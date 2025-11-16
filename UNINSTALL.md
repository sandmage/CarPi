# Uninstalling Audio Ducker / CarPi

This guide explains how to completely or partially remove the Audio Ducker system from your Raspberry Pi.

The uninstaller is safe, reversible, and will not remove your cloned GitHub repository unless you choose to delete it manually.

---

## 🚫 Quick Uninstall

From the Pi:

```bash
cd ~/audio-ducker
./uninstall.sh

This removes the service, its systemd entry, logs, config files, and optional helper scripts.

⸻

🧹 What the Uninstaller Removes

Running ./uninstall.sh performs the following:

🛑 Stops the Running Service
	•	audio-ducker.service is stopped cleanly.

🚫 Disables Startup
	•	The systemd user service is disabled so it no longer runs at boot/login.

🗑 Removes Installed Files

The uninstaller will delete:
	•	~/.config/systemd/user/audio-ducker.service
	•	~/audio_ducker_config.json
	•	~/audio-ducker/audio_ducker_config.json
	•	~/audio-ducker/audio-ducker.log
	•	~/autoconnect.sh (routing helper)
	•	~/reboot_check.sh (reboot validator)
	•	~/audio-ducker/venv/ (Python virtual environment)

⸻

❗ What is NOT Removed

To keep your development environment intact, the following are not deleted:
	•	Your cloned GitHub repo folder:
~/audio-ducker/
	•	Your customized audio_ducker.py
	•	Your templates/index.html Web UI
	•	README, QUICKSTART, install scripts, etc.

This means you can reinstall later by running:

cd ~/audio-ducker
./install.sh


⸻

🧨 Full Removal (Optional)

If you want to wipe absolutely everything:

rm -rf ~/audio-ducker

This deletes the source code and your local Git repo.

⸻

🧭 Verification

After uninstalling, you can verify that the service is gone:

systemctl --user status audio-ducker

Expected output:

Unit audio-ducker.service could not be found.


