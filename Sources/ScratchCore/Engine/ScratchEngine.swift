/// Moteur audio de ScratchApp : deux platines et une table de mixage (architecture §3, §5.1 et §6.2).
///
/// Fils d'exécution :
/// - **fil de contrôle** (fil principal dans l'app) : `send`, `latestSnapshot`, `drainReleasedClips`,
///   `pump` (hôte arrêté seulement) ;
/// - **fil audio** : `render`, appelé par l'hôte (`AudioEngineHost`) ou par un rendu hors ligne.
///
/// Communication : file SPSC de commandes (contrôle → audio), triple tampon d'instantanés
/// (audio → contrôle), file SPSC de retour des clips remplacés (audio → contrôle). `render` ne
/// prend aucun verrou, n'alloue rien et ne libère aucun objet.
///
/// Version minimale (story 0.2) : les commandes sont appliquées et reflétées dans l'instantané,
/// le rendu produit du silence. La physique et le DSP arrivent avec les stories 1.1 à 1.5 (James).
public final class ScratchEngine: EngineControlling, @unchecked Sendable {
    /// Capacité de la file de commandes (plus de 2 s de touches regroupées à 240 Hz sur deux disques).
    public static let commandCapacity = 1024
    /// Capacité de la file de retour des clips.
    public static let releaseCapacity = 64
    /// Taille maximale d'un bloc interne ; `render` découpe les demandes plus longues.
    public static let maximumBlockFrames = 512

    // Shared between threads (lock-free).
    private let commands = SPSCQueue<RenderCommand>(minimumCapacity: ScratchEngine.commandCapacity)
    private let releases = SPSCQueue<Unmanaged<AudioClip>>(minimumCapacity: ScratchEngine.releaseCapacity)
    private let snapshots: SnapshotBuffer<EngineSnapshot>
    private let controlRole = RoleGuard()
    private let audioRole = RoleGuard()

    // Audio-thread state (also touched by `pump` and `deinit`, never concurrently with `render`).
    private var deckA: DeckChannel
    private var deckB: DeckChannel
    private var mixer: MixerRenderer
    private var motorTimings = MotorTimings.defaults
    private var outputSampleRate: Double
    private var sampleTime: Int64 = 0
    private let scratch: RenderScratch

    /// - Parameter outputSampleRate: fréquence de sortie initiale (modifiable par
    ///   `EngineCommand.outputSampleRate`).
    public init(outputSampleRate: Double = 48_000) {
        let rate = outputSampleRate.isFinite && outputSampleRate > 0 ? outputSampleRate : 48_000
        self.outputSampleRate = rate
        self.deckA = DeckChannel(sampleRate: rate)
        self.deckB = DeckChannel(sampleRate: rate)
        self.mixer = MixerRenderer(outputSampleRate: rate)
        self.scratch = RenderScratch(capacity: ScratchEngine.maximumBlockFrames)
        self.snapshots = SnapshotBuffer(initialValue: EngineSnapshot(outputSampleRate: rate))
        assert(_isPOD(RenderCommand.self), "RenderCommand must stay trivial (real-time rule)")
        assert(_isPOD(EngineSnapshot.self), "EngineSnapshot must stay trivial (real-time rule)")
        // Warm-up: run the audio-side code paths once off the audio thread.
        pump()
    }

    deinit {
        while let command = commands.pop() { command.releaseUnsentClip() }
        deckA.clip?.release()
        deckB.clip?.release()
        while let clip = releases.pop() { clip.release() }
    }

    // MARK: Fil de contrôle

    @discardableResult
    public func send(_ command: EngineCommand) -> Bool {
        controlRole.enter("ScratchEngine.send called concurrently from two threads")
        defer { controlRole.exit() }
        let renderCommand = RenderCommand(command)
        if commands.push(renderCommand) { return true }
        renderCommand.releaseUnsentClip()
        return false
    }

    public func latestSnapshot() -> EngineSnapshot {
        controlRole.enter("ScratchEngine.latestSnapshot called concurrently from two threads")
        defer { controlRole.exit() }
        return snapshots.read()
    }

    @discardableResult
    public func drainReleasedClips() -> Int {
        controlRole.enter("ScratchEngine.drainReleasedClips called concurrently from two threads")
        defer { controlRole.exit() }
        var released = 0
        while let clip = releases.pop() {
            clip.release()
            released += 1
        }
        return released
    }

    public func pump() {
        audioRole.enter("ScratchEngine.pump called while the audio thread is rendering")
        defer { audioRole.exit() }
        applyPendingCommands()
        publishSnapshot()
    }

    // MARK: Fil audio

