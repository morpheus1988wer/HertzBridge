import Foundation
import CoreAudio

public struct AudioDeviceInfo: Equatable {
    public let id: AudioDeviceID
    public let name: String
    public let sampleRate: Double // Nominal rate
}

public struct StreamFormat {
    public let sampleRate: Double
    public let bitDepth: Int
    public let formatID: AudioFormatID
    
    public var description: String {
        return "\(Int(sampleRate))Hz / \(bitDepth)bit"
    }
}

public class DeviceManager {
    public static let shared = DeviceManager()
    
    private init() {}
    
    public func getAllOutputDevices() -> [AudioDeviceInfo] {
        var propertySize = UInt32(0)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let errSize = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize
        )
        
        guard errSize == noErr else { return [] }
        
        let count = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        
        let errData = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceIDs
        )
        
        guard errData == noErr else { return [] }
        
        var devices: [AudioDeviceInfo] = []
        for id in deviceIDs {
            // Filter for Output devices only
            if isOutputDevice(id) {
                if let info = getDeviceInfo(id) {
                    devices.append(info)
                }
            }
        }
        
        return devices
    }
    
    private func isOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var propertySize = UInt32(0)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let err = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)
        return err == noErr && propertySize > 0
    }
    
    public func getDefaultOutputDevice() -> AudioDeviceInfo? {
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let err = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        )
        
        if err != noErr { return nil }
        return getDeviceInfo(deviceID)
    }
    
    public func getDeviceInfo(_ deviceID: AudioDeviceID) -> AudioDeviceInfo? {
        var deviceName = "" as CFString
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var err = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &deviceName)
        if err != noErr { return nil }
        
        var nominalSampleRate = Float64(0)
        propertySize = UInt32(MemoryLayout<Float64>.size)
        propertyAddress.mSelector = kAudioDevicePropertyNominalSampleRate
        err = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &nominalSampleRate)
        if err != noErr { nominalSampleRate = 0 }
        
        return AudioDeviceInfo(
            id: deviceID,
            name: deviceName as String,
            sampleRate: nominalSampleRate
        )
    }
    
    // MARK: - Format Control
    
    public func getCurrentFormat(deviceID: AudioDeviceID) -> StreamFormat? {
        // We assume the first output stream represents the device format
        // Ideally we iterate all output streams.
        var format = AudioStreamBasicDescription()
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let err = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &format)
        if err != noErr { return nil }
        
        return StreamFormat(
            sampleRate: format.mSampleRate,
            bitDepth: Int(format.mBitsPerChannel), // Note: For Float32 this might be 32
            formatID: format.mFormatID
        )
    }
    
    /// Sets the device to the best matching physical format for the requested rate and bit depth.
    /// Returns true if successful.
    public func setFormat(deviceID: AudioDeviceID, sampleRate: Double, bitDepth: Int? = nil) -> Bool {
        // Get all available physical formats for this device (Stream-based)
        guard let availableRanges = getAvailableFormats(deviceID: deviceID) else {
            print("Failed to get available physical formats, falling back to nominal rate")
            return setNominalSampleRate(deviceID: deviceID, sampleRate: sampleRate)
        }
        
        // print("=== Format Matching (Real Physical Formats) ===")
        // print("Target: \(sampleRate)Hz / \(bitDepth ?? 0)bit")
        
        // Find best matching format from Real Driver Capabilities
        
        // Filter ranges that support the requested sample rate
        // AudioStreamRangedDescription contains an ASBD (mFormat) and a sample rate range
        let validRanges = availableRanges.filter { range in
            return sampleRate >= range.mSampleRateRange.mMinimum && sampleRate <= range.mSampleRateRange.mMaximum
        }
        
        if validRanges.isEmpty {
            print("✗ No physical format supports rate \(sampleRate)Hz")
            return setNominalSampleRate(deviceID: deviceID, sampleRate: sampleRate)
        }
        
        // Now find best bit depth among valid rate ranges
        
        if let targetDepth = bitDepth {
            // Case A: Specific Depth Requested (Local Files)
            // Priority 1: Exact Bit Depth Match
            if let exactMatch = validRanges.first(where: { Int($0.mFormat.mBitsPerChannel) == targetDepth }) {
                print("✓ Found exact physical match: \(targetDepth)bit")
                var formatToSet = exactMatch.mFormat
                formatToSet.mSampleRate = sampleRate
                return applyFormat(deviceID: deviceID, format: formatToSet)
            }
            // Priority 2: Closest Bit Depth
            if let bestMatch = validRanges.min(by: {
                abs(Int($0.mFormat.mBitsPerChannel) - targetDepth) < abs(Int($1.mFormat.mBitsPerChannel) - targetDepth)
            }) {
                print("✓ Using closest physical depth: \(bestMatch.mFormat.mBitsPerChannel)bit")
                var formatToSet = bestMatch.mFormat
                formatToSet.mSampleRate = sampleRate
                return applyFormat(deviceID: deviceID, format: formatToSet)
            }
        } else {
            // Case B: No Depth Specified (Streaming)
            // Strategy: Try ALL valid formats, starting with Highest Quality.
            // If 32-bit fails, fall back to 24-bit, etc.
            
            let sortedRanges = validRanges.sorted(by: {
                $0.mFormat.mBitsPerChannel > $1.mFormat.mBitsPerChannel // Descending (32 -> 24 -> 16)
            })
            
            for range in sortedRanges {
                var formatToSet = range.mFormat
                formatToSet.mSampleRate = sampleRate
                
                if applyFormat(deviceID: deviceID, format: formatToSet) {
                    // print("✓ Successfully set streaming format: \(sampleRate)Hz / \(depth)bit")
                    return true
                } else {
                    // print("⚠️ Failed to apply \(depth)bit format, trying next...")
                }
            }
            // If all failed
            print("✗ All attempts to set physical format failed.")
        }
        
        return false
    }
    
    private func setNominalSampleRate(deviceID: AudioDeviceID, sampleRate: Double) -> Bool {
        var newRate = Float64(sampleRate)
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyNominalSampleRate,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let err = AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<Float64>.size),
            &newRate
        )
        
        return err == noErr
    }
    
    private func getAvailableFormats(deviceID: AudioDeviceID) -> [AudioStreamRangedDescription]? {
        // 1. Get the Output Stream ID
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        var dataSize: UInt32 = 0
        var err = AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize)
        guard err == noErr, dataSize > 0 else { return nil }
        
        let streamCount = Int(dataSize) / MemoryLayout<AudioStreamID>.size
        var streamIDs = [AudioStreamID](repeating: 0, count: streamCount)
        err = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &streamIDs)
        guard err == noErr, let mainStream = streamIDs.first else { return nil }
        
        // 2. Get Available Physical Formats from the Stream
        propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioStreamPropertyAvailablePhysicalFormats,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        err = AudioObjectGetPropertyDataSize(mainStream, &propertyAddress, 0, nil, &dataSize)
        guard err == noErr, dataSize > 0 else { return nil }
        
        let rangeCount = Int(dataSize) / MemoryLayout<AudioStreamRangedDescription>.size
        var ranges = [AudioStreamRangedDescription](repeating: AudioStreamRangedDescription(), count: rangeCount)
        
        err = AudioObjectGetPropertyData(mainStream, &propertyAddress, 0, nil, &dataSize, &ranges)
        guard err == noErr else { return nil }
        
        return ranges
    }
    
    private func applyFormat(deviceID: AudioDeviceID, format: AudioStreamBasicDescription) -> Bool {
        var newFormat = format
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamFormat,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let err = AudioObjectSetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &newFormat
        )
        
        if err == noErr {
            print("Applied format: \(format.mSampleRate)Hz / \(format.mBitsPerChannel)bit")
        }
        
        return err == noErr
    }
}
