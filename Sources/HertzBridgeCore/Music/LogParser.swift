import Foundation

public protocol LogParserDelegate: AnyObject {
    func didDetectSampleRate(_ rate: Double)
}

public class LogParser {
    public static let shared = LogParser()
    public weak var delegate: LogParserDelegate?
    
    private var process: Process?
    private var pipe: Pipe?
    
    // Regex to match standard sample rates in various formats
    // e.g. "96000", "96000.0", "96 kHz" (normalized)
    // We strictly look for standard audio rates to reduce false positives
    private let ratePatterns: [String] = [
        "44100", "48000", "88200", "96000", "176400", "192000", "352800", "384000", "705600", "768000"
    ]
    
    private init() {}
    
    public func startMonitoring() {
        stopMonitoring()
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        
        // Monitor just the Music process (like the old working version)
        task.arguments = [
            "stream",
            "--process", "Music"
        ]
        
        print("LogParser started monitoring 'Music' process...")
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        try? task.run()
        self.process = task
        self.pipe = pipe
        
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if let output = String(data: data, encoding: .utf8) {
                self?.parseLogBatch(output)
            }
        }
    }
    
    public func stopMonitoring() {
        process?.terminate()
        process = nil
        pipe = nil
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
        // Simple approach: just look for standard sample rate numbers in the line
        // This is what the old working version did
        for rateStr in ratePatterns {
            if line.contains(rateStr) {
                if let rate = Double(rateStr) {
                    // print("LogParser: Detected \(rate)Hz from logs")
                    delegate?.didDetectSampleRate(rate)
                    return
                }
            }
        }
    }
}
