import AVFoundation
import Foundation

/// Fichiers audio de test générés avec `AVAudioFile` pendant le test (story 2.2, CA8).
///
/// Le type de fichier suit l'extension de l'URL (`.wav`, `.aiff`, `.m4a`). Le signal est calculé
/// sur sa première seconde puis répété : il doit être périodique sur une seconde (sinusoïde de
/// fréquence entière, constante), ce qui permet d'écrire vite des fichiers de plusieurs minutes.
enum AudioFixtureWriter {
    enum Encoding {
        case pcm16, float32, aac, alac
    }

    struct WriteError: Error {}

    static func write(to url: URL, encoding: Encoding, sampleRate: Double, channels: Int, frames: Int,
                      layoutTag: AudioChannelLayoutTag? = nil, signal: (_ channel: Int, _ frame: Int) -> Float) throws {
        var settings: [String: Any] = [AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels]
        switch encoding {
        case .pcm16, .float32:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = encoding == .pcm16 ? 16 : 32
            settings[AVLinearPCMIsFloatKey] = encoding == .float32
            settings[AVLinearPCMIsBigEndianKey] = url.pathExtension.lowercased().hasPrefix("aif")
            settings[AVLinearPCMIsNonInterleaved] = false
        case .aac:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = 128_000
        case .alac:
            settings[AVFormatIDKey] = kAudioFormatAppleLossless
            settings[AVEncoderBitDepthHintKey] = 16
        }
        if let layoutTag {
            var layout = AudioChannelLayout()
            layout.mChannelLayoutTag = layoutTag
            settings[AVChannelLayoutKey] = Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
        }
        // The file is finalized when `file` is released, at the end of this function.
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        guard frames > 0 else { return }
        let period = min(frames, Int(sampleRate.rounded()))
        guard let template = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                              frameCapacity: AVAudioFrameCount(period)),
              let data = template.floatChannelData
        else { throw WriteError() }
        for channel in 0 ..< channels {
            for frame in 0 ..< period { data[channel][frame] = signal(channel, frame) }
        }
        var remaining = frames
        while remaining > 0 {
            let count = min(remaining, period)
            template.frameLength = AVAudioFrameCount(count)
            try file.write(from: template)
            remaining -= count
        }
    }

    /// Sinusoïde de `frequency` hertz et d'amplitude `amplitude`, identique sur tous les canaux.
    static func sine(frequency: Double, amplitude: Float, sampleRate: Double) -> (Int, Int) -> Float {
        { _, frame in amplitude * Float(sin(2 * Double.pi * frequency * Double(frame) / sampleRate)) }
    }
}
