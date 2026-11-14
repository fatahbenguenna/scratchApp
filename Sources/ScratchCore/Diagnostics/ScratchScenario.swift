import Foundation

/// Scénario de scratch hors ligne et déterministe, indépendant de l'hôte de rendu (story 1.5 CA 10 ;
/// NFR11 ; base du self-test de la story 2.4).
///
/// Chronologie (platine A, secondes) : réglages par défaut et chargement, tête à 1 s ; START à
/// 0,05 ; tenue immobile de 1,5 à 2,4 ; poussée avant (¼ de tour) de 2,4 à 2,65, retour arrière
/// de 2,75 à 3,0 ; baby scratch (huit inversions par seconde sur un quart de tour) de 3,1 à 4,1 ;
/// relâchement à 4,5 ; voie A fermée au crossfader de 5,0 à 5,5, rouverte à 5,5 ; fermée à 6,0 et
/// rouverte par la coupure momentanée de 6,1 à 6,3 ; STOP à 6,6 ; fin à 7,8. Les touches sont
/// datées à 120 Hz et livrées par paires (60 lots par seconde) ; les commandes tombent au début des
/// tampons qui les contiennent, d'où un rendu identique à l'échantillon près pour une même taille de
/// tampon. Le clip de A doit durer au moins 7 s ; B, s'il est chargé, reste à l'arrêt.
///
/// Fil de contrôle uniquement : le scénario et son analyseur utilisent des tableaux et ne sont
/// jamais exécutés dans le rendu.
public struct ScratchScenario: Sendable {
    /// Une commande à envoyer avant de rendre le tampon qui contient `frame`.
    public struct Event: Sendable {
        public var frame: Int64
        public var command: EngineCommand
    }

    /// Noms stables des vérifications (rapport JSON du self-test, story 2.4).
    public static let checkNames = [
        "nominalSpeedReached", "silentWhileHeldStill", "platterSpinsWhileHeld", "rateSignFollowsGesture",
        "noClickAtReversals", "catchUpWithinSlipmatTime", "closedChannelSilent", "cutInWithin1ms",
        "peakAtMost0dBFS", "noNaN", "babyScratchReturnsToStart",
    ]

    /// Repères de la chronologie (s).
    enum Time {
        static let start = 0.05
        static let nominal = 1.0...1.4
        static let holdBegin = 1.5
        static let heldStill = 1.9...2.4
        static let pushBegin = 2.4, pushEnd = 2.65
        static let pullBegin = 2.75, pullEnd = 3.0
        static let pushCheck = 2.5...2.62
        static let pullCheck = 2.85...2.97
        static let babyBegin = 3.1, babyEnd = 4.1
        static let returnCheck = 4.4
        static let release = 4.5
        static let closeCrossfader = 5.0, openCrossfader = 5.5
        static let closedFirst = 5.05...5.45
        static let reference = 4.8...5.0
        static let closeAgain = 6.0, cutOpen = 6.1, cutClose = 6.3
        static let closedSecond = 6.35...6.55
        static let stop = 6.6
        static let end = 7.8
        /// Position de la tête au départ (s).
        static let startPosition = 1.0
    }

    public let sampleRate: Double
    public let blockFrames: Int
    public let totalFrames: Int64
    /// Commandes triées par trame.
    public let events: [Event]

    public init(clipA: AudioClip, clipB: AudioClip?, sampleRate: Double = 48_000, blockFrames: Int = 256) {
        self.sampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 48_000
        self.blockFrames = max(1, blockFrames)
        totalFrames = Int64((Time.end * self.sampleRate).rounded())
        events = Self.timeline(clipA: clipA, clipB: clipB, sampleRate: self.sampleRate)
    }

    /// Commandes à envoyer avant de rendre le tampon commençant à `frame` (événements de
    /// `[frame ; frame + blockFrames[`).
    public func events(forBlockStartingAt frame: Int64) -> [EngineCommand] {
        let end = frame + Int64(blockFrames)
        var low = 0
        var high = events.count
        while low < high {
            let middle = (low + high) / 2
            if events[middle].frame < frame { low = middle + 1 } else { high = middle }
        }
        var commands = [EngineCommand]()
        var index = low
        while index < events.count, events[index].frame < end {
            commands.append(events[index].command)
            index += 1
        }
        return commands
    }

    public func makeAnalyzer() -> ScenarioAnalyzer {
        ScenarioAnalyzer(sampleRate: sampleRate, blockFrames: blockFrames)
    }

    /// Résultat d'une exécution complète.
    public struct Run: Sendable {
        public var report: ScenarioReport
        public var left: [Float]
        public var right: [Float]
    }

