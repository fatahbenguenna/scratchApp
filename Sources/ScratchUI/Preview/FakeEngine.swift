import Foundation
import ScratchCore

/// Faux moteur des aperçus, des tests et du lancement tant que 6.1 n'est pas livrée (story 4.1 CA 1).
///
/// Conforme à `EngineControlling` comme le vrai moteur : les commandes sont mises en file et
/// appliquées par `pump()`, qui publie un instantané complet. Contrairement à `ScratchEngine.pump()`,
/// il fait avancer le temps d'après une horloge injectable. Cinématique simple, sans son ni physique
/// fine : rampes de démarrage et de freinage (SF-04, SF-05), feutrine du 1er ordre (SF-68), disque
/// qui suit le doigt, plateau qui tourne sous le disque retenu (6.9), tête bornée à [−2 s ; durée]
/// (RM-55), repère recalé après chaque saut (IC-09).
///
/// Fil de contrôle uniquement (non thread-safe).
public final class FakeEngine: EngineControlling {
    /// Pas de temps maximal d'un `pump()` : une image en retard ne fait pas sauter le disque.
    static let maximumStep = 0.1

    private let clock: () -> Double
    private var lastPumpTime: Double?
    private var pending: [EngineCommand] = []
    private var decks = DeckPair(repeating: FakeDeck())
    private var mixer = MixerSnapshot.initial
    private var timings = MotorTimings.defaults
    private var outputSampleRate = 48_000.0
    private var sampleTime: Int64 = 0
    private var releasedClips = 0
    private var published = EngineSnapshot.initial

    /// - Parameter clock: horloge monotone en secondes (par défaut, `ProcessInfo.systemUptime`).
    public init(clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }

    @discardableResult
    public func send(_ command: EngineCommand) -> Bool {
        guard pending.count < ScratchEngine.commandCapacity else { return false }
        pending.append(command)
        return true
    }

    public func latestSnapshot() -> EngineSnapshot { published }

    @discardableResult
    public func drainReleasedClips() -> Int {
        defer { releasedClips = 0 }
        return releasedClips
    }

    /// Applique les commandes en attente, avance du temps écoulé depuis l'appel précédent (borné à
    /// `maximumStep`), puis publie l'instantané.
    public func pump() {
        let now = clock()
        let step = lastPumpTime.map { min(max(now - $0, 0), Self.maximumStep) } ?? 0
        lastPumpTime = now
        // Nothing moved while the previous snapshot was idle (display loop asleep): no catch-up step.
        let wasIdle = published.isIdle
        let commands = pending
        pending.removeAll(keepingCapacity: true)
        commands.forEach(apply)
        if step > 0, !wasIdle {
            decks.a.advance(by: step, timings: timings)
            decks.b.advance(by: step, timings: timings)
            sampleTime += Int64((step * outputSampleRate).rounded())
        }
        published = EngineSnapshot(decks: decks.map(\.snapshot), mixer: mixer, motorTimings: timings,
                                   outputSampleRate: outputSampleRate, sampleTime: sampleTime)
    }

    private func apply(_ command: EngineCommand) {
        switch command {
        case let .load(deck, clip):
            if decks[deck].clip != nil { releasedClips += 1 }
            decks[deck].load(clip)
        case let .unload(deck):
            if decks[deck].clip != nil { releasedClips += 1 }
            decks[deck].load(nil)
        case let .motor(deck, on): decks[deck].motorOn = on
        case let .speed(deck, speed): decks[deck].speed = speed
        case let .pitch(deck, value):
            if value.isFinite { decks[deck].pitch = value.clamped(to: TurntableConstants.pitchRange, fallback: 0) }
        case let .resistance(deck, value):
            if value.isFinite { decks[deck].resistance = value.clamped(to: 0...1, fallback: 0.5) }
        case let .touchBegan(deck, angle, _): decks[deck].grab(at: angle)
        case let .touchMoved(deck, angle, _, _): if decks[deck].isHeld { decks[deck].fingerAngle = angle }
        case let .touchEnded(deck, _): decks[deck].isHeld = false
        case let .setCue(deck): if decks[deck].clip != nil { decks[deck].cue = max(0, decks[deck].position) }
        case let .recallCue(deck): decks[deck].jump(to: decks[deck].cue ?? 0)
        case let .seek(deck, seconds): if !decks[deck].isHeld, seconds.isFinite { decks[deck].jump(to: seconds) }
        case let .startDuration(value): timings.startDuration = value.isFinite ? value : timings.startDuration
        case let .brakeDuration(value): timings.brakeDuration = value.isFinite ? value : timings.brakeDuration
        case let .slipmatCatchUp(value): timings.slipmatCatchUp = value.isFinite ? value : timings.slipmatCatchUp
        case let .crossfader(value): mixer.crossfader = value.clamped(to: 0...1, fallback: mixer.crossfader)
        case let .crossfaderCurve(value):
            mixer.crossfaderCurve = value.clamped(to: 0...1, fallback: mixer.crossfaderCurve)
        case let .hamster(on): mixer.hamster = on
        case let .lineFader(deck, value): mixer.lineFaders[deck] = value.clamped(to: 0...1, fallback: 1)
        case let .momentaryCut(deck, open): mixer.momentaryCuts[deck] = open
        case .stopAllMotors:
            decks.a.stopImmediately()
            decks.b.stopImmediately()
        case let .outputSampleRate(value): if value.isFinite, value > 0 { outputSampleRate = value }
        }
        timings = timings.clamped()
    }
}

