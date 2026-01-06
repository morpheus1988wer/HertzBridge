# HertzBridge 🎧

**Bit-Perfect Audio Switching for macOS Music**

HertzBridge is a lightweight menu bar utility that automatically synchronizes your DAC's sample rate with the track currently playing in the macOS Music app (including Apple Music and local files). 

## 🚀 Latest Version: v1.2 (Stable)

This version is the most stable and reliable iteration of HertzBridge, featuring a completely rewritten engine for zero-latency detection and rock-solid state management.

### [Download HertzBridge v1.2 (DMG)](HertzBridge_v1.2.dmg)

### Key Improvements in v1.2:
- **Zero-Loop Logic**: Resolved the "Detecting..." infinite loop caused by polling race conditions.
- **Enhanced Stability**: Refined the stability timer to prevent resets during active monitoring.
- **State Cleanup**: Improved rate detection to explicitly clear internal flags after a successful switch.
- **Branding Sync**: Properly reflected versioning in the menu bar and application metadata.

---

## ✨ Features

*   **Tenacious Switching Engine**: Robust retry logic that iterates through compatible bit depths (32-bit > 24-bit > 16-bit) to ensure hardware compatibility.
*   **Smart Album Continuity**: Instant switching for subsequent tracks in the same album, preserving gapless playback once the initial rate is confirmed.
*   **Persistent Device Display**: The menu bar reflects your DAC's *actual* physical sample rate, providing real-time verification of bit-perfect playback.
*   **Dual-Trigger System**: The app wakes up immediately on hardware rate changes, bypassing latent notifications for a snappier experience.
*   **Native Engine**: Built for performance with a native in-process system that uses negligible CPU.
*   **Zero-Interference**: Intelligently manages connection state so it never accidentally launches the Music app on startup.

## 🛠️ Evolution from v1.1
HertzBridge v1.2 inherits all the major performance breakthroughs of v1.1:
- Replaced shell-based polling with **native AppleScript hooks** (NSAppleScript).
- Moved expensive operations to **background threads** to keep the UI perfectly fluid.
- Implemented **Distributed Notifications** for instant track detection.

## 🔧 Installation & Usage

1.  Download the latest [HertzBridge v1.2](HertzBridge_v1.2.dmg).
2.  Drag to **Applications**.
3.  Open HertzBridge from your Applications folder.
4.  Optionally, enable **Launch at Login** from the menu.

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
