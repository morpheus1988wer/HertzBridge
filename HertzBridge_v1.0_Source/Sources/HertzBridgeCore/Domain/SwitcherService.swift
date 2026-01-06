import Foundation
import CoreAudio

public protocol SwitcherServiceDelegate: AnyObject {
    func didUpdateStatus(track: String, trackFormat: String, device: String, deviceFormat: String)
}

public class SwitcherService: LogParserDelegate {
    public static let shared = SwitcherService()
    
    private var isRunning = false
    private var firstTrack = true // First track after app starts
    private var activePollInterval: TimeInterval = 0.1 // Very fast track change detection
    private var idlePollInterval: TimeInterval = 20.0 // Slow during playback
    private var pollTimer: Timer?
    private var currentTrackHash: String = ""
    private var pendingSwitchTimer: Timer?
    private var hasAlreadySwitched: Bool = false
    
    // v1.9 State: Album Continuity
    private var previousAlbum: String?
    private var confirmedAlbumRate: Double?
    
    // V2 State
    public weak var delegate: SwitcherServiceDelegate?
    public var selectedDeviceID: AudioDeviceID? = nil
    
    // v2.0 UI State tracking (to prevent redundant flashes)
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
        
        // Register for Music app notifications
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(musicPlayerStateChanged),
                                               name: NSNotification.Name("com.apple.iTunes.playerInfo"), // For Music.app
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(musicPlayerStateChanged),
                                               name: NSNotification.Name("com.apple.Music.playerInfo"), // For Music.app (newer macOS)
                                               object: nil)
    }
    
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        firstTrack = true // Reset on app start
        
        // Re-enable log parsing with improved filtering
        logParser.startMonitoring()
        
        // Reset to standard 44.1kHz on startup
        if let device = deviceManager.getDefaultOutputDevice() {
            print("🚀 Startup: Resetting \(device.name) to 44.1kHz")
            _ = deviceManager.setFormat(deviceID: device.id, sampleRate: 44100.0)
        }
        
        checkForTrackChange()
        setPollInterval(activePollInterval) // Start with fast polling
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
    
    // Delegate from LogParser - store the latest detected rate
    private var latestLogRate: Double?
    private var stableRateStartTime: Date?
    private var stableRate: Double?
    
    public func didDetectSampleRate(_ rate: Double) {
        // Store latest log rate for streaming tracks
        latestLogRate = rate
        // print("SwitcherService: Stored latestLogRate = \(rate)Hz")
        
        // Track rate stability
        if let stable = stableRate, abs(stable - rate) < 0.1 {
            // Same rate as before - stability continues
        } else {
            // Different rate - restart stability tracking
            stableRate = rate
            stableRateStartTime = Date()
            // print("📊 Rate stability: Started tracking \(rate)Hz")
        }
        
        // Check if rate has been stable for 3+ seconds
        if let startTime = stableRateStartTime,
           Date().timeIntervalSince(startTime) >= 3.0 {
            // print("✅ Rate stability: \(rate)Hz stable for 3+ seconds")
        }
    }
    
    // MARK: - Notification Handling
    @objc private func musicPlayerStateChanged(notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        
        // Strict Filter: Only process if Name and Artist are present
        // This filters out playback time updates and other noise
        guard let _ = userInfo["Name"] as? String,
              let _ = userInfo["Artist"] as? String else {
            // print("🔇 Ignored notification (missing metadata)")
            return
        }
        
        // Use throttle check to limit processing
        checkForTrackChange()
    }
    
    private func checkForTrackChange() {
        guard isRunning else { return }
        
        let track = musicBridge.getCurrentTrack()
        
        // v2.0: Decouple Device Format display from Track lifecycle
        // This ensures the menu bar shows the DAC's rate even if Music is off.
        var targetDevice: AudioDeviceCompat?
        if let userID = selectedDeviceID {
            targetDevice = deviceManager.getDeviceInfo(userID)
        } else {
            targetDevice = deviceManager.getDefaultOutputDevice()
        }
        
        let deviceFormatStr = if let device = targetDevice {
            getDeviceFormatString(for: device.id)
        } else {
            "Unknown"
        }
        
        if track == nil {
            if !currentTrackHash.isEmpty {
                currentTrackHash = ""
                hasAlreadySwitched = false
            }
            updateUI(
                status: "Idle",
                trackFormat: "-",
                deviceFormat: deviceFormatStr,
                deviceName: targetDevice?.name
            )
            return
        }
        
        // If track exists, proceed with standard change detection
        guard let track = track else { return }
        
        // Create unique hash for this track
        let trackHash = "\(track.name)|\(track.artist)"
        
        // Check if track changed
        if trackHash != currentTrackHash {
            // v1.9 Optimization: Same-Album Continuity
            // If we are on the same album and have a confirmed rate, we trust it persists.
            let isSameAlbum = (firstTrack == false) && (previousAlbum != nil) && (track.album == previousAlbum)
            
            currentTrackHash = trackHash
            previousAlbum = track.album // Update for next time
            hasAlreadySwitched = false
            
            // Default behavior: Reset stability
            stableRate = nil
            stableRateStartTime = nil
            setPollInterval(activePollInterval)
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
                
                // Check for Same-Album "Instant Path"
                if isSameAlbum, let expectedRate = confirmedAlbumRate {
                    print("💿 Same Album ('\(track.album ?? "-")') detected. Preserving \(expectedRate)Hz.")
                    // Manually set the 'latestLogRate' to what we expect, so determineFormat picks it up
                    latestLogRate = expectedRate
                    
                    // Instant Switch (0.1s to allow UI breath)
                    pendingSwitchTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
                         self?.performDelayedSwitch(for: track)
                    }
                } else {
                    // Normal Path (Fast or Slow Stability Check)
                    print("🌐 Streaming track detected: Waiting for stability...")
                    // Reset album rate confirmation until this new track is stable
                    confirmedAlbumRate = nil 
                    waitForStableRate(track: track)
                }
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
            
            // Determine Current Device Rate for Fast Path
            var currentDeviceRate: Double?
            if let userID = self.selectedDeviceID {
                currentDeviceRate = self.deviceManager.getDeviceInfo(userID)?.sampleRate
            } else {
                currentDeviceRate = self.deviceManager.getDefaultOutputDevice()?.sampleRate
            }
            
            // Dynamic Stability Duration
            // If the logs match the CURRENT device rate (same rate), we can trust it faster (0.5s).
            // If the logs show a NEW rate, we must be strict (2.0s) to avoid glitches/lag.
            let requiredDuration: TimeInterval
            if let devRate = currentDeviceRate, let logRate = self.stableRate,
               abs(devRate - logRate) < 0.1 {
                requiredDuration = 0.5 // Fast Path: Same rate, just confirm briefly
            } else {
                requiredDuration = 2.0 // Slow Path: Changing rate, be strict
            }
            
            // Check stability
            if let startTime = self.stableRateStartTime,
               let rate = self.stableRate,
               Date().timeIntervalSince(startTime) >= requiredDuration {
                
                let pathName = requiredDuration < 1.0 ? "FAST" : "STRICT"
                print("✅ Verified stable rate (\(pathName)): \(rate)Hz (held for >\(requiredDuration)s) - switching now")
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
        guard !hasAlreadySwitched else { return }
        hasAlreadySwitched = true
        
        // print("🔍 performDelayedSwitch called for '\(track.name)'")
        // print("🔍 track.location = \(track.location?.description ?? "nil (streaming)")")
        // print("🔍 latestLogRate before determineFormat = \(latestLogRate?.description ?? "nil")")
        
        let (requiredRate, requiredDepth) = determineFormat(for: track)
        
        // print("🔍 determineFormat returned: \(requiredRate)Hz / \(requiredDepth?.description ?? "nil")bit")
        
        // Determine Target Device
        var targetDevice: AudioDeviceCompat?
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
                // v1.9: Confirm this rate for the album
                self.confirmedAlbumRate = requiredRate
                // print("💿 Album Rate Confirmed: \(requiredRate)Hz")
                
                self.setPollInterval(self.idlePollInterval)
            }
        } else {
            // Already correct format
            updateUIForTrack(track, beforeSwitch: false)
            // v1.9: Confirm this rate for the album
            self.confirmedAlbumRate = requiredRate
             
            setPollInterval(idlePollInterval)
        }
    }
    
    private func updateUIForTrack(_ track: MusicTrack, beforeSwitch: Bool) {
        let (requiredRate, requiredDepth) = determineFormat(for: track)
        let trackFormatStr = if let depth = requiredDepth {
            "\(Int(requiredRate))Hz / \(depth)bit"
        } else {
            "\(Int(requiredRate))Hz (stream)"
        }
        
        var targetDevice: AudioDeviceCompat?
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
        
        // Priority 2: Streaming - use log-detected rate if available
        // print("Stream detection: latestLogRate = \(latestLogRate?.description ?? "nil")")
        if let logRate = latestLogRate {
            // print("Using log-detected rate: \(logRate)Hz for stream")
            return (logRate, nil) // nil = ignore bit depth for streams
        }
        
        // Priority 3: Fallback for streams (CD quality)
        // print("No log rate detected, falling back to 44.1kHz")
        return (44100.0, nil)
    }
    
    // Legacy method kept for compatibility
    private func determineSampleRate(for track: MusicTrack) -> Double {
        return determineFormat(for: track).sampleRate
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
}
