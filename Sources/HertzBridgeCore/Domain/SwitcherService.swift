import Foundation
import CoreAudio

public protocol SwitcherServiceDelegate: AnyObject {
    func didUpdateStatus(track: String, trackFormat: String, device: String, deviceFormat: String)
}

public class SwitcherService: LogParserDelegate, MusicAppBridgeDelegate {
    public static let shared = SwitcherService()
    
    private var isRunning = false
    private var isSystemInitializing = true    // v2.0: Faster Heartbeat
    // Since Native API (v1.9) is cheap, we can poll frequently to catch updates 
    // even if notifications fail completely.
    private let playbackPollInterval: TimeInterval = 3.0
    private let transitionPollInterval: TimeInterval = 0.51 // Fast polling during changes
    private var pollTimer: Timer?
    private var trackIdentityHash: String = ""
    private var pendingSwitchTimer: Timer?
    private var isSwitchOperationApplied: Bool = false
    
    // Track Monitoring state
    private var previousAlbum: String?
    private var confirmedAlbumRate: Double?
    
    // Public Configuration & State
    public weak var delegate: SwitcherServiceDelegate?
    public var selectedDeviceID: AudioDeviceID? = nil
    
    // UI State tracking (to prevent redundant flashes)
    private var lastReportedTrackName: String?
    private var lastReportedDeviceFormat: String?
    private var lastReportedDeviceName: String?
    
    // Manual Override
    public var manualOverrideRate: Double? = nil // nil = auto-detect
    public var streamingDefaultRate: Double = 96000.0 // Default for Apple Music Hi-Res
    
    public func setManualOverride(rate: Double?) {
        manualOverrideRate = rate
        print("Manual override: \(rate.map { "\($0)Hz" } ?? "disabled")")
        // Force immediate re-check to apply override
        checkForTrackChange()
    }
    
    public func setStreamingDefault(rate: Double) {
        streamingDefaultRate = rate
        print("Streaming default: \(rate)Hz")
    }
    
    // Dependencies
    private let deviceManager = DeviceManager.shared
    private let musicBridge = MusicAppBridge.shared
    private let fileParser = FileParser.shared
    private let logParser = LogParser.shared
    
    private init() {
        logParser.delegate = self
        musicBridge.delegate = self // v1.3: Boot Loop Fix
        
        // Register for Music app notifications
        // Note: Music.app still broadcasts as 'com.apple.iTunes' for backward compatibility
        // Register for Distributed Notifications (Critical for instant detection)
        // Music.app broadcasts 'com.apple.iTunes.playerInfo' globally
        DistributedNotificationCenter.default().addObserver(self,
                                                           selector: #selector(musicPlayerStateChanged),
                                                           name: NSNotification.Name("com.apple.iTunes.playerInfo"),
                                                           object: nil)
        
        DistributedNotificationCenter.default().addObserver(self,
                                                           selector: #selector(musicPlayerStateChanged),
                                                           name: NSNotification.Name("com.apple.Music.playerInfo"),
                                                           object: nil)
    }
    
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        isSystemInitializing = true // Reset on app start
        
        logParser.startMonitoring()
        
        // Reset to standard 44.1kHz on startup
        if let device = deviceManager.getDefaultOutputDevice() {
            _ = deviceManager.setFormat(deviceID: device.id, sampleRate: 44100.0)
        }
        
