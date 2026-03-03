import Foundation

public protocol LogParserDelegate: AnyObject {
    func didDetectSampleRate(_ rate: Double, at timestamp: Date)
}

public class LogParser {
    public static let shared = LogParser()
    public weak var delegate: LogParserDelegate?
    
    private var process: Process?
    private var pipe: Pipe?
    
    // v1.4: Watchdog — track process health
    private var lastLogReceived: Date = Date()
    private var watchdogTimer: Timer?
    private var isMonitoring: Bool = false
    private var restartCount: Int = 0
    private let maxRestartAttempts: Int = 5   // Reset counter after success
    
    // Regex to match standard sample rates in various formats
    // e.g. "96000", "96000.0", "96 kHz" (normalized)
    // We strictly look for standard audio rates to reduce false positives
    private let ratePatterns: [String] = [
        "44100", "48000", "88200", "96000", "176400", "192000", "352800", "384000", "705600", "768000"
    ]
    
    private init() {}
    
    public func startMonitoring() {
        stopMonitoring()
        isMonitoring = true
        restartCount = 0
        launchLogProcess()
        startWatchdog()
    }
    
    public func stopMonitoring() {
        isMonitoring = false
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        killLogProcess()
    }
    
    // v1.4: Check if the log process is alive and producing output
    public var isHealthy: Bool {
        guard isMonitoring else { return false }
        guard let process = process, process.isRunning else { return false }
        // If no log lines received for 60s while we're supposed to be monitoring, something is wrong
        // (Music process may just be quiet, so we use a generous window)
        return true
    }
    
    // v1.4: Force restart the log process (called by SwitcherService self-check)
    public func forceRestart() {
        guard isMonitoring else { return }
        print("LogParser: Force restart requested")
        killLogProcess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.launchLogProcess()
        }
    }
    
    // MARK: - Private
    
    private func launchLogProcess() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        
        // Monitor just the Music process (like the old working version)
        task.arguments = [
            "stream",
            "--process", "Music"
        ]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice // Suppress stderr noise
        
        // v1.4: Detect process death and auto-restart
        task.terminationHandler = { [weak self] process in
            guard let self = self, self.isMonitoring else { return }
            let exitCode = process.terminationStatus
            print("LogParser: log stream process exited (code: \(exitCode)) — scheduling restart")
            
            DispatchQueue.main.async { [weak self] in
                self?.handleProcessDeath()
            }
        }
        
        do {
            try task.run()
            self.process = task
            self.pipe = pipe
            self.lastLogReceived = Date()
            
            // Reset restart counter on successful launch
            if restartCount > 0 {
                print("LogParser: Restart #\(restartCount) successful")
            }
            
            print("LogParser: Started monitoring 'Music' process (PID: \(task.processIdentifier))")
            
            let handle = pipe.fileHandleForReading
            handle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return } // EOF = process died
                if let output = String(data: data, encoding: .utf8) {
                    self?.lastLogReceived = Date()
                    self?.parseLogBatch(output)
                }
            }
        } catch {
            print("LogParser: Failed to launch log stream: \(error)")
            handleProcessDeath()
        }
    }
    
    private func killLogProcess() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
        pipe = nil
    }
    
    private func handleProcessDeath() {
        guard isMonitoring else { return }
        
        killLogProcess() // Clean up
        restartCount += 1
        
        if restartCount > maxRestartAttempts {
            print("LogParser: ⚠️ Max restart attempts (\(maxRestartAttempts)) reached — backing off to 30s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
                guard let self = self, self.isMonitoring else { return }
                self.restartCount = 0 // Reset for next batch
                self.launchLogProcess()
            }
            return
        }
        
        // Exponential backoff: 2s, 4s, 8s, 16s, 32s
        let delay = TimeInterval(min(1 << restartCount, 32))
        print("LogParser: Restarting in \(delay)s (attempt \(restartCount)/\(maxRestartAttempts))")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.isMonitoring else { return }
            self.launchLogProcess()
        }
    }
    
    // v1.4: Watchdog timer — periodic health check
    private func startWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isMonitoring else { return }
            
            // Check if process is still alive
            if let p = self.process, !p.isRunning {
                print("LogParser Watchdog: Process is dead — triggering restart")
                self.handleProcessDeath()
                return
            }
            
            // Check if process is nil (somehow cleaned up without restart)
            if self.process == nil {
                print("LogParser Watchdog: No process found — triggering restart")
                self.handleProcessDeath()
                return
            }
        }
    }
    
    private func parseLogBatch(_ logs: String) {
        // We look for lines containing "SampleRate" or just specific numbers causing a hit.
        // This is a "Scattershot" approach: if we see "192000" in a line that looks audio-related, we take it.
        // Refinement: Look for "AudioStack" or "HLS" or "Format"
        
        logs.enumerateLines { [weak self] (line, stop) in
            guard let self = self else { return }
            self.processLine(line)
        }
    }

    private func processLine(_ line: String) {
        // v1.4.1: Context-aware filtering
        // The old approach of line.contains("44100") matched false positives like item IDs (317335::317341).
        // We now require the line to contain audio-relevant keywords before trusting a rate number.
        let audioKeywords = [
            "SampleRate", "sample rate", "sampleRate",
            "Hz", "hz",
            "format", "Format",
            "AudioQueue", "AudioConverter",
            "nominal", "NominalSampleRate",
            "output", "Output",
            "kAudioDevice", "AQMEIO",
            "sample_rate", "srate"
        ]
        
        // Quick reject: if the line has no audio keywords, skip entirely
        let lineLC = line.lowercased()
        let hasAudioContext = audioKeywords.contains { lineLC.contains($0.lowercased()) }
        guard hasAudioContext else { return }
        
        for rateStr in ratePatterns {
            if line.contains(rateStr) {
                if let rate = Double(rateStr) {
                    let timestamp = extractTimestamp(from: line) ?? Date()
                    print("LogParser: Matched \(rateStr)Hz in audio-context line")
                    delegate?.didDetectSampleRate(rate, at: timestamp)
                    return
                }
            }
        }
    }
    
    // v1.4: Basic timestamp parser for default `log stream` format
    // Format: "2024-01-06 18:57:10.123456+0100 ..."
    private func extractTimestamp(from line: String) -> Date? {
        let components = line.components(separatedBy: " ")
        if components.count >= 2 {
            let dateStr = components[0] + " " + components[1]
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
            return formatter.date(from: dateStr)
        }
        return nil
    }
}
