# HertzBridge v1.5.1 Release Notes

## Bugfixes
- **Fixed Idle State Loop**: Resolved an issue where closing and later reopening the Music app would cause HertzBridge to be permanently stuck in an "Idle" or "Detecting..." state.
- **Fixed Apple Music Relaunch**: Resolves a race condition where manually quitting Apple Music would immediately cause macOS to relaunch it. HertzBridge now reliably detects the "Stopped" termination signal and delays queries to respectfully let Music terminate in peace.
