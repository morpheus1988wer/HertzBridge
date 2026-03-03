# HertzBridge v1.5 Release Notes

### System-Level Output Switching
- **macOS Default Output Control**: Selecting a device from "Select Output Device" now changes the macOS system default output — identical to switching in System Settings → Sound → Output. Previously, HertzBridge only managed the sample rate on the selected device without changing the system routing.
- **Sample Rate Follows Selection**: The automatic sample rate management continues to work seamlessly on whichever device is active.

### Idle State Recovery
- **Background Audio Fix**: Fixed a bug where playing audio in another app (YouTube, Spotify, etc.) while Apple Music was paused would leave HertzBridge permanently stuck in "Idle" after resuming Music playback.
- **CoreAudio Device Listener**: Added a system-level listener for default output device changes. When macOS audio routing changes (Bluetooth connect/disconnect, another app releasing audio), HertzBridge now immediately re-checks Music playback state.
- **Unrestricted Notification Handling**: Removed an overly strict filter on Music player notifications that silently dropped resume events lacking metadata, preventing detection of playback resumption.