        checkForTrackChange()
        setPollInterval(transitionPollInterval) // Start with fast polling
    }
    
    public func stop() {
        isRunning = false
        pollTimer?.invalidate()
        pollTimer = nil
        pendingSwitchTimer?.invalidate()
        logParser.stopMonitoring()
    }
    
    private func setPollInterval(_ interval: TimeInterval) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkForTrackChange()
        }
    }
    
    // v1.7: Aggressive Polling Mode
    // Forces fast polling for a short window (5s) to catch laggy state updates
    private func startAggressivePolling() {
        setPollInterval(0.5)
        
        // Revert to slow polling after 5 seconds if no change detected
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self else { return }
            // Only revert if we haven't locked onto a new track transition
            if self.pendingSwitchTimer == nil && !self.isSwitchOperationApplied {
                self.setPollInterval(self.playbackPollInterval)
            }
        }
    }
    
    // Delegate from LogParser - store the latest detected rate
    private var detectedStreamRate: Double?
    private var candidateRateStartTime: Date?
    private var candidateRate: Double?
    private var lastTrackChangeTime: Date = Date.distantPast // v1.4: Sync point
    
    public func didDetectSampleRate(_ rate: Double, at timestamp: Date) {
        // v1.5: Sync Check with Tolerance
        // System logs might be slightly "older" than our Date() capture due to IPC latency.
        // We use a 2.0s "Safety Window".
        // If the log is MORE than 2.0s older than our change time, it's definitely stale.
        // If it's within that window (e.g. -0.2s), it's likely the new track starting.
        let tolerance: TimeInterval = 2.0
        if timestamp < lastTrackChangeTime.addingTimeInterval(-tolerance) {
             // print("🚫 Ignoring stale log: \(rate)Hz (Time: \(timestamp) < Window)")
             return
        }
        
        // v2.0: Dual-Trigger System
        // If we see a log, it means the audio engine is active/changing.
        // We use this as a signal to check the metadata, in case the Notification failed.
        // Since logs can spam, startAggressivePolling() handles the throttling (idempotent).
        startAggressivePolling()
        
        // Store latest log rate for streaming tracks
        detectedStreamRate = rate
        
        // Track rate stability (now using fast 0.2s path because we TRUST the timestamp)
        if let candidate = candidateRate, abs(candidate - rate) < 0.1 {
            // Same rate as before - stability continues
        } else {
            // Different rate - restart stability tracking
            candidateRate = rate
            candidateRateStartTime = Date()
            
            // v1.3 Fix: Only show "Detecting..." if we're actually waiting for logs
            // If the switch is already applied or pending, don't flash "Detecting..."
            if !isSwitchOperationApplied && pendingSwitchTimer == nil {
                // v2.1: Immediate Feedback
                // Update UI instantly to show we found a candidate rate ("Detecting...")
                // This prevents the "dead" feeling while waiting for stability.
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                let rateStr = formatter.string(from: NSNumber(value: rate)) ?? "\(rate)"
                
                if let currentDevice = deviceManager.getDeviceInfo(selectedDeviceID ?? deviceManager.getDefaultOutputDevice()?.id ?? 0) {
                    updateUI(
                        status: "Detecting...", 
                        trackFormat: "\(rateStr)Hz?", 
                        deviceFormat: getDeviceFormatString(for: currentDevice.id),
                        deviceName: currentDevice.name
                    )
                }
            }
        }
    }

    
    // MARK: - Notification Handling
    @objc private func musicPlayerStateChanged(notification: Notification) {
        // v2.4: Cleaned up unused variable warning
        // We just need to know if userInfo exists, we don't need to read it yet.
        guard notification.userInfo != nil else { return }
        
        // v1.8: Removed Strict Filter
        // We now react to ALL playerInfo notifications.
        // It's better to poll unnecessarily (Aggressive Mode) than to miss a track change 
        // because the notification didn't have "Name" or "Artist" keys yet.
        // guard let _ = userInfo["Name"] as? String,
        //       let _ = userInfo["Artist"] as? String else {
        //     return
        // }
        
        // Use throttle check to limit processing
        checkForTrackChange()
        
        // v1.7: Aggressive Polling Mode
        // We trigger a 5-second window of fast polling (0.5s) on EVERY notification.
        // This covers any variable latency from Music.app (100ms... 3s).
        startAggressivePolling()
    }
    
    private func checkForTrackChange() {
        guard isRunning else { return }
        
        // v1.9: Run AppleScript on background thread to prevent UI blocking
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let track = self.musicBridge.getCurrentTrack()
            
            // Hop back to main for device checks and UI updates
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard self.isRunning else { return } // Re-check validity
                
                var targetDevice: AudioDeviceInfo?
                if let userID = self.selectedDeviceID {
                    targetDevice = self.deviceManager.getDeviceInfo(userID)
                } else {
                    targetDevice = self.deviceManager.getDefaultOutputDevice()
                }
                
                let deviceFormatStr = if let device = targetDevice {
                    self.getDeviceFormatString(for: device.id)
                } else {
                    "Unknown"
                }
                
                if track == nil {
                    if !self.trackIdentityHash.isEmpty {
                        self.trackIdentityHash = ""
                        self.isSwitchOperationApplied = false
                    }
                    self.updateUI(
                        status: "Idle",
                        trackFormat: "-",
                        deviceFormat: deviceFormatStr,
                        deviceName: targetDevice?.name
                    )
                    return
                }
                
                // If track exists, proceed with standard change detection
                self.processTrackChange(track: track!, targetDevice: targetDevice)
            }
        }
    }
    
    // Split out logic for clearer flow
    private func processTrackChange(track: MusicTrack, targetDevice: AudioDeviceInfo?) {
        // Create unique hash for this track
        let trackHash = "\(track.name)|\(track.artist)"
        
        // Check if track changed OR if we have a pending rate change to process
        // v1.2 Fix: "Detecting..." Loop
        // We must process even if trackHash is same, if 'candidateRate' is set (meaning logs saw a change).
        if trackHash != trackIdentityHash {
             // Track changed: Reset everything
             self.handleNewTrackDetected(track: track, trackHash: trackHash)
        } else if candidateRate != nil && pendingSwitchTimer == nil {
             // Same track, but we have a candidate rate AND we aren't already monitoring it.
             // If pendingSwitchTimer is NOT nil, it means waitForStableRate is already running (or a switch is pending),
             // so we let that timer do its job instead of rebooting it.
             self.handleNewTrackDetected(track: track, trackHash: trackHash)
        } else {
             // Track stable, or already detecting.
             // Ensure UI is ostensibly correct (clears any stale "Detecting" if it persisted erroneously)
             if pendingSwitchTimer == nil {
                 updateUIForTrack(track, beforeSwitch: false)
             }
        }
    }
    
    // v1.9 Refactor helper
    private func handleNewTrackDetected(track: MusicTrack, trackHash: String) {
            // Smart Album Continuity
            // If we are on the same album and have a confirmed rate, we trust it persists.
            let isSameAlbum = (isSystemInitializing == false) && (previousAlbum != nil) && (track.album == previousAlbum)
            
            trackIdentityHash = trackHash
            previousAlbum = track.album // Update for next time
            isSwitchOperationApplied = false
            
            // v1.4: Record Sync Timestamp
            // We use Date() - 0.5s to be safe against slight clock diffs, but mostly to mark "Now"
            lastTrackChangeTime = Date()
            
            // Default behavior: Reset stability
            candidateRate = nil
            candidateRateStartTime = nil
            // v2.3 Fix: Preserving Stream Rate
            // We do NOT clear detectedStreamRate here.
            // Since v2.0 "Dual-Trigger", the log (Rate Change) often arrives BEFORE this method (Track Change).
            // If we clear it, we wipe the fresh valid rate we just saw, causing a fallback error.
            // detectedStreamRate = nil
            
            // v2.3: Force Last Change Time update to ensure we accept the log
            // We subtract 0.5s to ensure the log timestamp (which might be milliseconds ago) is accepted.
            lastTrackChangeTime = Date().addingTimeInterval(-0.5)
            
            setPollInterval(transitionPollInterval)
            pendingSwitchTimer?.invalidate()
            pendingSwitchTimer = nil
            
            updateUIForTrack(track, beforeSwitch: true)
            
            let isLocalFile = track.location != nil
            
            if isLocalFile {
                // ... (Local file logic unchanged) ...
                let switchDelay = 0.2
                pendingSwitchTimer = Timer.scheduledTimer(withTimeInterval: switchDelay, repeats: false) { [weak self] _ in
                    self?.performDelayedSwitch(for: track)
                }
            } else {
                // STREAMING LOGIC
                
                // v1.3: Priority Check - AppleScript Rate Available?
                if let scriptRate = track.sampleRate, scriptRate > 0 {
                    print("🎵 AppleScript provided rate: \(scriptRate)Hz - switching immediately")
                    // Use AppleScript rate directly, no need to wait for logs
                    detectedStreamRate = scriptRate
                    
                    // Instant Switch (0.1s to allow UI breath)
                    pendingSwitchTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                         self?.performDelayedSwitch(for: track)
                    }
                } else if isSameAlbum, let expectedRate = confirmedAlbumRate {
                    print("💿 Same Album ('\(track.album ?? "-")') detected. Preserving \(expectedRate)Hz.")
                    // Manually set the 'detectedStreamRate' to what we expect, so determineFormat picks it up
                    detectedStreamRate = expectedRate
                    
                    // Instant Switch (0.1s to allow UI breath)
                    pendingSwitchTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                         self?.performDelayedSwitch(for: track)
                    }
                } else {
                    // Fallback: Log-based detection (for old behavior compatibility)
                    print("🌐 Streaming track detected: Waiting for log-based stability...")
                    // Reset album rate confirmation until this new track is stable
                    confirmedAlbumRate = nil 
                    waitForStableRate(track: track)
                }
            }
        }
    
    private func waitForStableRate(track: MusicTrack) {
        // Reset stability state effectively for new track
        // (Note: We keep 'stableRate' but measuring strict duration from 'now' relative to new track logic if needed)
        // Ideally we just wait for the loop to confirm it.
        
        var attempts = 0
        let maxAttempts = 30 // 15 seconds max (0.5s intervals)
        
        // Poll every 0.5 seconds (more responsive)
        pendingSwitchTimer?.invalidate()
        pendingSwitchTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            attempts += 1
            
            // Debug current state
            // let currentLogRate = self.latestLogRate
            // print("checking stability... current log: \(currentLogRate ?? 0)")
            
            // Dynamic Stability Duration
            // v1.4: Timestamp Sync allows us to be FAST again (0.5s)
            // We know the log is "fresh" because of didDetectSampleRate filtering.
            let requiredDuration: TimeInterval = 0.5
            
            // Check stability
            if let startTime = self.candidateRateStartTime,
               let rate = self.candidateRate,
               Date().timeIntervalSince(startTime) >= requiredDuration {
                
                print("✅ Verified stable rate: \(rate)Hz (held for >\(requiredDuration)s) - switching now")
                timer.invalidate()
                self.performDelayedSwitch(for: track)
                return
            }
            
            // Give up after max attempts
            if attempts >= maxAttempts {
                print("⚠️ Timeout waiting for stable rate - proceeding with best guess")
                timer.invalidate()
                self.performDelayedSwitch(for: track)
                return
            }
            
            if attempts % 4 == 0 { // Log every 2 seconds
                print("⏳ Verifying stream stability... Attempt \(attempts)/\(maxAttempts)")
            }
        }
    }
    
    private func performDelayedSwitch(for track: MusicTrack) {
        guard !isSwitchOperationApplied else { return }
        isSwitchOperationApplied = true
        
        let (requiredRate, requiredDepth) = determineFormat(for: track)
        
        // Determine Target Device
        var targetDevice: AudioDeviceInfo?
        if let userID = selectedDeviceID {
            targetDevice = deviceManager.getDeviceInfo(userID)
        } else {
            targetDevice = deviceManager.getDefaultOutputDevice()
        }
        
        guard let device = targetDevice else { return }
        
        // Check if switch needed
        let currentFormat = deviceManager.getCurrentFormat(deviceID: device.id)
        let rateChanged = abs(device.sampleRate - requiredRate) > 0.1
        
        // Only check depth if we have a target depth (local files)
        let depthChanged: Bool
        if let depth = requiredDepth {
            depthChanged = currentFormat?.bitDepth != depth
        } else {
            depthChanged = false // Streaming: ignore depth
        }
        
        let needsSwitch = rateChanged || depthChanged
        
        if needsSwitch {
            let depthStr = requiredDepth.map { "\($0)bit" } ?? "any"
            print("Switching \(device.name) to \(requiredRate)Hz / \(depthStr) for '\(track.name)'")
            _ = deviceManager.setFormat(deviceID: device.id, sampleRate: requiredRate, bitDepth: requiredDepth)
            
            // Update UI after switch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.updateUIForTrack(track, beforeSwitch: false)
                // Confirm this rate for the album
                self.confirmedAlbumRate = requiredRate
                
                self.setPollInterval(self.playbackPollInterval)
            }
        } else {
            // Already correct format
            updateUIForTrack(track, beforeSwitch: false)
            // Confirm this rate for the album
            self.confirmedAlbumRate = requiredRate
             
            setPollInterval(playbackPollInterval)
        }
        
        // v1.2 Fix: Cleanup Candidate Rate
        // Once the switch is performed (or deemed unnecessary), we must clear the candidate rate
        // so that the polling loop doesn't think there's a "pending" change and restart detection.
        candidateRate = nil
        candidateRateStartTime = nil
    }
    
    private func updateUIForTrack(_ track: MusicTrack, beforeSwitch: Bool) {
        let (requiredRate, requiredDepth) = determineFormat(for: track)
        let trackFormatStr = if let depth = requiredDepth {
            "\(Int(requiredRate))Hz / \(depth)bit"
        } else {
            "\(Int(requiredRate))Hz (stream)"
        }
        
        var targetDevice: AudioDeviceInfo?
        if let userID = selectedDeviceID {
            targetDevice = deviceManager.getDeviceInfo(userID)
        } else {
            targetDevice = deviceManager.getDefaultOutputDevice()
        }
        
        guard let device = targetDevice else { return }
        
        updateUI(
            status: track.name,
            trackFormat: trackFormatStr,
            deviceFormat: getDeviceFormatString(for: device.id),
            deviceName: device.name
        )
    }
    
    private func determineFormat(for track: MusicTrack) -> (sampleRate: Double, bitDepth: Int?) {
        // Priority 0: Manual Override (if set)
        if let override = manualOverrideRate {
            return (override, nil) // Manual = rate only, let DAC choose depth
        }
        
        // Priority 1: Local file metadata (both rate + depth)
        if let location = track.location {
            if let format = fileParser.getAudioFormat(path: location) {
                // Local files: use actual bit depth if available
                let depth = format.bitDepth ?? 16
                return (format.sampleRate, depth)
            }
        }
        
        // Priority 1.5: Direct AppleScript Rate (v1.3 Fix for Local Builds)
        // If AppleScript gave us a valid rate, use it! It's much more reliable than logs for ad-hoc builds.
        if let scriptRate = track.sampleRate, scriptRate > 0 {
             return (scriptRate, nil)
        }
        
        // Priority 2: Streaming - use log-detected rate if available
        if let logRate = detectedStreamRate {
            return (logRate, nil) // nil = ignore bit depth for streams
        }
        
        // Priority 3: Fallback for streams (CD quality)
        // If we just cleared it, this returns 44.1 temporarily until logs catch up.
        // This is safer than sticking to the old rate (e.g. 192k) which might be wrong.
        return (44100.0, nil)
    }
    

    
    private func getDeviceFormatString(for id: AudioDeviceID? = nil) -> String {
        let targetID = id ?? (selectedDeviceID ?? deviceManager.getDefaultOutputDevice()?.id)
        guard let validID = targetID, let format = deviceManager.getCurrentFormat(deviceID: validID) else {
            return "Unknown"
        }
        return format.description
    }
    
    private func updateUI(status: String, trackFormat: String, deviceFormat: String, deviceName: String? = nil) {
        let devName = deviceName ?? "Default"
        
        // v2.0 Optimization: Avoid redundant delegate calls (polling is frequent)
        if status == lastReportedTrackName && 
           deviceFormat == lastReportedDeviceFormat && 
           devName == lastReportedDeviceName {
            return
        }
        
        lastReportedTrackName = status
        lastReportedDeviceFormat = deviceFormat
        lastReportedDeviceName = devName
        
        delegate?.didUpdateStatus(track: status, trackFormat: trackFormat, device: devName, deviceFormat: deviceFormat)
    }
    
    // MARK: - MusicAppBridgeDelegate
    public func musicAppDidTerminate() {
        print("SwitcherService: Music terminated - halting all timers immediately")
        // Immediately stop all timers to prevent any queries during shutdown
        pollTimer?.invalidate()
        pollTimer = nil
        pendingSwitchTimer?.invalidate()
        pendingSwitchTimer = nil
        
        // Reset state
        trackIdentityHash = ""
        isSwitchOperationApplied = false
    }
}
