import Foundation
import AudioToolbox

public class FileParser {
    public static let shared = FileParser()
    
    private init() {}
    
    public func getAudioFormat(path: String) -> (sampleRate: Double, bitDepth: Int?)? {
        let url = URL(fileURLWithPath: path)
        var audioFile: AudioFileID?
        
        let status = AudioFileOpenURL(url as CFURL, .readPermission, 0, &audioFile)
        guard status == noErr, let file = audioFile else { return nil }
        
        defer { AudioFileClose(file) }
        
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        
        let err = AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &format)
        guard err == noErr else { return nil }
        
        let sampleRate = format.mSampleRate
        let rawBitDepth = Int(format.mBitsPerChannel)
        
        // Check format type
        let formatID = format.mFormatID
        
        // For ALAC and other lossless codecs, try to get source bit depth
        if formatID == kAudioFormatAppleLossless || rawBitDepth == 0 {
            var sourceBitDepth: UInt32 = 0
            var propSize = UInt32(MemoryLayout<UInt32>.size)
            let err = AudioFileGetProperty(file, kAudioFilePropertySourceBitDepth, &propSize, &sourceBitDepth)
            
            if err == noErr && sourceBitDepth > 0 {
                print("FileParser: ALAC/Lossless format, source bit depth: \(sourceBitDepth)")
                return (sampleRate, Int(sourceBitDepth))
            }
        }
        
        // For raw PCM formats
        if rawBitDepth > 0 {
            return (sampleRate, rawBitDepth)
        }
        
        // Truly compressed formats (AAC, MP3) - no real bit depth
        if formatID == kAudioFormatMPEG4AAC || formatID == kAudioFormatMPEGLayer3 {
            print("FileParser: Compressed format (AAC/MP3), bit depth N/A")
            return (sampleRate, nil)
        }
        
        // Unknown - return nil for bit depth
        print("FileParser: Unknown format \(formatID), cannot determine bit depth")
        return (sampleRate, nil)
    }
    
    // Legacy method for backward compatibility
    public func getSampleRate(path: String) -> Double? {
        return getAudioFormat(path: path)?.sampleRate
    }
}