    /// Fil audio uniquement. Rend `frameCount` trames stéréo désentrelacées dans `left` et `right`
    /// (écrasement).
    ///
    /// Ordre : commandes en attente, puis blocs de `maximumBlockFrames` au plus (physique →
    /// lecture → mixage), puis publication d'un instantané. Temps réel : aucune allocation, aucun
    /// verrou, aucune libération d'objet.
    public func render(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        audioRole.enter("ScratchEngine.render called concurrently (two audio threads, or pump during render)")
        defer { audioRole.exit() }
        applyPendingCommands()
        var offset = 0
        while offset < frameCount {
            let count = min(ScratchEngine.maximumBlockFrames, frameCount - offset)
            renderBlock(frameCount: count, left: left + offset, right: right + offset)
            offset += count
        }
        sampleTime += Int64(max(0, frameCount))
        publishSnapshot()
    }

    // MARK: Interne

    private func renderBlock(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        deckA.render(frameCount: frameCount, scratch: scratch.a)
        deckB.render(frameCount: frameCount, scratch: scratch.b)
        mixer.mix(
            a: (UnsafePointer(scratch.a.left), UnsafePointer(scratch.a.right)),
            b: (UnsafePointer(scratch.b.left), UnsafePointer(scratch.b.right)),
            frameCount: frameCount,
            left: left,
            right: right
        )
    }

    private func applyPendingCommands() {
        // A load or unload returns at most one clip: never pop a command without room to return it.
        while releases.availableCapacity > 0, let command = commands.pop() {
            apply(command)
        }
    }

    private func apply(_ command: RenderCommand) {
        switch command {
        case let .load(deck, clip):
            withDeck(deck) { channel in
                if let previous = channel.replaceClip(with: clip) { _ = releases.push(previous) }
            }
        case let .unload(deck):
            withDeck(deck) { channel in
                if let previous = channel.replaceClip(with: nil) { _ = releases.push(previous) }
            }
        case let .motor(deck, on): withDeck(deck) { $0.physics.setMotor(on) }
        case let .speed(deck, speed): withDeck(deck) { $0.physics.setSpeed(speed) }
        case let .pitch(deck, value): withDeck(deck) { $0.physics.setPitch(value) }
        case let .resistance(deck, value): withDeck(deck) { $0.physics.setResistance(value) }
        case let .touchBegan(deck, angle, time): withDeck(deck) { $0.physics.touchBegan(angle: angle, time: time) }
        case let .touchMoved(deck, angle, time, predicted):
            withDeck(deck) { $0.physics.touchMoved(angle: angle, time: time, predicted: predicted) }
        case let .touchEnded(deck, time): withDeck(deck) { $0.physics.touchEnded(time: time) }
        case let .setCue(deck): withDeck(deck) { $0.physics.setCue() }
        case let .recallCue(deck): withDeck(deck) { $0.physics.recallCue() }
        case let .seek(deck, seconds): withDeck(deck) { $0.physics.seek(to: seconds) }
        case let .startDuration(value):
            guard value.isFinite else { return }
            motorTimings.startDuration = value
            applyMotorTimings()
        case let .brakeDuration(value):
            guard value.isFinite else { return }
            motorTimings.brakeDuration = value
            applyMotorTimings()
        case let .slipmatCatchUp(value):
            guard value.isFinite else { return }
            motorTimings.slipmatCatchUp = value
            applyMotorTimings()
        case let .crossfader(value): mixer.setCrossfader(value)
        case let .crossfaderCurve(value): mixer.setCrossfaderCurve(value)
        case let .hamster(on): mixer.setHamster(on)
        case let .lineFader(deck, value): mixer.setLineFader(deck, value)
        case let .momentaryCut(deck, open): mixer.setMomentaryCut(deck, open: open)
        case .stopAllMotors:
            deckA.physics.stopMotorImmediately()
            deckB.physics.stopMotorImmediately()
        case let .outputSampleRate(value):
            guard value.isFinite, value > 0 else { return }
            outputSampleRate = value
            deckA.setOutputSampleRate(value)
            deckB.setOutputSampleRate(value)
            mixer.setOutputSampleRate(value)
        }
    }

    private func applyMotorTimings() {
        motorTimings = motorTimings.clamped()
        deckA.physics.setMotorTimings(motorTimings)
        deckB.physics.setMotorTimings(motorTimings)
    }

    private func withDeck(_ deck: DeckID, _ body: (inout DeckChannel) -> Void) {
        switch deck {
        case .a: body(&deckA)
        case .b: body(&deckB)
        }
    }

