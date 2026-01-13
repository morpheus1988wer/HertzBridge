# HertzBridge 🎧

**Bit-Perfect Audio Switching for macOS Music**

HertzBridge is a lightweight menu bar utility that automatically synchronizes your DAC's sample rate with the track currently playing in the macOS Music app (including Apple Music and local files). 

## 🚀 Latest Version: v1.3 (Stable)

This version features comprehensive improvements to rate detection, UI responsiveness, and Music app termination handling.

### [Download HertzBridge v1.3 (DMG)](HertzBridge_v1.3.dmg)

### Key Improvements in v1.3:
- **AppleScript Rate Detection**: Direct sample rate fetching bypasses log permission restrictions for instant, reliable detection.
- **Zero UI Flicker**: Eliminated "Detecting..." flashes by prioritizing AppleScript rates over log-based detection.
- **Boot Loop Fix**: Comprehensive 5-layer protection prevents Music from relaunching when quit during playback.
- **Enhanced Permissions**: Added `NSAppleEventsUsageDescription` for proper macOS automation access.

---

## 📦 Installation

1. Download the latest [HertzBridge v1.3 DMG](HertzBridge_v1.3.dmg).
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

---

## ✨ Credits & Acknowledgements

HertzBridge is a technical evolution of concepts pioneered by the community. Special thanks to [Vincent Neo](https://github.com/vincentneo) for foundational research into log-based rate detection on macOS.

---
*Created with 💙 for the Hi-Fi community.*
