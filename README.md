# HertzBridge 🎧

**Bit-Perfect Audio Switching for macOS Music**

HertzBridge is a lightweight menu bar utility that automatically synchronizes your DAC's sample rate with the track currently playing in the macOS Music app (including Apple Music and local files). 

## 🚀 Latest Version: v1.5 (Stable)

This version adds system-level output device switching and fixes idle state recovery after background audio playback.

### [Download HertzBridge v1.5 (DMG)](HertzBridge_v1.5.dmg)

### Key Improvements in v1.5:
- **System-Level Output Switching**: Selecting a device from "Select Output Device" now changes the macOS system default output — identical to switching in System Settings → Sound → Output.
- **Background Audio Fix**: Fixed a bug where playing audio in another app while Apple Music was paused would leave HertzBridge stuck in "Idle" after resuming Music.
- **CoreAudio Device Listener**: Added a system-level listener for default output device changes (Bluetooth connect/disconnect, another app releasing audio) that immediately re-checks Music playback.

---

## 📦 Installation

1. Download the latest [HertzBridge v1.5 DMG](HertzBridge_v1.5.dmg).
2. Open the DMG and drag **HertzBridge.app** to your **Applications** folder.
3. **Important:** Since this app is not signed with an Apple Developer certificate, macOS will block it on first launch.

### Bypassing macOS Gatekeeper (Required for first launch):

**Option 1: Right-Click Method (Easiest)**
1. Go to **Applications** folder
2. **Right-click** (or Control-click) on **HertzBridge.app**
3. Select **"Open"** from the menu
4. Click **"Open"** in the security dialog
5. The app will now run normally on future launches

**Option 2: Terminal Command (Alternative)**
```bash
xattr -cr /Applications/HertzBridge.app
```
Then launch HertzBridge normally from Applications.

**Option 3: System Settings (If already blocked)**
1. Go to **System Settings** → **Privacy & Security**
2. Scroll down to the **Security** section
3. Click **"Open Anyway"** next to the HertzBridge message
4. Confirm by clicking **"Open"**

### Optional: Launch at Login
Once HertzBridge is running, you can enable **Launch at Login** from the menu bar icon.


## 🧠 Technical Overview

HertzBridge operates by:
*   **Log Parsing**: Monitoring `com.apple.Music` system logs for real-time streaming metadata.
*   **Native Bridge**: Low-impact metadata fetching via in-process AppleScript.
*   **CoreAudio (C-APIs)**: Direct hardware communication to set the physical clock without resampling.
*   **Device Listener**: Monitors system default output changes for instant playback re-detection.

---

## 📜 Version History

### v1.4 (Reliability)
- **Watchdog & Self-Healing**: Automatically monitors the `log stream` utility in the background and restarts the engine if the connection silently dies.
- **Race Condition Fix**: Ensured the track property detection cannot get indefinitely looped or jammed by forced Music terminations.
- **Deep Codec Parsing**: Replaced blind extension-guessing with fully native `kAudioFormat` reads (ALAC, FLAC, AC3, PCM) directly from CoreAudio headers.
- **Overhauled NSView Rendering**: Completely bypassed rigid macOS label styling to render unclickable, perfectly-left-aligned dynamic width labels in solid black.
- **Instant Toggling**: Bypassed stream-stabilization waits when selecting a Manual Override rate, guaranteeing instant hardware sync.

### v1.3 (Optimization)
- **AppleScript Rate Detection**: Direct sample rate fetching bypasses log permission restrictions for instant, reliable detection.
- **Zero UI Flicker**: Eliminated "Detecting..." flashes by prioritizing AppleScript rates over log-based detection.
- **Boot Loop Fix**: Comprehensive 5-layer protection prevents Music from relaunching when quit during playback.
- **Enhanced Permissions**: Added `NSAppleEventsUsageDescription` for proper macOS automation access.

### v1.2 (Stable)
- **Zero-Loop Logic**: Resolved the "Detecting..." infinite loop.
- **Enhanced Stability**: Refined stability timers and state cleanup.
- **Features Introduced**:
    - **Tenacious Switching Engine**: Retry logic (32 > 24 > 16 bit).
    - **Smart Album Continuity**: Instant switching for same-album tracks.
    - **Dual-Trigger System**: Immediate wakeup on hardware rate changes.

### v1.1 (Evolution)
- Replaced shell-based polling with **native AppleScript hooks** (NSAppleScript).
- Moved expensive operations to **background threads**.
- Implemented **Distributed Notifications** for instant track detection.

---

## ✨ Credits & Acknowledgements

HertzBridge is a technical evolution of concepts pioneered by the community. Special thanks to [Vincent Neo](https://github.com/vincentneo) for foundational research into log-based rate detection on macOS.

---
*Created with 💙 for the Hi-Fi community.*