    private func publishSnapshot() {
        snapshots.write(EngineSnapshot(
            decks: DeckPair(a: deckA.snapshot(peak: mixer.channelPeaks.a), b: deckB.snapshot(peak: mixer.channelPeaks.b)),
            mixer: MixerSnapshot(
                crossfader: mixer.crossfader,
                crossfaderCurve: mixer.crossfaderCurve,
                hamster: mixer.hamster,
                lineFaders: mixer.lineFaders,
                momentaryCuts: mixer.momentaryCuts,
                channelGains: mixer.channelGains,
                outputPeak: mixer.outputPeak,
                limiterReduction: mixer.limiterReduction
            ),
            motorTimings: motorTimings,
            outputSampleRate: outputSampleRate,
            sampleTime: sampleTime
        ))
    }
}

/// Une platine côté fil audio : clip (référence non gérée), physique et lecture.
struct DeckChannel {
    private(set) var clip: Unmanaged<AudioClip>?
    var physics: DeckPhysics
    var renderer: DeckRenderer

    init(sampleRate: Double) {
        physics = DeckPhysics(sampleRate: sampleRate)
        renderer = DeckRenderer(outputSampleRate: sampleRate)
    }

    /// Remplace le clip et revient à l'état initial (SF-03) ; renvoie l'ancien, à rendre au fil de
    /// contrôle par la file de retour.
    mutating func replaceClip(with newClip: Unmanaged<AudioClip>?) -> Unmanaged<AudioClip>? {
        let previous = clip
        clip = newClip
        let duration = newClip.map { $0._withUnsafeGuaranteedRef { $0.duration } } ?? 0
        physics.reset(duration: duration)
        renderer.reset()
        return previous
    }

    mutating func setOutputSampleRate(_ rate: Double) {
        physics.setSampleRate(rate)
        renderer.setOutputSampleRate(rate)
    }

    mutating func render(frameCount: Int, scratch: RenderScratch.Deck) {
        // A jump (CUE, needle drop) is applied between blocks: the voice fades the old position out.
        if let origin = physics.takeJumpOrigin() { renderer.beginJumpCrossfade(from: origin) }
        physics.process(frameCount: frameCount, positions: scratch.positions, rates: scratch.rates)
        if let clip {
            clip._withUnsafeGuaranteedRef { audioClip in
                renderer.render(clip: audioClip, positions: scratch.positions, rates: scratch.rates,
                                frameCount: frameCount, left: scratch.left, right: scratch.right)
            }
        } else {
            renderer.render(clip: nil, positions: scratch.positions, rates: scratch.rates,
                            frameCount: frameCount, left: scratch.left, right: scratch.right)
        }
    }

    func snapshot(peak: Double) -> DeckSnapshot {
        DeckSnapshot(
            clipID: clip.map { $0._withUnsafeGuaranteedRef { $0.id } },
            durationSeconds: physics.durationSeconds,
            positionSeconds: physics.positionSeconds,
            playbackRate: physics.playbackRate,
            discAngle: physics.discAngle,
            platterAngle: physics.platterAngle,
            stickerAngle: physics.stickerAngle,
            isHeld: physics.isHeld,
            motorOn: physics.motorOn,
            speed: physics.speed,
            pitch: physics.pitch,
            resistance: physics.resistance,
            cueSeconds: physics.cueSeconds,
            isAtEnd: physics.isAtEnd,
            isInLeadIn: physics.isInLeadIn,
            peakLevel: peak
        )
    }
}

/// Tampons de travail préalloués du rendu (un jeu par platine).
final class RenderScratch {
    struct Deck {
        let positions: UnsafeMutablePointer<Double>
        let rates: UnsafeMutablePointer<Double>
        let left: UnsafeMutablePointer<Float>
        let right: UnsafeMutablePointer<Float>
    }

    let capacity: Int
    let a: Deck
    let b: Deck

    init(capacity: Int) {
        self.capacity = capacity
        func make() -> Deck {
            let positions = UnsafeMutablePointer<Double>.allocate(capacity: capacity)
            positions.initialize(repeating: 0, count: capacity)
            let rates = UnsafeMutablePointer<Double>.allocate(capacity: capacity)
            rates.initialize(repeating: 0, count: capacity)
            let left = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
            left.initialize(repeating: 0, count: capacity)
            let right = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
            right.initialize(repeating: 0, count: capacity)
            return Deck(positions: positions, rates: rates, left: left, right: right)
        }
        a = make()
        b = make()
    }

    deinit {
        for deck in [a, b] {
            deck.positions.deallocate()
            deck.rates.deallocate()
            deck.left.deallocate()
            deck.right.deallocate()
        }
    }
}
