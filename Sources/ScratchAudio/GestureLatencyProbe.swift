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
///
/// **Phases** (#114). Sur un appareil, l'horloge des touches et les images d'affichage n'ont aucune
/// relation de phase, et le retard appris par le rejeu en dépend. Sur une image, il décroît presque
/// linéairement, du pire cas juste après une coïncidence jusqu'au meilleur juste avant. La phase
/// alignée exacte, où une touche sur deux est livrée à l'instant même de son image, est un point
/// singulier : c'est le meilleur cas, et sa probabilité est nulle sur un appareil. La mesure est donc
/// répétée au milieu de `phases` intervalles égaux d'une image, `(k + ½) / (phases × displayRate)`,
/// chacun avec un moteur neuf. Elle publie la **moyenne**, référence de D-56, exacte dès 8 phases,
/// ainsi que le maximum, publié sans décider de la gate, et le minimum. Le maximum des phases mesurées
/// approche par défaut la borne supérieure, d'environ 0,5 ms à 120 Hz.
/// Pendant l'attente d'une réponse, chaque tampon est rendu échantillon par échantillon : aucune
/// commande n'arrive au milieu d'un tampon, et le moteur calcule sa physique échantillon par
/// échantillon, si bien que le rendu est le même qu'en un seul appel, et que l'instantané de chaque
/// échantillon donne sa vitesse.
public enum GestureLatencyProbe {
    /// Valeurs d'une partie moteur sur les phases touches/affichage, en secondes.
    public struct PhaseSpread: Equatable, Sendable {
        /// Une valeur par phase, dans l'ordre des décalages.
        public var values: [Double]

        public init(values: [Double]) {
            self.values = values
        }

        public var mean: Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
        public var maximum: Double { values.max() ?? 0 }
        public var minimum: Double { values.min() ?? 0 }
    }

    /// Latence geste→son décomposée, en secondes.
    public struct Measurement: Equatable, Sendable {
        /// Partie moteur en régime appris (second geste), sur les phases.
        public var learned: PhaseSpread
        /// Partie moteur du premier geste, au retard initial du rejeu, sur les phases.
        public var firstGesture: PhaseSpread
        public var bufferDuration: Double
        public var outputLatency: Double

        public init(learned: PhaseSpread, firstGesture: PhaseSpread, bufferDuration: Double, outputLatency: Double) {
            self.learned = learned
            self.firstGesture = firstGesture
            self.bufferDuration = bufferDuration
            self.outputLatency = outputLatency
        }

        /// Partie moteur de référence (D-54, D-56) : régime appris, moyenne sur au moins 8 phases.
        public var engineDelay: Double { learned.mean }
        /// Partie moteur du premier geste, moyenne sur la phase.
        public var firstGestureEngineDelay: Double { firstGesture.mean }
        /// Latence de référence (D-15, D-54, D-56) : régime appris, moyenne sur la phase, tampon et
        /// latence de sortie annoncée compris.
        public var total: Double { engineDelay + bufferDuration + outputLatency }
        /// Pire phase du régime appris, latence de sortie annoncée comprise : publiée, sans décider de
        /// la gate (D-56).
        public var worstTotal: Double { learned.maximum + bufferDuration + outputLatency }
        /// Latence du premier geste, moyenne sur la phase, latence de sortie annoncée comprise.
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
    /// Phases touches/affichage mesurées par défaut, réparties sur une image.
    public static let defaultPhaseCount = 8

    /// Mesure par le graphe AVAudioEngine en rendu manuel hors ligne, sur `phases` décalages répartis
    /// sur une image d'affichage (un moteur et un graphe neufs par phase).
    public static func measure(sampleRate: Double = 48_000,
                               bufferFrames: Int = TurntableConstants.preferredBufferFrames,
                               displayRate: Double = 120, outputLatency: Double = 0,
                               phases: Int = defaultPhaseCount) throws -> Measurement {
        let frames = max(1, bufferFrames)
        var learned: [Double] = []
        var firstGesture: [Double] = []
        for offset in phaseOffsets(count: phases, displayRate: displayRate) {
            let delays = try graphEngineDelays(sampleRate: sampleRate, bufferFrames: frames,
                                               displayRate: displayRate, phaseOffset: offset)
            learned.append(delays.learned)
            firstGesture.append(delays.firstGesture)
        }
        return Measurement(learned: PhaseSpread(values: learned), firstGesture: PhaseSpread(values: firstGesture),
                           bufferDuration: Double(frames) / sampleRate, outputLatency: outputLatency)
    }

    /// Décalages du début des gestes : `(k + base) / (count × displayRate)`, pour `k` de 0 à
    /// `count − 1`. Par défaut, `base` vaut ½ : le milieu de chaque intervalle, sans la phase alignée.
    static func phaseOffsets(count: Int, displayRate: Double, base: Double = 0.5) -> [Double] {
        let phases = max(1, count)
        return (0 ..< phases).map { (base + Double($0)) / (Double(phases) * displayRate) }
    }

    /// Une phase, par le graphe AVAudioEngine en rendu manuel.
    private static func graphEngineDelays(sampleRate: Double, bufferFrames frames: Int, displayRate: Double,
                                          phaseOffset: Double) throws -> EngineDelays {
        let engine = ScratchEngine(outputSampleRate: sampleRate)
        let graph = try ScratchAudioGraph.offline(engine: engine, sampleRate: sampleRate,
                                                  maximumFrameCount: AVAudioFrameCount(max(frames, ScratchEngine.maximumBlockFrames)))
        try graph.avEngine.start()
        defer { graph.avEngine.stop() }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: graph.avEngine.manualRenderingFormat,
                                            frameCapacity: AVAudioFrameCount(frames))
        else { throw AudioOutputError.invalidFormat }
        let delays = try engineDelays(engine: engine, sampleRate: sampleRate, bufferFrames: frames,
                                      displayRate: displayRate, phaseOffset: phaseOffset) { count in
            let status = try graph.avEngine.renderOffline(AVAudioFrameCount(count), to: buffer)
            if status != .success { throw AudioOutputError.noResponse }
        }
        guard let delays else { throw AudioOutputError.noResponse }
        return delays
    }

    /// Partie moteur des deux gestes, dans une phase. `phaseOffset` décale le début des deux gestes
    /// (secondes). `render` rend le nombre de trames demandé, au plus `bufferFrames` (graphe en rendu
    /// manuel, ou rendu direct). Renvoie `nil` si un geste reste sans réponse pendant une seconde, ou
    /// si le disque n'est pas revenu au repos avant le second geste.
    static func engineDelays(engine: ScratchEngine, sampleRate: Double, bufferFrames: Int, displayRate: Double,
                             phaseOffset: Double = 0, render: (Int) throws -> Void) rethrows -> EngineDelays? {
        let clip = AudioClip(title: "latence", sampleRate: sampleRate, frameCount: Int(sampleRate * 4)) { left, right in
            for index in 0 ..< left.count {
                let value = Float(0.5 * sin(2 * Double.pi * 440 * Double(index) / sampleRate))
                left[index] = value
                right[index] = value
            }
        }
        engine.send(.load(.a, clip))
        let starts = [touchTime + phaseOffset, learnedTouchTime + phaseOffset]
        let events = gesture(at: starts[0], duration: warmUpDuration, releases: true, displayRate: displayRate)
            + gesture(at: starts[1], duration: responseTimeout, releases: false, displayRate: displayRate)
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
