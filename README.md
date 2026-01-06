# HertzBridge 🎧

**Bit-Perfect Audio Switching for macOS Music**

HertzBridge is a lightweight menu bar utility that automatically synchronizes your DAC's sample rate with the track currently playing in the macOS Music app (including Apple Music and local files). 

Built on the technical foundations of projects like Vincent Neo's *LosslessSwitcher*, HertzBridge is a modern evolution focused on high-reliability switching and a seamless, "set and forget" user experience.

## ✨ Key Features

*   **Tenacious Switching Engine**: Robust retry logic that iterates through all compatible bit depths (32-bit > 24-bit > 16-bit) if a hardware driver rejects the initial request.
*   **Smart Album Continuity**: Detects when you are playing an album. Once the rate is confirmed for the first track, subsequent tracks in the same album switch **instantly**, preserving gapless playback.
*   **Persistent Device Display**: The menu bar always reflects your DAC's actual physical sample rate, even when Apple Music is closed or if you manually change settings in Audio MIDI Setup.
*   **Dual-Path Stability**: 
    *   **Fast Path**: Near-instant approval if the new track matches the current hardware rate.
    *   **Safe Path**: Strict stability verification for actual rate changes to ensure zero audio glitches.
*   **Zero-Interference**: Intelligently pre-checks if the Music app is running before querying, ensuring it never accidentally launches the player on startup.
*   **Minimalist UI**: Ultra-compact menu bar item with variable-width display (e.g., "44k", "192k") to minimize clutter.

## 🚀 Release Notes: v1.1 (Stable Release)

This version is a complete engine rewrite focusing on zero latency and native performance.

### ⚡️ Engine & Performance
*   **Native Engine**: Replaced slow shell polling with a native in-memory system. Checks are now instant with negligible CPU usage.
*   **Dual-Trigger System**: The app wakes up *immediately* when the audio device reports a sample rate change, bypassing slow Music.app notifications.


### 🛠️ Fixes & Polish
*   **Persistence Fix**: Resolved a race condition ensuring correct rates are applied even during rapid track skipping.
*   **Memory Safety**: Fixed all compiler warnings for rock-solid stability.
*   **Icon Restored**: Includes the restored, premium app icon.

## 🛠️ Installation & Usage

1.  Download the latest [HertzBridge_v1.1.dmg](HertzBridge_v1.1.dmg).
2.  Drag to Applications.
3.  Open HertzBridge. It will appear in your Menu Bar.
4.  Optionally, enable **Launch at Login** from the menu.

## 🧠 Technical Overview

HertzBridge operates by:
*   **Log Parsing**: Actively monitoring `com.apple.Music` system logs to extract real-time streaming metadata not exposed by standard APIs.
*   **AppleScript Bridge**: Low-impact metadata fetching for Track/Artist/Album context.
*   **CoreAudio (C-APIs)**: Direct hardware communication with your DAC to set the physical clock without resampling.

## ✨ Vibe Coded

HertzBridge is "vibe coded"—built with passion to solve a shared problem. I'll do my best to address improvements and fix errors as they arise, but please keep in mind this is a community project maintained in spare time.

## ⚠️ Disclaimer

**Use at your own risk.** Usage of this application does not make the developer liable for any damage caused to your DAC, Mac, or any other hardware. By using this software, you agree that you are solely responsible for its impact on your system.

## 🤝 Credits

HertzBridge is a technical evolution of concepts pioneered by the community. Special thanks to [Vincent Neo](https://github.com/vincentneo) for the foundational research into log-based rate detection on macOS.

---
*Created with 💙 for the Hi-Fi community.*
