import AVFoundation
import Foundation
import ScratchCore

/// Sonde de la latence geste→son (story 2.1 CA 11 ; D-15, réserve R2 ; mesures de 4.3 et 6.3).
///
/// Latence = du temps système d'un événement de geste à la sortie du son qui y répond. Elle se
/// décompose ainsi :
/// - **partie moteur** (`engineDelay`), mesurée hors ligne par le graphe AVAudioEngine en rendu
///   manuel. Elle va du premier mouvement horodaté du doigt à la fin du premier tampon rendu où le
///   disque répond (vitesse ≥ 2 % de la vitesse nominale). Elle comprend :
///   - la livraison des touches par image d'affichage ;
///   - le retard de rejeu du doigt ;
///   - le découpage en tampons ;
///   - le départ du suivi ;
/// - **un tampon** (`bufferDuration`) : le tampon rendu sort après avoir été calculé ;
/// - **la latence de sortie annoncée** (`outputLatency`) : périphérique et pilote.
///
/// Le geste simulé reprend celui de `ScratchScenario` : disque à l'arrêt, doigt posé, puis mouvement
/// à la vitesse nominale. Les touches sont horodatées à 240 Hz et livrées à chaque image
/// d'affichage, comme en vrai. Une commande n'est vue que par le premier tampon qui commence après
/// sa livraison.
public enum GestureLatencyProbe {
    /// Latence geste→son décomposée, en secondes.
    public struct Measurement: Equatable, Sendable {
        public var engineDelay: Double
        public var bufferDuration: Double
        public var outputLatency: Double

        public var total: Double { engineDelay + bufferDuration + outputLatency }
    }

    /// Réponse du disque retenue : 2 % de la vitesse nominale.
    static let responseThreshold = 0.02
    /// Le doigt se pose à 0,1 s ; les tampons précédents installent le moteur.
    static let touchTime = 0.1
    /// Cadence des horodatages des touches (Hz).
    static let touchRate = 240.0

    /// Mesure par le graphe AVAudioEngine en rendu manuel hors ligne.
    public static func measure(sampleRate: Double = 48_000,
                               bufferFrames: Int = TurntableConstants.preferredBufferFrames,
                               displayRate: Double = 120, outputLatency: Double = 0) throws -> Measurement {
        let frames = max(1, bufferFrames)
        let engine = ScratchEngine(outputSampleRate: sampleRate)
        let graph = try ScratchAudioGraph.offline(engine: engine, sampleRate: sampleRate,
                                                  maximumFrameCount: AVAudioFrameCount(max(frames, ScratchEngine.maximumBlockFrames)))
        try graph.avEngine.start()
        defer { graph.avEngine.stop() }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: graph.avEngine.manualRenderingFormat,
                                            frameCapacity: AVAudioFrameCount(frames))
        else { throw AudioOutputError.invalidFormat }
        let delay = try engineDelay(engine: engine, sampleRate: sampleRate, bufferFrames: frames, displayRate: displayRate) {
            let status = try graph.avEngine.renderOffline(AVAudioFrameCount(frames), to: buffer)
            if status != .success { throw AudioOutputError.noResponse }
        }
        guard let delay else { throw AudioOutputError.noResponse }
        return Measurement(engineDelay: delay, bufferDuration: Double(frames) / sampleRate, outputLatency: outputLatency)
    }

    /// Partie moteur de la latence. `renderBuffer` rend un tampon de `bufferFrames` trames du moteur
    /// (graphe en rendu manuel, ou rendu direct). Renvoie `nil` sans réponse au bout d'une seconde.
    static func engineDelay(engine: ScratchEngine, sampleRate: Double, bufferFrames: Int, displayRate: Double,
                            renderBuffer: () throws -> Void) rethrows -> Double? {
        let clip = AudioClip(title: "latence", sampleRate: sampleRate, frameCount: Int(sampleRate * 2)) { left, right in
            for index in 0 ..< left.count {
                let value = Float(0.5 * sin(2 * Double.pi * 440 * Double(index) / sampleRate))
                left[index] = value
                right[index] = value
            }
        }
        engine.send(.load(.a, clip))
        let omega = TurntableConstants.referenceAngularVelocity
        let firstMove = touchTime + 1 / touchRate
        var events: [(delivery: Double, command: EngineCommand)] = [(touchTime, .touchBegan(.a, angle: 0, time: touchTime))]
        for index in 1 ... Int(touchRate) {
            let time = touchTime + Double(index) / touchRate
            let delivery = (time * displayRate).rounded(.up) / displayRate
            events.append((delivery, .touchMoved(.a, angle: omega * (time - touchTime), time: time)))
        }
        var next = 0
        var frame = 0
        let limit = Int((touchTime + 1) * sampleRate)
        while frame < limit {
            let now = Double(frame) / sampleRate
            while next < events.count, events[next].delivery <= now {
                engine.send(events[next].command)
                next += 1
            }
            try renderBuffer()
            frame += bufferFrames
            if abs(engine.latestSnapshot()[.a].playbackRate) >= responseThreshold {
                return Double(frame) / sampleRate - firstMove
            }
        }
        return nil
    }
}
