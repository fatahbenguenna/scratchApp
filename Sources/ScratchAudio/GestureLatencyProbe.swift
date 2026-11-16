import AVFoundation
import Foundation
import ScratchCore

/// Sonde de la latence geste→son (story 2.1 CA 11 ; D-15, réserve R2 ; méthode de D-54 ; mesures de
/// 4.3 et 6.3).
///
/// Latence = du temps système d'un événement de geste à la sortie du son qui y répond. Elle se
/// décompose ainsi :
/// - **partie moteur** (`engineDelay`), mesurée hors ligne par le graphe AVAudioEngine en rendu
///   manuel. Elle va du premier mouvement horodaté du doigt au **premier échantillon** où le disque
///   répond (vitesse ≥ 2 % de la vitesse nominale), et non à la fin du tampon qui le contient. Elle
///   comprend :
///   - la livraison des touches par image d'affichage ;
///   - le retard de rejeu du doigt ;
///   - le découpage en tampons ;
///   - le départ du suivi ;
/// - **un tampon** (`bufferDuration`) : le tampon rendu sort après avoir été calculé ;
/// - **la latence de sortie annoncée** (`outputLatency`) : périphérique et pilote.
///
/// **Deux gestes** (D-54). Le premier part du retard initial fixe du rejeu (14 ms), quelle que soit la
/// cadence d'affichage. Il sert d'échauffement : 1,5 s à la vitesse nominale, puis relâchement, et le
/// disque revient au repos en roue libre. Le second geste est mesuré en **régime appris**, avec le
/// retard que le rejeu a appris à la cadence d'affichage : c'est ce que le DJ ressent en jouant, et
/// c'est la mesure de référence (`engineDelay`, `total`). Le premier geste reste publié
/// (`firstGestureEngineDelay`).
///
/// Chaque geste reprend celui de `ScratchScenario` : disque à l'arrêt, doigt posé, puis mouvement à
/// la vitesse nominale. Les touches sont horodatées à 240 Hz et livrées à chaque image d'affichage,
/// comme en vrai. Une commande n'est vue que par le premier tampon qui commence après sa livraison.
/// Pendant l'attente d'une réponse, chaque tampon est rendu échantillon par échantillon : aucune
/// commande n'arrive au milieu d'un tampon, et le moteur calcule sa physique échantillon par
/// échantillon, si bien que le rendu est le même qu'en un seul appel, et que l'instantané de chaque
/// échantillon donne sa vitesse.
public enum GestureLatencyProbe {
    /// Latence geste→son décomposée, en secondes.
    public struct Measurement: Equatable, Sendable {
        /// Partie moteur en régime appris (second geste) : la mesure de référence (D-54).
        public var engineDelay: Double
        /// Partie moteur du premier geste, au retard initial du rejeu.
        public var firstGestureEngineDelay: Double
        public var bufferDuration: Double
        public var outputLatency: Double

        public init(engineDelay: Double, firstGestureEngineDelay: Double, bufferDuration: Double, outputLatency: Double) {
            self.engineDelay = engineDelay
            self.firstGestureEngineDelay = firstGestureEngineDelay
            self.bufferDuration = bufferDuration
            self.outputLatency = outputLatency
        }

        /// Latence de référence (D-15, D-54) : régime appris, latence de sortie annoncée comprise.
        public var total: Double { engineDelay + bufferDuration + outputLatency }
        /// Latence du premier geste, latence de sortie annoncée comprise.
        public var firstGestureTotal: Double { firstGestureEngineDelay + bufferDuration + outputLatency }
    }

    /// Partie moteur des deux gestes, en secondes.
    struct EngineDelays: Equatable {
        var firstGesture: Double
        var learned: Double
    }

