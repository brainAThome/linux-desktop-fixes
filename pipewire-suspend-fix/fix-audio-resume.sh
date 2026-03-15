#!/bin/bash
# fix-audio-resume.sh — Fix audio and reload OpenRGB after resume from suspend
#
# Problem 1: USB audio devices (Yamaha ZG01, Astro A50, etc.) get disconnected
# during suspend and re-enumerate on resume. WirePlumber holds stale device
# references and fails to reconnect.
#
# Problem 2: OpenRGB loses USB device connections during suspend and needs its
# lighting profile reloaded.
#
# Solution: After resume, restart only WirePlumber (not the full PipeWire stack)
# to re-detect USB audio devices while keeping existing audio streams alive.
# Apps using pa_simple (e.g., Minecraft/mcpelauncher) cannot auto-reconnect to
# PipeWire, so a full PipeWire restart would break their audio. WirePlumber-only
# restart preserves all existing streams. After that, reload the OpenRGB profile.
#
# This script is called by the fix-audio-resume.service systemd unit.

# Wait for USB devices to fully re-enumerate and stabilize after resume
sleep 3

# Restart only WirePlumber (session manager) — NOT the full PipeWire stack.
# This re-detects USB audio devices without killing existing audio streams.
loginctl list-sessions --no-legend | while read -r _session uid user _rest; do
    if [ -S "/run/user/$uid/pipewire-0" ]; then
        logger -t fix-audio-resume "Restarting WirePlumber for $user (UID $uid)"
        runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
            systemctl --user restart wireplumber.service 2>&1 | \
            logger -t fix-audio-resume || true
        # Give WirePlumber time to re-detect all USB audio devices
        sleep 2
        logger -t fix-audio-resume "WirePlumber restart complete for $user"
    fi
done

# Wait for USB RGB controllers to re-enumerate after suspend
sleep 5

# Reload OpenRGB profile for each logged-in user running OpenRGB
loginctl list-sessions --no-legend | while read -r _session uid user _rest; do
    if runuser -u "$user" -- pgrep -x openrgb >/dev/null 2>&1; then
        logger -t fix-audio-resume "Reloading OpenRGB profile for $user (UID $uid)"
        runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            /usr/bin/flatpak run --branch=stable --arch=x86_64 \
            --command=openrgb org.openrgb.OpenRGB --profile "meins" 2>&1 | \
            logger -t fix-audio-resume || true
        logger -t fix-audio-resume "OpenRGB profile reload complete for $user"
    fi
done
