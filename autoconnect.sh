#!/bin/bash

# Audio Ducker Autoconnect Script
# Uses PipeWire JACK (pw-jack)

echo "=== Audio Ducker Autoconnect ==="

# Wait for JACK to be ready
for i in {1..10}; do
    if pw-jack jack_lsp &> /dev/null; then
        echo "JACK is ready."
        break
    fi
    echo "Waiting for JACK..."
    sleep 1
done

# MS210x -> AudioDucker (secondary input)
pw-jack jack_connect "MS210x Video Grabber [EasierCAP] Analog Stereo:capture_FL" "AudioDucker:secondary_in_L" 2>/dev/null
pw-jack jack_connect "MS210x Video Grabber [EasierCAP] Analog Stereo:capture_FR" "AudioDucker:secondary_in_R" 2>/dev/null

# AudioDucker -> Fosi Q6 outputs
pw-jack jack_connect "AudioDucker:output_L" "Fosi Audio Q6 Analog Stereo:playback_FL" 2>/dev/null
pw-jack jack_connect "AudioDucker:output_R" "Fosi Audio Q6 Analog Stereo:playback_FR" 2>/dev/null

echo "Connections applied."