    /// Réponse du disque retenue : 2 % de la vitesse nominale.
    static let responseThreshold = 0.02
    /// Le doigt se pose à 0,1 s ; les tampons précédents installent le moteur.
    static let touchTime = 0.1
    /// Durée du geste d'échauffement, relâché ensuite.
    static let warmUpDuration = 1.5
    /// Second geste, mesuré en régime appris : le disque est revenu au repos (roue libre de 150 ms
    /// après le rejeu du relâchement).
    static let learnedTouchTime = touchTime + 2
    /// Cadence des horodatages des touches (Hz).
    static let touchRate = 240.0
    /// Délai au-delà duquel un geste est réputé sans réponse.
    static let responseTimeout = 1.0

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
        let delays = try engineDelays(engine: engine, sampleRate: sampleRate, bufferFrames: frames,
                                      displayRate: displayRate) { count in
            let status = try graph.avEngine.renderOffline(AVAudioFrameCount(count), to: buffer)
            if status != .success { throw AudioOutputError.noResponse }
        }
        guard let delays else { throw AudioOutputError.noResponse }
        return Measurement(engineDelay: delays.learned, firstGestureEngineDelay: delays.firstGesture,
                           bufferDuration: Double(frames) / sampleRate, outputLatency: outputLatency)
    }

    /// Partie moteur des deux gestes. `render` rend le nombre de trames demandé, au plus
    /// `bufferFrames` (graphe en rendu manuel, ou rendu direct). Renvoie `nil` si un geste reste sans
    /// réponse pendant une seconde, ou si le disque n'est pas revenu au repos avant le second geste.
    static func engineDelays(engine: ScratchEngine, sampleRate: Double, bufferFrames: Int, displayRate: Double,
                             render: (Int) throws -> Void) rethrows -> EngineDelays? {
        let clip = AudioClip(title: "latence", sampleRate: sampleRate, frameCount: Int(sampleRate * 4)) { left, right in
            for index in 0 ..< left.count {
                let value = Float(0.5 * sin(2 * Double.pi * 440 * Double(index) / sampleRate))
                left[index] = value
                right[index] = value
            }
        }
        engine.send(.load(.a, clip))
        let events = gesture(at: touchTime, duration: warmUpDuration, releases: true, displayRate: displayRate)
            + gesture(at: learnedTouchTime, duration: responseTimeout, releases: false, displayRate: displayRate)
        let starts = [touchTime, learnedTouchTime]
        var responses: [Double] = []
        var begun = 0
        var next = 0
        var frame = 0
        while responses.count < starts.count {
            let now = Double(frame) / sampleRate
            if now >= starts[responses.count] + responseTimeout { return nil }
            while next < events.count, events[next].delivery <= now {
                if case .touchBegan = events[next].command {
                    // The learned gesture starts from rest, like the first one.
                    if begun > 0, engine.latestSnapshot()[.a].playbackRate != 0 { return nil }
                    begun += 1
                }
                engine.send(events[next].command)
                next += 1
            }
            guard begun > responses.count else {
                try render(bufferFrames)
                frame += bufferFrames
                continue
            }
            // Sample by sample: the snapshot after each frame gives the speed of that frame.
            for rendered in 0 ..< bufferFrames {
                try render(1)
                frame += 1
                if abs(engine.latestSnapshot()[.a].playbackRate) >= responseThreshold {
                    responses.append(Double(frame) / sampleRate - (starts[responses.count] + 1 / touchRate))
                    let remaining = bufferFrames - rendered - 1
                    if remaining > 0 { try render(remaining) }
                    frame += remaining
                    break
                }
            }
        }
        return EngineDelays(firstGesture: responses[0], learned: responses[1])
    }

    /// Geste à la vitesse nominale, posé à `start` : touches horodatées à 240 Hz, livrées à l'image
    /// d'affichage suivante (ou à la même image si elles tombent dessus) ; relâchement à la fin si
    /// `releases`.
    private static func gesture(at start: Double, duration: Double, releases: Bool,
                                displayRate: Double) -> [(delivery: Double, command: EngineCommand)] {
        let omega = TurntableConstants.referenceAngularVelocity
        // A timestamp on a frame boundary belongs to that frame (no floating-point slip to the next).
        func delivery(_ time: Double) -> Double { (time * displayRate - 1e-9).rounded(.up) / displayRate }
        var events: [(delivery: Double, command: EngineCommand)] = [(delivery(start), .touchBegan(.a, angle: 0, time: start))]
        let count = Int((duration * touchRate).rounded())
        for index in 1 ... count {
            let time = start + Double(index) / touchRate
            events.append((delivery(time), .touchMoved(.a, angle: omega * (time - start), time: time)))
        }
        if releases {
            let end = start + Double(count) / touchRate
            events.append((delivery(end), .touchEnded(.a, time: end)))
        }
        return events
    }
}
