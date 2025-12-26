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
## 🛠️ Installation & Usage
1.  Download the latest [HertzBridge.dmg](HertzBridge_v1.0.dmg).
2.  Drag to Applications.
3.  Open HertzBridge. It will appear in your Menu Bar.
4.  Optionally, enable **Launch at Login** from the menu.
## 🧠 Technical Overview
HertzBridge operates by:
*   **Log Parsing**: Actively monitoring `com.apple.Music` system logs to extract real-time streaming metadata not exposed by standard APIs.
*   **AppleScript Bridge**: Low-impact metadata fetching for Track/Artist/Album context.
*   **CoreAudio (C-APIs)**: Direct hardware communication with your DAC to set the physical clock without resampling.
## 🤝 Credits
HertzBridge is a technical evolution of concepts pioneered by the community. Special thanks to [Vincent Neo](https://github.com/vincentneo) for the foundational research into log-based rate detection on macOS.
---
*Created with 💙 for the Hi-Fi community.*
