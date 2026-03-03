# HertzBridge v1.4 Release Notes

### Core Reliability Enhancements
- **Watchdog Timer & Self-Healing**: Added a dedicated watchdog process to monitor the native macOS CoreAudio log stream. If the stream listener ever dies or stops reporting, it will now automatically restart it, preventing the UI from freezing.
- **Race Condition Fix**: Fixed an issue where the `isMusicTerminating` flag could get permanently stuck if Apple Music was forcefully quit, which previously prevented further automated detection.
- **Immediate State Toggles**: Toggling manual override modes now bypasses stream validation waits to instantly sync the DAC without delay, and untoggling them immediately re-arms the native log scanner mid-stream instead of requiring song skips.

### UI Refinements
- **Actual Codec Extraction**: Local audio tracks now correctly identify deep native source codecs (e.g. ALAC, FLAC, AC3, PCM) directly from `AudioStreamBasicDescription` rather than blindly relying on file extensions to guess the source file type.
- **Improved Alignment & Aesthetics**: Overhauled dropdown layouts using raw `NSView` bounding boxes to natively construct custom unclickable labels that bypass macOS "grey text" disabled styling. 
- **Formatting Cleanup**: The redundant "Format:" prefixes have been removed, lists now utilize clean slash dividers (e.g., `192000Hz / 24bit / ALAC`), and elements correctly align flush to the left edge exactly like standard contextual menu items.
