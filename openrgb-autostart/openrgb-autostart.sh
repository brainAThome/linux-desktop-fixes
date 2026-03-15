#!/bin/bash
# OpenRGB Autostart Script
# Starts the OpenRGB server minimized, waits for USB device initialization,
# then loads a saved lighting profile.
#
# Problem: When OpenRGB is started with --profile at boot, the profile
# is applied before USB/I2C controllers are fully initialized by the kernel.
# This causes the profile to be partially or completely ignored.
#
# Solution: Start OpenRGB server first (without profile), wait for device
# initialization, then load the profile via a second OpenRGB client call.

# ──── Configuration ────────────────────────────────────────────────────────────
# Name of the OpenRGB profile to load (as saved in OpenRGB's profile manager)
PROFILE="meins"

# Seconds to wait before starting OpenRGB (for USB/I2C controller enumeration)
USB_DELAY=15

# Seconds to wait after starting the server before loading the profile
PROFILE_DELAY=5
# ───────────────────────────────────────────────────────────────────────────────

# 1. Wait for USB controllers to be fully recognized by the kernel
sleep "$USB_DELAY"

# 2. Start OpenRGB in server mode, minimized to system tray (no profile yet!)
/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=openrgb \
    org.openrgb.OpenRGB --startminimized --server &

# 3. Wait for OpenRGB to finish its internal device discovery (I2C, USB, HID)
sleep "$PROFILE_DELAY"

# 4. Load the profile by connecting to the already-running server
/usr/bin/flatpak run --branch=stable --arch=x86_64 --command=openrgb \
    org.openrgb.OpenRGB --profile "$PROFILE"
