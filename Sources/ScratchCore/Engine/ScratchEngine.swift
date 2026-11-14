import Foundation

/// Moteur audio de ScratchApp : deux platines et une table de mixage (architecture §3, §5.1 et §6.2 ;
/// story 1.5).
///
/// Fils d'exécution :
/// - **fil de contrôle** (fil principal dans l'app) : `send`, `latestSnapshot`, `drainReleasedClips`,
///   `pump` (hôte arrêté seulement) ;
/// - **fil audio** : `render`, appelé par l'hôte (`AudioEngineHost`) ou par un rendu hors ligne.
///
/// Communication : file SPSC de commandes (contrôle → audio), triple tampon d'instantanés
/// (audio → contrôle), file SPSC de retour des clips remplacés (audio → contrôle). `render` ne
/// prend aucun verrou, n'alloue rien, ne libère aucun objet et ne touche jamais un `AudioClip` : il
/// lit ses échantillons par une `ClipView` construite sur le fil de contrôle (aucun comptage de
/// références sur le fil audio).
///
/// Rendu (§6.2) : commandes en attente, puis blocs de 512 trames au plus — physique (1.1), voix
/// (1.3), table de mixage (1.4) — puis un instantané complet par appel, dont les mesures (crêtes,
/// réduction du limiteur) couvrent **tous** les blocs de l'appel.
///
/// Remplacement d'un son en lecture (SF-15) : l'ancien clip reste sur le fil audio le temps d'un
/// fondu de sortie de 5 ms, à la position et à la vitesse qu'il avait, puis rejoint la file de
/// retour (aucune coupure nette).
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
    private var meters = RenderMeters()
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
        warmUp()
        pump()
    }

    deinit {
        while let command = commands.pop() { command.releaseUnsentClip() }
        deckA.releaseAll()
        deckB.releaseAll()
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

    /// Applique les commandes et publie un instantané sans rendre d'audio ni avancer le temps
    /// (hôte arrêté). Les mesures publiées sont nulles : rien n'est rendu.
    public func pump() {
        audioRole.enter("ScratchEngine.pump called while the audio thread is rendering")
        defer { audioRole.exit() }
        applyPendingCommands()
        // Nothing is rendered: a replaced clip has no sound to fade out and goes back at once.
        deckA.abandonFadeOut()
        deckB.abandonFadeOut()
        returnFadedClips()
        meters = RenderMeters()
        publishSnapshot()
    }

    // MARK: Fil audio

    /// Fil audio uniquement. Rend `frameCount` trames stéréo désentrelacées dans `left` et `right`
    /// (écrasement).
    ///
    /// Ordre : commandes en attente, puis blocs de `maximumBlockFrames` au plus (physique →
    /// lecture → mixage), puis publication d'un instantané. Temps réel : aucune allocation, aucun
    /// verrou, aucune libération d'objet, aucun comptage de références.
    public func render(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        audioRole.enter("ScratchEngine.render called concurrently (two audio threads, or pump during render)")
        defer { audioRole.exit() }
        applyPendingCommands()
        meters = RenderMeters()
        var offset = 0
        while offset < frameCount {
            let count = min(ScratchEngine.maximumBlockFrames, frameCount - offset)
            renderBlock(frameCount: count, left: left + offset, right: right + offset)
            meters.accumulate(mixer)
            offset += count
        }
        returnFadedClips()
        sampleTime += Int64(max(0, frameCount))
        publishSnapshot()
    }

    // MARK: Interne

    private func renderBlock(frameCount: Int, left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        deckA.render(frameCount: frameCount, scratch: scratch.a, outgoing: scratch.outgoing)
        deckB.render(frameCount: frameCount, scratch: scratch.b, outgoing: scratch.outgoing)
        mixer.mix(
            a: (UnsafePointer(scratch.a.left), UnsafePointer(scratch.a.right)),
            b: (UnsafePointer(scratch.b.left), UnsafePointer(scratch.b.right)),
            frameCount: frameCount,
            left: left,
            right: right
        )
    }

    /// Rend à la file de retour les clips dont le fondu de sortie est fini, s'il y a de la place.
    private func returnFadedClips() {
        if releases.availableCapacity > 0, let clip = deckA.takeFadedOutgoing() { _ = releases.push(clip) }
        if releases.availableCapacity > 0, let clip = deckB.takeFadedOutgoing() { _ = releases.push(clip) }
    }

    private func applyPendingCommands() {
        // A load or unload returns at most one clip: never pop a command without room to return it.
        while releases.availableCapacity > 0, let command = commands.pop() {
            apply(command)
        }
    }

    private func apply(_ command: RenderCommand) {
        switch command {
        case let .load(deck, clip, view):
            withDeck(deck) { channel in
                if let previous = channel.replaceClip(with: clip, view: view) { _ = releases.push(previous) }
            }
        case let .unload(deck):
            withDeck(deck) { channel in
                if let previous = channel.replaceClip(with: nil, view: nil) { _ = releases.push(previous) }
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

    /// Échauffement (architecture §6.1 règle 7) : rend un bloc sur des copies des composants, hors du
    /// fil audio, pour instancier les métadonnées et parcourir le code du rendu avant le premier
    /// appel réel. L'état du moteur n'est pas modifié.
    private func warmUp() {
        var channel = deckA
        var mixerCopy = mixer
        channel.render(frameCount: ScratchEngine.maximumBlockFrames, scratch: scratch.a, outgoing: scratch.outgoing)
        mixerCopy.mix(
            a: (UnsafePointer(scratch.a.left), UnsafePointer(scratch.a.right)),
            b: (UnsafePointer(scratch.a.left), UnsafePointer(scratch.a.right)),
            frameCount: ScratchEngine.maximumBlockFrames,
            left: scratch.b.left,
            right: scratch.b.right
        )
    }

    private func publishSnapshot() {
        snapshots.write(EngineSnapshot(
            decks: DeckPair(a: deckA.snapshot(peak: meters.channelPeaks.a), b: deckB.snapshot(peak: meters.channelPeaks.b)),
            mixer: MixerSnapshot(
                crossfader: mixer.crossfader,
                crossfaderCurve: mixer.crossfaderCurve,
                hamster: mixer.hamster,
                lineFaders: mixer.lineFaders,
                momentaryCuts: mixer.momentaryCuts,
                channelGains: mixer.channelGains,
                outputPeak: meters.outputPeak,
                limiterReduction: meters.limiterReduction
            ),
            motorTimings: motorTimings,
            outputSampleRate: outputSampleRate,
            sampleTime: sampleTime
        ))
    }
}

/// Mesures d'un appel de rendu : maximum sur tous ses blocs (un tampon d'hôte de plus de 512 trames
/// est rendu en plusieurs blocs).
struct RenderMeters {
    var channelPeaks = DeckPair<Double>(repeating: 0)
    var outputPeak: Double = 0
    var limiterReduction: Double = 0

    mutating func accumulate(_ mixer: MixerRenderer) {
        channelPeaks = DeckPair(a: max(channelPeaks.a, mixer.channelPeaks.a), b: max(channelPeaks.b, mixer.channelPeaks.b))
        outputPeak = max(outputPeak, mixer.outputPeak)
        limiterReduction = max(limiterReduction, mixer.limiterReduction)
    }
}

/// Une platine côté fil audio : clip (référence non gérée et vue), physique, voix, et fondu de sortie
/// du clip remplacé.
struct DeckChannel {
    private(set) var clip: Unmanaged<AudioClip>?
    private(set) var view: ClipView?
    var physics: DeckPhysics
    var renderer: DeckRenderer

    // Clip being faded out after a replacement (kept on the audio thread until the fade ends).
    private var outgoing: Unmanaged<AudioClip>?
    private var outgoingView: ClipView?
    private var outgoingRenderer: DeckRenderer
    private var outgoingPosition = 0.0
    private var outgoingRate = 0.0
    private var outgoingRemaining = 0
    private var outgoingLength = 1

    init(sampleRate: Double) {
        physics = DeckPhysics(sampleRate: sampleRate)
        renderer = DeckRenderer(outputSampleRate: sampleRate)
        outgoingRenderer = renderer
        updateFadeLength(sampleRate)
    }

    /// Un clip remplacé est encore en cours de fondu de sortie (diagnostic, tests).
    var isFadingOut: Bool { outgoing != nil && outgoingRemaining > 0 }

    /// Remplace le clip et revient à l'état initial (SF-03). Le clip remplacé reste en fondu de sortie
    /// s'il était audible ; renvoie le clip à rendre **tout de suite** par la file de retour (au plus
    /// un : celui d'un remplacement précédent encore présent).
    mutating func replaceClip(with newClip: Unmanaged<AudioClip>?, view newView: ClipView?) -> Unmanaged<AudioClip>? {
        let immediate = outgoing
        outgoing = clip
        outgoingView = view
        outgoingRenderer = renderer
        outgoingPosition = physics.positionSeconds
        outgoingRate = physics.playbackRate
        outgoingRemaining = clip != nil && renderer.isAudible ? outgoingLength : 0
        clip = newClip
        view = newView
        physics.reset(duration: newView?.duration ?? 0)
        renderer.reset()
        return immediate
    }

    /// Hôte arrêté (`pump`) : le fondu de sortie ne peut pas avancer ; le clip est rendu tout de suite.
    mutating func abandonFadeOut() { outgoingRemaining = 0 }

    /// Clip remplacé dont le fondu est fini, à rendre par la file de retour.
    mutating func takeFadedOutgoing() -> Unmanaged<AudioClip>? {
        guard let done = outgoing, outgoingRemaining == 0 else { return nil }
        outgoing = nil
        outgoingView = nil
        return done
    }

    /// Fil de contrôle (`deinit` du moteur) : rend les +1 du clip courant et du clip en fondu.
    mutating func releaseAll() {
        clip?.release()
        outgoing?.release()
        clip = nil
        outgoing = nil
    }

    mutating func setOutputSampleRate(_ rate: Double) {
        physics.setSampleRate(rate)
        renderer.setOutputSampleRate(rate)
        outgoingRenderer.setOutputSampleRate(rate)
        updateFadeLength(rate)
    }

    private mutating func updateFadeLength(_ rate: Double) {
        outgoingLength = max(1, Int((TurntableConstants.jumpFadeDuration * rate).rounded()))
        outgoingRemaining = min(outgoingRemaining, outgoingLength)
    }

    /// Fil audio uniquement. Physique, saut, voix, puis fondu de sortie du clip remplacé, ajouté à la
    /// voix dans `scratch.left/right`.
    mutating func render(frameCount: Int, scratch: RenderScratch.Deck, outgoing work: RenderScratch.Deck) {
        // A jump (CUE, needle drop) is applied between blocks: the voice fades the old position out.
        if let origin = physics.takeJumpOrigin() { renderer.beginJumpCrossfade(from: origin) }
        physics.process(frameCount: frameCount, positions: scratch.positions, rates: scratch.rates)
        renderer.render(clip: view, positions: scratch.positions, rates: scratch.rates,
                        frameCount: frameCount, left: scratch.left, right: scratch.right)
        guard outgoingRemaining > 0, let outgoingView else { return }
        // The replaced sound carries on at its last speed while it fades out (raised cosine).
        let dt = renderer.outputSampleRate > 0 ? 1 / renderer.outputSampleRate : 0
        let upper = outgoingView.duration
        let count = min(frameCount, outgoingRemaining)
        for index in 0..<count {
            outgoingPosition = min(upper, max(-TurntableConstants.leadInSeconds, outgoingPosition + outgoingRate * dt))
            work.positions[index] = outgoingPosition
            work.rates[index] = outgoingRate
        }
        outgoingRenderer.render(clip: outgoingView, positions: work.positions, rates: work.rates,
                                frameCount: count, left: work.left, right: work.right)
        for index in 0..<count {
            let progress = Double(outgoingLength - outgoingRemaining + index + 1) / Double(outgoingLength)
            let gain = Float(0.5 + 0.5 * cos(Double.pi * progress))
            scratch.left[index] += work.left[index] * gain
            scratch.right[index] += work.right[index] * gain
        }
        outgoingRemaining -= count
    }

    func snapshot(peak: Double) -> DeckSnapshot {
        DeckSnapshot(
            clipID: view?.id,
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

/// Tampons de travail préalloués du rendu : un jeu par platine et un jeu pour le fondu de sortie des
/// clips remplacés (partagé, utilisé une platine après l'autre).
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
    let outgoing: Deck

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
        outgoing = make()
    }

    deinit {
        for deck in [a, b, outgoing] {
            deck.positions.deallocate()
            deck.rates.deallocate()
            deck.left.deallocate()
            deck.right.deallocate()
        }
    }
}
