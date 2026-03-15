# Linux Desktop Fixes

Fixes for common Linux desktop issues on KDE Plasma / Kubuntu systems with NVIDIA GPUs, USB audio devices, and RGB hardware.

---

## Table of Contents

- [Fix 1: OpenRGB Autostart with Reliable Profile Loading](#fix-1-openrgb-autostart-with-reliable-profile-loading)
  - [The Problem](#the-problem)
  - [Root Cause](#root-cause)
  - [The Solution](#the-solution)
  - [Installation](#installation)
  - [Configuration](#configuration)
  - [How It Works](#how-it-works)
  - [Troubleshooting](#troubleshooting-openrgb)
- [Fix 2: Suspend/Resume Fix (Audio + OpenRGB)](#fix-2-suspendresume-fix-audio--openrgb)
  - [The Problem](#the-problem-1)
  - [Root Cause](#root-cause-1)
  - [The Solution](#the-solution-1)
  - [Installation](#installation-1)
  - [How It Works](#how-it-works-1)
  - [Verification](#verification)
  - [Troubleshooting](#troubleshooting-audio)
- [Tested Environment](#tested-environment)
- [Development](#development)
- [License](#license)

---

## Fix 1: OpenRGB Autostart with Reliable Profile Loading

### The Problem

When OpenRGB is configured to autostart at login with a lighting profile (e.g., via `--profile "meins"`), the profile is **partially or completely ignored**. Some or all RGB devices retain their default colors instead of the saved profile.

This happens inconsistently — sometimes it works, sometimes it doesn't — making it appear like a random bug.

### Root Cause

The issue is a **timing race condition** between three concurrent startup processes:

```
Boot / Login
    │
    ├─ Kernel: USB controller enumeration (takes 5–15 seconds)
    │   └─ I2C bus scanning
    │   └─ USB HID device registration
    │   └─ Motherboard SMBus initialization
    │
    ├─ Desktop Environment: launches autostart entries
    │   └─ OpenRGB starts with --profile
    │       └─ Scans for devices (but USB isn't ready yet!)
    │       └─ Finds only partial device list
    │       └─ Applies profile to found devices only
    │       └─ Late-discovered devices get no profile → wrong colors
    │
    └─ Result: Incomplete profile application
```

**Specifically:**

1. **USB controllers take time to enumerate** — I2C/SMBus controllers on NVIDIA GPUs and motherboards (ASUS Aura, MSI Mystic Light, etc.) take 5–15 seconds after boot to fully register
2. **OpenRGB starts too early** — The desktop autostart fires before all controllers are ready
3. **Single-pass profile loading** — `openrgb --profile` applies the profile once to whatever devices are currently detected, then exits. Devices that appear later are missed
4. **No retry mechanism** — OpenRGB does not re-scan for devices after the initial load

### The Solution

A two-phase startup script that separates server startup from profile loading:

```
Phase 1: Wait → Start OpenRGB server (no profile)
Phase 2: Wait → Load profile via client connection to running server
```

#### Files

| File | Purpose | Install Location |
|------|---------|------------------|
| `openrgb-autostart.sh` | Two-phase startup script | `~/.local/bin/` |
| `openrgb-autostart.desktop` | KDE/GNOME autostart entry | `~/.config/autostart/` |

### Installation

```bash
# 1. Copy the startup script
cp openrgb-autostart/openrgb-autostart.sh ~/.local/bin/
chmod +x ~/.local/bin/openrgb-autostart.sh

# 2. Copy the autostart entry
cp openrgb-autostart/openrgb-autostart.desktop ~/.config/autostart/

# 3. Edit the .desktop file to use your actual home directory
sed -i "s|\$HOME|$HOME|g" ~/.config/autostart/openrgb-autostart.desktop

# 4. Remove any existing OpenRGB autostart entries that might conflict
rm -f ~/.config/autostart/org.openrgb.OpenRGB.desktop 2>/dev/null
```

### Configuration

Edit `~/.local/bin/openrgb-autostart.sh` and adjust these variables:

```bash
# Name of your saved OpenRGB profile
PROFILE="meins"

# Seconds to wait for USB/I2C controllers (increase if devices are missed)
USB_DELAY=15

# Seconds for OpenRGB to scan devices before loading profile
PROFILE_DELAY=5
```

#### Tuning the Delays

| Symptom | Fix |
|---------|-----|
| Some devices still missing → wrong colors | Increase `USB_DELAY` (try 20–30) |
| Profile loads but colors are wrong on some devices | Increase `PROFILE_DELAY` (try 8–10) |
| Everything works but startup feels slow | Decrease `USB_DELAY` to 10 |
| No devices found at all | Check if OpenRGB Flatpak is installed: `flatpak list \| grep openrgb` |

#### Using Native OpenRGB Instead of Flatpak

If you installed OpenRGB via PPA or AppImage instead of Flatpak, change the commands in the script:

```bash
# Replace Flatpak commands:
/usr/bin/flatpak run ... org.openrgb.OpenRGB --startminimized --server &
/usr/bin/flatpak run ... org.openrgb.OpenRGB --profile "$PROFILE"

# With native commands:
openrgb --startminimized --server &
openrgb --profile "$PROFILE"
```

### How It Works

```
Login
  │
  ▼
┌────────────────────────────────────────────────────────────────┐
│ openrgb-autostart.sh                                           │
│                                                                │
│ 1. sleep $USB_DELAY (15s)                                      │
│    └─ Kernel finishes USB/I2C/SMBus enumeration                │
│    └─ All RGB controllers registered                           │
│                                                                │
│ 2. openrgb --startminimized --server &                         │
│    └─ OpenRGB starts in background                             │
│    └─ Scans all I2C, USB HID, SMBus devices                   │
│    └─ Finds ALL controllers (because we waited)                │
│    └─ Server socket listening on port 6742                     │
│                                                                │
│ 3. sleep $PROFILE_DELAY (5s)                                   │
│    └─ OpenRGB finishes device initialization                   │
│                                                                │
│ 4. openrgb --profile "$PROFILE"                                │
│    └─ Connects to running server via SDK port                  │
│    └─ Server already has complete device list                  │
│    └─ Profile applied to ALL devices ✓                         │
└────────────────────────────────────────────────────────────────┘
```

### Troubleshooting (OpenRGB)

#### Profile not loading at all

```bash
# Check if the script is executable
ls -la ~/.local/bin/openrgb-autostart.sh

# Test the script manually
~/.local/bin/openrgb-autostart.sh

# Check if OpenRGB Flatpak is installed
flatpak list | grep -i openrgb

# List available profiles
flatpak run org.openrgb.OpenRGB --list-profiles
```

#### OpenRGB shows 0 devices

```bash
# Check I2C permissions
ls -la /dev/i2c-*

# Add yourself to the i2c group
sudo usermod -aG i2c $USER
# Then logout and login again

# Check if i2c-dev module is loaded
lsmod | grep i2c_dev
# If not loaded:
sudo modprobe i2c-dev
echo "i2c-dev" | sudo tee /etc/modules-load.d/i2c-dev.conf
```

#### Profile applies partially (some devices wrong)

Increase the delays stepwise:
```bash
# In openrgb-autostart.sh:
USB_DELAY=25     # Was 15
PROFILE_DELAY=10 # Was 5
```

---

## Fix 2: Suspend/Resume Fix (Audio + OpenRGB)

### The Problem

After resuming from **suspend** (sleep) or **hibernate**:

1. **Audio**: USB audio devices stop working. No sound output, even though the system tray shows devices as connected and volume is not muted.
2. **OpenRGB**: RGB lighting reverts to default colors — the saved profile is lost.

A manual `systemctl --user restart wireplumber` fixes audio; manually running `openrgb --profile "meins"` fixes RGB.

### Root Cause

When the system enters suspend:

1. **USB audio devices are electrically disconnected** — the USB bus is powered down
2. **PipeWire and WirePlumber keep references** to the now-disconnected devices
3. **On resume, USB devices re-enumerate** — they get new device paths (`/dev/snd/pcmC2D0p` → `/dev/snd/pcmC3D0p`)
4. **PipeWire still holds the old references** — attempts to write audio data to the old (now invalid) device paths
5. **Result: audio writes silently fail** — no error message, just silence

```
Before Suspend:
  PipeWire → /dev/snd/pcmC2D0p → USB Audio Device ✓

During Suspend:
  USB bus powers down → device disconnected

After Resume:
  USB re-enumerates → new path /dev/snd/pcmC3D0p
  PipeWire still → /dev/snd/pcmC2D0p → GONE ✗ (silence)
```

**NVIDIA complication:** On systems with NVIDIA GPUs, the `nvidia-suspend.service` and `nvidia-resume.service` add additional timing complexity. The audio fix must run **after** the NVIDIA resume service completes, because the NVIDIA driver's resume process can trigger additional USB re-enumeration.

### The Solution

A systemd service that automatically:

1. **Restarts WirePlumber** (only the session manager, not the full PipeWire stack) — this re-detects USB audio devices while keeping existing audio streams alive
2. **Reloads the OpenRGB profile** — restores RGB lighting to the saved configuration

> **Why WirePlumber-only?** Apps using `pa_simple` (e.g., Minecraft Bedrock via mcpelauncher) cannot automatically reconnect to PipeWire. A full PipeWire restart would break their audio until the app is restarted. WirePlumber-only restart preserves all existing streams while fixing USB device routing.

#### Files

| File | Purpose | Install Location |
|------|---------|------------------|
| `fix-audio-resume.sh` | Restart WirePlumber + reload OpenRGB profile | `/usr/lib/systemd/system-sleep/` |
| `fix-audio-resume.service` | systemd unit (runs after resume) | `/etc/systemd/system/` |

### Installation

```bash
# 1. Copy the script (requires root)
sudo cp pipewire-suspend-fix/fix-audio-resume.sh /usr/lib/systemd/system-sleep/
sudo chmod 755 /usr/lib/systemd/system-sleep/fix-audio-resume.sh

# 2. Copy the systemd service
sudo cp pipewire-suspend-fix/fix-audio-resume.service /etc/systemd/system/

# 3. Reload systemd and enable the service
sudo systemctl daemon-reload
sudo systemctl enable fix-audio-resume.service

# 4. Verify it's enabled
systemctl is-enabled fix-audio-resume.service
# Expected output: enabled
```

### How It Works

```
System resumes from suspend
  │
  ▼
systemd runs resume services in order:
  │
  ├─ nvidia-resume.service (NVIDIA driver restore)
  │
  ├─ fix-audio-resume.service (our service, runs AFTER nvidia)
  │   │
  │   ▼
  │ ┌──────────────────────────────────────────────────────────┐
  │ │ fix-audio-resume.sh                                      │
  │ │                                                          │
  │ │ Phase 1: Audio Fix                                       │
  │ │ 1. sleep 3                                               │
  │ │    └─ Wait for USB devices to re-enumerate               │
  │ │                                                          │
  │ │ 2. For each session with PipeWire socket:                │
  │ │    └─ Restart WirePlumber ONLY (not full PipeWire)       │
  │ │    └─ Existing audio streams stay alive ✓                │
  │ │    └─ USB devices re-detected ✓                          │
  │ │    └─ sleep 2 (let WirePlumber settle)                   │
  │ │                                                          │
  │ │ Phase 2: OpenRGB Fix                                     │
  │ │ 3. sleep 5                                               │
  │ │    └─ Wait for USB RGB controllers to re-enumerate       │
  │ │                                                          │
  │ │ 4. For each session running OpenRGB:                     │
  │ │    └─ flatpak run openrgb --profile "meins"              │
  │ │    └─ RGB lighting restored ✓                            │
  │ └──────────────────────────────────────────────────────────┘
  │
  ▼
Desktop session: audio + RGB fully functional
```

#### Why Only WirePlumber (Not the Full Stack)?

| Service | Role | Restart Needed? |
|---------|------|----------------|
| `wireplumber.service` | Session/policy manager, device routing | **Yes** — holds stale USB device references |
| `pipewire.service` | Core audio/video server | **No** — streams survive if WirePlumber reconnects devices |
| `pipewire-pulse.service` | PulseAudio compatibility layer | **No** — automatically picks up WirePlumber changes |
| `filter-chain.service` | DSP/effects chain | **No** — no direct USB device references |

Restarting only WirePlumber is crucial for apps that use `pa_simple` (PulseAudio Simple API), like **Minecraft Bedrock** via mcpelauncher. These apps establish a one-shot audio connection and cannot automatically reconnect if PipeWire itself restarts. A WirePlumber-only restart re-routes USB devices without dropping any existing audio streams.

#### Why `runuser` Instead of `sudo -u`?

The script runs as **root** (systemd system service) but needs to restart **user** services. `runuser` is the correct tool because:

- It doesn't require PAM authentication (unlike `su`)
- It properly sets `XDG_RUNTIME_DIR` which PipeWire needs
- It works in early boot/resume context where PAM may not be ready

### Verification

After installing, test by suspending and resuming:

```bash
# 1. Suspend the system
systemctl suspend

# 2. After resume, check the logs
journalctl -u fix-audio-resume.service --no-pager -n 20

# Expected output:
# fix-audio-resume: Restarting WirePlumber for <username> (UID 1000)
# fix-audio-resume: WirePlumber restart complete for <username>
# fix-audio-resume: Reloading OpenRGB profile for <username> (UID 1000)
# fix-audio-resume: OpenRGB profile reload complete for <username>

# 3. Also check syslog
journalctl -t fix-audio-resume --no-pager -n 10

# 4. Verify audio works
speaker-test -t sine -f 440 -l 1
```

### Troubleshooting (Audio)

#### Audio still broken after resume

```bash
# Check if the service ran
systemctl status fix-audio-resume.service

# Check if WirePlumber is running
systemctl --user status wireplumber.service

# Manual restart (immediate fix — WirePlumber only)
systemctl --user restart wireplumber.service

# If WirePlumber-only restart doesn't fix it, try the full stack
# (note: this will break audio for Minecraft and similar pa_simple apps)
systemctl --user restart pipewire.service wireplumber.service \
    pipewire-pulse.service filter-chain.service

# If manual restart works but automatic doesn't, increase the sleep delay
sudo sed -i 's/sleep 3/sleep 5/' /usr/lib/systemd/system-sleep/fix-audio-resume.sh
```

#### OpenRGB profile not restored after resume

```bash
# Check if OpenRGB is still running
pgrep -af openrgb

# Manually reload the profile
flatpak run org.openrgb.OpenRGB --profile "meins"

# Check logs for OpenRGB reload
journalctl -t fix-audio-resume --no-pager | grep -i openrgb
```

#### Service not running after resume

```bash
# Check if it's properly enabled
systemctl is-enabled fix-audio-resume.service

# Check WantedBy links
ls -la /etc/systemd/system/systemd-suspend.service.wants/

# Re-enable if needed
sudo systemctl enable fix-audio-resume.service
sudo systemctl daemon-reload
```

#### Audio works but some devices are on the wrong output

```bash
# Check PipeWire device list
wpctl status

# Set default output device
wpctl set-default <device-id>
```

---

## Tested Environment

| Component | Details |
|-----------|---------|
| **OS** | Kubuntu 24.04.4 LTS (Noble), Kernel 6.17.x |
| **Desktop** | KDE Plasma 5.27 (Wayland) |
| **GPU** | NVIDIA GeForce RTX 4080, proprietary driver 590.x |
| **Audio Server** | PipeWire 1.0.5 (with PulseAudio/ALSA/JACK compatibility) |
| **OpenRGB** | Flatpak (org.openrgb.OpenRGB) |
| **RGB Devices** | Motherboard (I2C), RAM (SMBus), GPU (I2C), peripherals (USB HID) |

Both fixes are confirmed working with:
- NVIDIA proprietary driver (including `nvidia-suspend`/`nvidia-resume` services)
- Multiple USB audio devices
- Multiple RGB controllers across different bus types

---

## Development

These fixes were developed using **AI-assisted programming** ("vibecoding") with **Claude Opus 4.6** (Anthropic) via GitHub Copilot in VS Code. The AI analyzed the root causes, implemented the scripts, and authored this documentation. All fixes were practically tested and verified on a real system by [brainAThome](https://github.com/brainAThome).

---

## License

These scripts and documentation are released under the [MIT License](LICENSE).
