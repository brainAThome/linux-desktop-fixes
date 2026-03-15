#!/bin/bash
# fix-audio-resume.sh — Restart PipeWire audio stack after suspend/resume
#
# Problem: USB audio devices get disconnected during suspend and re-enumerate
# on resume. PipeWire and WirePlumber hold stale device references and fail
# to reconnect to the re-enumerated devices. Result: no audio after resume.
#
# Solution: After resume, wait for USB re-enumeration to complete, then
# restart the PipeWire audio stack for all active user sessions.
#
# This script is called by the fix-audio-resume.service systemd unit.

# Wait for USB devices to fully re-enumerate and stabilize after resume
sleep 3

# Find all user sessions with an active PipeWire socket and restart their stack
loginctl list-sessions --no-legend | while read -r _session uid user _rest; do
    if [ -S "/run/user/$uid/pipewire-0" ]; then
        logger -t fix-audio-resume "Restarting PipeWire for $user (UID $uid)"
        runuser -u "$user" -- env XDG_RUNTIME_DIR="/run/user/$uid" \
            systemctl --user restart pipewire.service wireplumber.service \
            pipewire-pulse.service filter-chain.service 2>&1 | \
            logger -t fix-audio-resume || true
        logger -t fix-audio-resume "PipeWire restart complete for $user"
    fi
done
