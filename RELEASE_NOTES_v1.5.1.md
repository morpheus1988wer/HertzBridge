# HertzBridge v1.5.1 Release Notes

## Bugfixes
- **Fixed Idle State Loop**: Resolved an issue where closing and later reopening the Music app would cause HertzBridge to be permanently stuck in an "Idle" or "Detecting..." state.
- **Fixed Apple Music Relaunch**: Resolves a race condition where manually quitting Apple Music would cause macOS to instantly relaunch it. To prevent this, HertzBridge now increases the AppleScript cooldown to 8.0 seconds and bypasses aggressive status polling when Music broadcasts a "Stopped" state, allowing it to fully quit without interruption.