/// État d'une platine du faux moteur.
private struct FakeDeck {
    var clip: AudioClip?
    var motorOn = false
    var speed = TurntableSpeed.rpm33
    var pitch = 0.0
    var resistance = TurntableConstants.defaultResistance
    var cue: Double?
    var position = 0.0
    var platterAngle = 0.0
    var discAngle = 0.0
    var platterVelocity = 0.0
    var discVelocity = 0.0
    var isHeld = false
    var fingerAngle = 0.0
    var gripOffset = 0.0
    var isAtStop = false

    private static let twoPi = 2 * Double.pi
    private var duration: Double { clip?.duration ?? 0 }

    mutating func advance(by step: Double, timings: MotorTimings) {
        let nominal = TurntableConstants.referenceAngularVelocity * speed.nominalRate * (1 + pitch)
        let target = motorOn ? nominal : 0
        if platterVelocity < target {
            platterVelocity = min(target, platterVelocity + nominal / timings.startDuration * step)
        } else {
            platterVelocity = max(target, platterVelocity - nominal / timings.brakeDuration * step)
        }
        platterAngle += platterVelocity * step
        let previousDisc = discAngle
        if isHeld {
            discAngle = fingerAngle + gripOffset
            discVelocity = (discAngle - previousDisc) / step
        } else {
            let tau = timings.slipmatCatchUp / 3
            discVelocity += (platterVelocity - discVelocity) * (tau > 0 ? 1 - exp(-step / tau) : 1)
            // Snap below the idle threshold of `DeckSnapshot.isActive`: a resting disc reads exactly 0.
            if abs(discVelocity - platterVelocity) < 1e-3 * TurntableConstants.referenceAngularVelocity {
                discVelocity = platterVelocity
            }
            discAngle += discVelocity * step
        }
        guard clip != nil else { return }
        let free = position + (discAngle - previousDisc) / Self.twoPi * TurntableConstants.secondsPerRevolution
        position = min(max(free, -TurntableConstants.leadInSeconds), duration)
        if position != free {
            isAtStop = true
        } else if isAtStop {
            isAtStop = false
            realign()
        }
    }

    mutating func load(_ newClip: AudioClip?) {
        clip = newClip
        motorOn = false
        cue = nil
        isHeld = false
        isAtStop = false
        position = 0
        realign()
    }

    mutating func grab(at angle: Double) {
        guard !isHeld else { return }
        isHeld = true
        fingerAngle = angle
        gripOffset = discAngle - angle
    }

    mutating func jump(to seconds: Double) {
        guard clip != nil else { return }
        position = min(max(seconds, -TurntableConstants.leadInSeconds), duration)
        realign()
    }

    mutating func stopImmediately() {
        motorOn = false
        platterVelocity = 0
        if !isHeld { discVelocity = 0 }
    }

    /// IC-09 : ramène l'angle du disque à 2π × position / 1,8 (mod 2π) par la plus petite correction ;
    /// un disque tenu reste sous le doigt.
    private mutating func realign() {
        let expected = Self.twoPi * position / TurntableConstants.secondsPerRevolution
        var correction = (expected - discAngle).truncatingRemainder(dividingBy: Self.twoPi)
        if correction > .pi { correction -= Self.twoPi } else if correction < -.pi { correction += Self.twoPi }
        discAngle += correction
        gripOffset += correction
    }

    var snapshot: DeckSnapshot {
        let rate = discVelocity / TurntableConstants.referenceAngularVelocity
        return DeckSnapshot(
            clipID: clip?.id,
            durationSeconds: duration,
            positionSeconds: position,
            playbackRate: min(max(rate, -TurntableConstants.maximumPlaybackRate), TurntableConstants.maximumPlaybackRate),
            discAngle: discAngle,
            platterAngle: platterAngle,
            stickerAngle: discAngle - Self.twoPi * (cue ?? 0) / TurntableConstants.secondsPerRevolution,
            isHeld: isHeld,
            motorOn: motorOn,
            speed: speed,
            pitch: pitch,
            resistance: resistance,
            cueSeconds: cue,
            isAtEnd: clip != nil && position >= duration,
            isInLeadIn: position < 0
        )
    }
}
