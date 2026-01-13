import Foundation
import AppKit

public protocol MusicAppBridgeDelegate: AnyObject {
    func musicAppDidTerminate()
}

public struct MusicTrack {
    public let name: String
    public let artist: String
    public let album: String? // New in v1.9
    public let location: String? // Path to local file, nil if streaming
    public let sampleRate: Double? // New in v1.3 (AppleScript Bypass)
    
    public init(name: String, artist: String, album: String? = nil, location: String?, sampleRate: Double? = nil) {
        self.name = name
        self.artist = artist
        self.album = album
        self.location = location
        self.sampleRate = sampleRate
    }
}

public class MusicAppBridge {
    public static let shared = MusicAppBridge()
    
    // v1.3 Boot Loop Fix: cooldown window after termination
    private var terminationCooldown: Date = Date.distantPast
    private var isMusicTerminating: Bool = false  // v1.3: Immediate flag for in-flight queries
    public weak var delegate: MusicAppBridgeDelegate?
    
    private init() {
         // Watch for app termination to set a "safety window"
         NSWorkspace.shared.notificationCenter.addObserver(self, 
            selector: #selector(appDidTerminate(_:)), 
            name: NSWorkspace.didTerminateApplicationNotification, 
            object: nil)
    }
    
    @objc private func appDidTerminate(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier == "com.apple.Music" {
             print("MusicAppBridge: detected Music termination. Blocking queries for 5s.")
             isMusicTerminating = true  // Set flag IMMEDIATELY to block in-flight queries
             terminationCooldown = Date().addingTimeInterval(5.0)
             delegate?.musicAppDidTerminate()
        }
    }
    
    public func getCurrentTrack() -> MusicTrack? {
        guard let output = runScript() else { 
            // print("MusicAppBridge: Failed to run script")
            return nil 
        }
        
        if output.contains("stopped") { 
            return nil 
        }
        
        if output.contains("error") {
            print("MusicAppBridge: AppleScript error")
            return nil
        }
        
        return parseRobustOutput(output)
    }
    
    private func runScript() -> String? {
        // v1.3 CRITICAL: Check termination flag FIRST (before any other work)
        // This blocks in-flight queries that are already on background threads
        if isMusicTerminating {
            return nil
        }
        
        // v1.3 Fix: Check Cooldown
        if Date() < terminationCooldown {
            return nil
        } else {
            // Cooldown expired - reset the terminating flag
            // This allows Music to work normally if the user launches it again
            if isMusicTerminating {
                print("MusicAppBridge: Cooldown expired - resetting termination flag")
                isMusicTerminating = false
            }
        }
        
        // Prevent launching Music app if it's not running
        let musicApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        // v1.3 Fix: "Boot Loop" - We must filter out apps that are .isTerminated
        let activeApp = musicApps.first { !$0.isTerminated }
        
        guard let app = activeApp else {
            return nil
        }
        
        // v1.3 CRITICAL FIX: Check process launch time
        // If Music was launched within the last 5 seconds, DON'T query it
        // It might be a relaunch we caused - querying it again will perpetuate the loop
        if let launchDate = app.launchDate {
            let timeSinceLaunch = Date().timeIntervalSince(launchDate)
            if timeSinceLaunch < 5.0 {
                print("MusicAppBridge: Music launched recently (\(String(format: "%.1f", timeSinceLaunch))s ago) - skipping query to avoid relaunch loop")
                return nil
            }
        }
    
        // v1.9: Use Native NSAppleScript for speed (avoids process launch overhead)
        let fetchTrackMetadataScript = """
        tell application "Music"
            if player state is playing then
                try
                    set tName to name of current track
                    set tArtist to artist of current track
                    set tAlbum to album of current track
                    try
                        set tLoc to POSIX path of (location of current track as text)
                    on error
                        set tLoc to "missing value"
                    end try
                    
                    try
                        set tRate to sample rate of current track
                    on error
                        set tRate to "0"
                    end try
                    
                    return tName & "|||" & tArtist & "|||" & tAlbum & "|||" & tLoc & "|||" & tRate
                on error
                    return "error"
                end try
            else
                return "stopped"
            end if
        end tell
        """
        
        var error: NSDictionary?
        if let scriptObject = NSAppleScript(source: fetchTrackMetadataScript) {
            // v1.3 Boot Loop Fix: Monitor execution time to detect dying process
            let startTime = Date()
            let outputDescriptor = scriptObject.executeAndReturnError(&error)
            let executionTime = Date().timeIntervalSince(startTime)
            
            // If execution took > 1 second, Music is likely unresponsive/dying
            if executionTime > 1.0 {
                print("MusicAppBridge: AppleScript timeout (\(String(format: "%.2f", executionTime))s) - Music likely terminating")
                terminationCooldown = Date().addingTimeInterval(10.0)
                delegate?.musicAppDidTerminate()
                return nil
            }
            
            if let err = error {
                // Only log unexpected errors - "Connection is invalid" during termination is expected
                if !isMusicTerminating {
                    print("MusicAppBridge: NSAppleScript Error: \(err)")
                }
                // Don't trigger delegate here - termination is detected by NSWorkspace observer
                // This error is just a symptom, not the cause
                return nil
            }
            let result = outputDescriptor.stringValue
            if let res = result {
                 print("DEBUG: AppleScript Result: \(res)")
            }
            return result
        }
        return nil
    }
    
    // Updated parser for the metadata script
    private func parseRobustOutput(_ raw: String) -> MusicTrack? {
        let parts = raw.components(separatedBy: "|||")
        // Now expects 5 parts: Name, Artist, Album, Location, SampleRate
        guard parts.count >= 4 else { return nil }
        
        let name = parts[0]
        let artist = parts[1]
        let album = parts[2]
        let loc = parts[3]
        
        // Handle optional 5th part (Sample Rate) safely for backward compat
        var rate: Double? = nil
        if parts.count >= 5, let parsedRate = Double(parts[4]), parsedRate > 0 {
            rate = parsedRate
        }
        print("DEBUG: Parsed Rate: \(rate ?? 0)")
        
        let location = (loc == "missing value") ? nil : loc
        
        // Handle empty album string as nil
        let finalAlbum = album.isEmpty ? nil : album
        
        return MusicTrack(name: name, artist: artist, album: finalAlbum, location: location, sampleRate: rate)
    }
}