    /// Rend tout le scénario sur `engine` (rendu direct, hors ligne) et renvoie le rapport et la
    /// sortie. Le moteur doit être neuf ; ses clips remplacés sont rendus au fil de contrôle.
    public func run(on engine: ScratchEngine) -> Run {
        var analyzer = makeAnalyzer()
        var left = [Float](repeating: 0, count: Int(totalFrames))
        var right = [Float](repeating: 0, count: Int(totalFrames))
        var frame: Int64 = 0
        while frame < totalFrames {
            for command in events(forBlockStartingAt: frame) { engine.send(command) }
            let count = Int(min(Int64(blockFrames), totalFrames - frame))
            let offset = Int(frame)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    let pointerL = l.baseAddress! + offset
                    let pointerR = r.baseAddress! + offset
                    engine.render(frameCount: count, left: pointerL, right: pointerR)
                    analyzer.consume(frame: frame, left: pointerL, right: pointerR, count: count,
                                     snapshot: engine.latestSnapshot())
                }
            }
            engine.drainReleasedClips()
            frame += Int64(count)
        }
        return Run(report: analyzer.report(), left: left, right: right)
    }

    // MARK: Chronologie

    private static func timeline(clipA: AudioClip, clipB: AudioClip?, sampleRate: Double) -> [Event] {
        var events = [Event]()
        func at(_ time: Double, _ command: EngineCommand) {
            events.append(Event(frame: Int64((time * sampleRate).rounded(.down)), command: command))
        }
        at(0, .startDuration(TurntableConstants.defaultStartDuration))
        at(0, .brakeDuration(TurntableConstants.defaultBrakeDuration))
        at(0, .slipmatCatchUp(TurntableConstants.defaultSlipmatCatchUp))
        at(0, .crossfaderCurve(1))
        at(0, .crossfader(0.5))
        at(0, .hamster(false))
        for deck in DeckID.allCases {
            at(0, .lineFader(deck, 1))
            at(0, .momentaryCut(deck, open: false))
            at(0, .speed(deck, .rpm33))
            at(0, .pitch(deck, 0))
            at(0, .resistance(deck, TurntableConstants.defaultResistance))
        }
        at(0, .load(.a, clipA))
        if let clipB { at(0, .load(.b, clipB)) }
        at(0, .seek(.a, seconds: Time.startPosition))
        at(Time.start, .motor(.a, on: true))

        // Finger: touches at 120 Hz delivered in pairs (one batch per 1/60 s).
        let quarter = Double.pi / 2
        func finger(_ t: Double) -> Double {
            switch t {
            case ..<Time.pushBegin: return 0
            case ..<Time.pushEnd: return quarter * (t - Time.pushBegin) / (Time.pushEnd - Time.pushBegin)
            case ..<Time.pullBegin: return quarter
            case ..<Time.pullEnd: return quarter * (1 - (t - Time.pullBegin) / (Time.pullEnd - Time.pullBegin))
            case Time.babyBegin..<Time.babyEnd: return quarter / 2 * sin(2 * Double.pi * 8 * (t - Time.babyBegin))
            default: return 0
            }
        }
        at(Time.holdBegin, .touchBegan(.a, angle: finger(Time.holdBegin), time: Time.holdBegin))
        var touch = 1
        while true {
            let time = Time.holdBegin + Double(touch) / 120
            if time > Time.release { break }
            let delivery = Time.holdBegin + Double((touch + 1) / 2 * 2) / 120
            at(delivery, .touchMoved(.a, angle: finger(time), time: time))
            touch += 1
        }
        at(Time.release, .touchEnded(.a, time: Time.release))

        at(Time.closeCrossfader, .crossfader(1))
        at(Time.openCrossfader, .crossfader(0))
        at(Time.closeAgain, .crossfader(1))
        at(Time.cutOpen, .momentaryCut(.a, open: true))
        at(Time.cutClose, .momentaryCut(.a, open: false))
        at(Time.stop, .crossfader(0.5))
        at(Time.stop, .motor(.a, on: false))
        // Stable sort: same-frame commands keep their order.
        return events.enumerated().sorted { ($0.element.frame, $0.offset) < ($1.element.frame, $1.offset) }.map(\.element)
    }
}

/// Rapport d'un scénario : vérifications nommées et mesures (story 1.5 ; JSON du self-test 2.4).
public struct ScenarioReport: Codable, Sendable, Equatable {
    public var passed: Bool
    public var checks: [String: Bool]
    public var details: [String: Double]

    public init(checks: [String: Bool], details: [String: Double]) {
        self.checks = checks
        self.details = details
        passed = ScratchScenario.checkNames.allSatisfy { checks[$0] == true }
    }
}
