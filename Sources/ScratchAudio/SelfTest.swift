import AVFoundation
import Foundation
import ScratchCore

/// Auto-test hors ligne du pipeline audio (lancé par `ScratchApp --selftest`).
///
/// Il utilise le mode de rendu manuel d'`AVAudioEngine` : aucun périphérique de sortie n'est
/// nécessaire, ce qui permet de l'exécuter sur les runners macOS de la CI.
///
/// Version de départ (sprint 0) : rend une sinusoïde et vérifie le niveau de sortie.
/// À remplacer par le scénario de scratch complet (story « Self-test de scratch »).
public enum SelfTest {
    public struct Report: Codable, Sendable {
        public var passed: Bool
        public var checks: [String: Bool]
        public var details: [String: Double]
    }

    public static func run(sampleRate: Double = 48_000, seconds: Double = 1.0) throws -> Report {
        let engine = AVAudioEngine()
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw NSError(domain: "ScratchAudio.SelfTest", code: 1)
        }
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)

        var phase = 0.0
        let increment = 2.0 * Double.pi * 440.0 / sampleRate
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let value = Float(sin(phase) * 0.5)
                phase += increment
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        try engine.start()
        defer { engine.stop() }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                            frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw NSError(domain: "ScratchAudio.SelfTest", code: 2)
        }
        let totalFrames = AVAudioFramePosition(seconds * sampleRate)
        var sumSquares = 0.0
        var count = 0.0
        var hasNaN = false
        while engine.manualRenderingSampleTime < totalFrames {
            let remaining = AVAudioFrameCount(totalFrames - engine.manualRenderingSampleTime)
            let status = try engine.renderOffline(min(buffer.frameCapacity, remaining), to: buffer)
            guard status == .success, let data = buffer.floatChannelData else { break }
            for frame in 0..<Int(buffer.frameLength) {
                let sample = Double(data[0][frame])
                if sample.isNaN { hasNaN = true }
                sumSquares += sample * sample
                count += 1
            }
        }
        let rms = count > 0 ? (sumSquares / count).squareRoot() : 0
        let checks = ["rendered": count > 0, "audible": rms > 0.1, "noNaN": !hasNaN]
        return Report(passed: checks.values.allSatisfy { $0 }, checks: checks, details: ["rms": rms, "frames": count])
    }
}
