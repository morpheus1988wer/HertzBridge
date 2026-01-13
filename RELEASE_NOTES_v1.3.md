# HertzBridge v1.3 Release Notes

## 🎉 What's New in v1.3

### Major Improvements

#### 🎯 AppleScript Rate Detection
- **Direct sample rate fetching** from Music app bypasses macOS log permission restrictions
- Works reliably on unsigned/locally-built apps without Full Disk Access
- Instant detection for both local files and streaming tracks

#### ⚡ Zero UI Flicker
- Eliminated "Detecting..." flashes after track switches
- AppleScript rates take absolute priority over log-based detection
- UI updates are suppressed when switch is already pending/applied

#### 🔒 Boot Loop Fix (5-Layer Protection)
The most persistent issue is now completely resolved:

1. **Process State Check**: Filters out `.isTerminated` apps
2. **NSWorkspace Termination Observer**: Detects Music quit with 5-second cooldown
3. **Immediate Timer Shutdown**: Halts ALL polling/switch timers instantly via delegate callback
4. **AppleScript Timeout Detection**: Monitors execution time to detect unresponsive processes
5. **Process Launch Time Check**: Skips querying Music if launched within last 5 seconds
6. **Termination Flag**: Blocks all in-flight queries on background threads

Music now stays closed when quit during playback - no more relaunches!

#### 🔐 Enhanced Permissions
- Added `NSAppleEventsUsageDescription` to `Info.plist`
- macOS now properly requests Music automation permissions
- Clear permission prompts for users

#### 🎨 Version Display
- Menu bar now correctly shows "HertzBridge v1.3"

---

## 📦 Installation

Download [HertzBridge_v1.3.dmg](HertzBridge_v1.3.dmg)

**Important:** Since this app is unsigned, macOS Gatekeeper will block it on first launch.

### Bypass Instructions:
**Right-click** HertzBridge.app in Applications → Select **"Open"** → Click **"Open"** in dialog

Or run:
```bash
xattr -cr /Applications/HertzBridge.app
```

---

## 🐛 Bug Fixes
- Fixed "Detecting..." UI loop when rate was already applied
- Fixed Music relaunch during quit (comprehensive multi-layer fix)
- Fixed permission denials for AppleScript automation
- Suppressed expected "Connection invalid" errors during Music termination

## 🔧 Technical Details
- AppleScript execution now includes timeout monitoring (1s threshold)
- Background thread queries blocked immediately when Music terminates
- Termination flag resets automatically after cooldown expires
- Launch time tracking prevents querying recently-launched instances

---

## ⚠️ Known Limitations
- App requires manual Gatekeeper bypass (unsigned)
- First launch will prompt for Music automation permission
- Log-based detection (legacy fallback) still requires Full Disk Access on some systems

---

**Full Changelog**: v1.2...v1.3
