import Foundation
import AudioToolbox

public class FileParser {
    public static let shared = FileParser()
    
    private init() {}
    
    public func getAudioFormat(path: String) -> (sampleRate: Double, bitDepth: Int?, codec: String?)? {
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
        
        let codecStr = formatIDToString(formatID)
        
        // For ALAC and other lossless codecs, try to get source bit depth
        if formatID == kAudioFormatAppleLossless || rawBitDepth == 0 {
            var sourceBitDepth: UInt32 = 0
            var propSize = UInt32(MemoryLayout<UInt32>.size)
            let err = AudioFileGetProperty(file, kAudioFilePropertySourceBitDepth, &propSize, &sourceBitDepth)
            
            if err == noErr && sourceBitDepth > 0 {
                print("FileParser: ALAC/Lossless format, source bit depth: \(sourceBitDepth)")
                return (sampleRate, Int(sourceBitDepth), codecStr)
            }
        }
        
        // For raw PCM formats
        if rawBitDepth > 0 {
            return (sampleRate, rawBitDepth, codecStr)
        }
        
        // Truly compressed formats (AAC, MP3) - no real bit depth
        if formatID == kAudioFormatMPEG4AAC || formatID == kAudioFormatMPEGLayer3 {
            print("FileParser: Compressed format (AAC/MP3), bit depth N/A")
            return (sampleRate, nil, codecStr)
        }
        
        // Unknown - return nil for bit depth
        print("FileParser: Unknown format \(formatID), cannot determine bit depth")
        return (sampleRate, nil, codecStr)
    }
    
    private func formatIDToString(_ formatID: UInt32) -> String {
        switch formatID {
        case kAudioFormatLinearPCM: return "PCM"
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatMPEG4AAC: return "AAC"
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatFLAC: return "FLAC"
        case kAudioFormatOpus: return "Opus"
        case kAudioFormatAMR: return "AMR"
        case kAudioFormatAC3: return "AC3"
        default:
            // Convert FourCC to string if possible, else "Unknown"
            let bytes = [
                UInt8((formatID >> 24) & 0xFF),
                UInt8((formatID >> 16) & 0xFF),
                UInt8((formatID >> 8) & 0xFF),
                UInt8(formatID & 0xFF)
            ]
            if let str = String(bytes: bytes, encoding: .ascii) {
                return str.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return "Unknown"
        }
    }
    

}
