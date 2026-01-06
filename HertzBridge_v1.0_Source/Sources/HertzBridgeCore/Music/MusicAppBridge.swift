import Foundation
import AppKit

public struct MusicTrack {
    public let name: String
    public let artist: String
    public let album: String? // New in v1.9
    public let location: String? // Path to local file, nil if streaming
    
    public init(name: String, artist: String, album: String? = nil, location: String?) {
        self.name = name
        self.artist = artist
        self.album = album
        self.location = location
    }
}

public class MusicAppBridge {
    public static let shared = MusicAppBridge()
    
    private init() {}
    
    public func getCurrentTrack() -> MusicTrack? {
        guard let output = runScript() else { 
            print("MusicAppBridge: Failed to run script")
            return nil 
        }
        
        if output.contains("stopped") { 
            return nil 
        }
        
        if output.contains("error") {
            print("MusicAppBridge: AppleScript error")
            return nil
        }
        
        let track = parseRobustOutput(output)
        if let track = track {
            // print("MusicAppBridge: Detected track '\(track.name)' by \(track.artist)")
        }
        return track
    }
    
    private func runScript() -> String? {
        // Prevent launching Music app if it's not running
        let musicApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
        if musicApps.isEmpty {
            // print("MusicAppBridge: Music app not running, skipping script")
            return nil
        }
    
        let robustScript = """
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
                    return tName & "|||" & tArtist & "|||" & tAlbum & "|||" & tLoc
                on error
                    return "error"
                end try
            else
                return "stopped"
            end if
        end tell
        """
        
        let process = Process()
        process.launchPath = "/usr/bin/osascript"
        process.arguments = ["-e", robustScript]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
        } catch {
            return nil
        }
        
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // Updated parser for the robust script
    private func parseRobustOutput(_ raw: String) -> MusicTrack? {
        let parts = raw.components(separatedBy: "|||")
        // Now expects 4 parts: Name, Artist, Album, Location
        guard parts.count >= 4 else { return nil }
        
        let name = parts[0]
        let artist = parts[1]
        let album = parts[2]
        let loc = parts[3]
        
        let location = (loc == "missing value") ? nil : loc
        
        // Handle empty album string as nil
        let finalAlbum = album.isEmpty ? nil : album
        
        return MusicTrack(name: name, artist: artist, album: finalAlbum, location: location)
    }
}
