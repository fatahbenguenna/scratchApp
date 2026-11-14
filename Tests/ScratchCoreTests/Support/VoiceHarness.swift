import Foundation
@testable import ScratchCore

/// Banc d'essai de bout en bout d'une platine : `DeckChannel` réel (physique, saut, voix), clip
/// synthétique, gestes horodatés sur l'horloge audio, touches livrées par lots au début de chaque
/// bloc (story 1.3 ; réutilisable par 1.5).
final class VoiceHarness {
    struct Output {
        var left: [Float] = []
        var right: [Float] = []
        var positions: [Double] = []
        var rates: [Double] = []

        mutating func append(_ other: Output) {
            left += other.left
            right += other.right
            positions += other.positions
            rates += other.rates
        }
    }

    private enum Touch {
        case began(Double)
        case moved(Double)
        case ended
    }

    /// Rejeu du doigt à retard constant (14 ms) et cadence 1 : cinématique exacte.
    static let exactFinger: FingerTrajectory.Configuration = {
        var configuration = FingerTrajectory.Configuration()
        configuration.rateGain = 0
        configuration.delaySmoothing = 0
        return configuration
    }()

    let sampleRate: Double
    private(set) var channel: DeckChannel
    private let scratch = RenderScratch(capacity: ScratchEngine.maximumBlockFrames)
    private(set) var sampleCount = 0
    private var pending: [(time: Double, touch: Touch)] = []
    /// Livraison des touches : à chaque bloc (0) ou à la cadence d'affichage donnée (Hz).
    var displayRate: Double = 0
    private var nextDisplayTime = 0.0

    init(clip: AudioClip?, sampleRate: Double = 48_000,
         finger: FingerTrajectory.Configuration = VoiceHarness.exactFinger) {
        self.sampleRate = sampleRate
        channel = DeckChannel(sampleRate: sampleRate)
        channel.physics = DeckPhysics(sampleRate: sampleRate, fingerConfiguration: finger)
        _ = channel.replaceClip(with: clip.map { Unmanaged.passRetained($0) }, view: clip.map(ClipView.init))
    }

    deinit {
        channel.releaseAll()
    }

    var time: Double { Double(sampleCount) / sampleRate }
    var physics: DeckPhysics {
        get { channel.physics }
        set { channel.physics = newValue }
    }

    /// Programme un geste : contact à `start`, touches à `touchRate` jusqu'à `end`, relâchement à
    /// `end` si demandé ; `path(t)` est l'angle cumulé du doigt (rad) à l'instant `t`.
    func schedule(from start: Double, to end: Double, touchRate: Double = 240, release: Bool = true,
                  path: (Double) -> Double) {
        pending.append((start, .began(path(start))))
        var index = 1
        while true {
            let t = start + Double(index) / touchRate
            if t > end + 1e-12 { break }
            pending.append((t, .moved(path(t))))
            index += 1
        }
        if end - (start + Double(index - 1) / touchRate) > 1e-9 { pending.append((end, .moved(path(end)))) }
        if release { pending.append((end, .ended)) }
    }

    private func deliverDueTouches() {
        if displayRate > 0 {
            guard time >= nextDisplayTime else { return }
            nextDisplayTime += 1 / displayRate
        }
        var delivered = 0
        for event in pending {
            guard event.time <= time + 1e-12 else { break }
            switch event.touch {
            case let .began(angle): channel.physics.touchBegan(angle: angle, time: event.time)
            case let .moved(angle): channel.physics.touchMoved(angle: angle, time: event.time, predicted: false)
            case .ended: channel.physics.touchEnded(time: event.time)
            }
            delivered += 1
        }
        pending.removeFirst(delivered)
    }

    @discardableResult
    func run(samples: Int, block: Int = 256) -> Output {
        var output = Output()
        output.left.reserveCapacity(samples)
        var remaining = samples
        let deck = scratch.a
        while remaining > 0 {
            let count = min(block, remaining, scratch.capacity)
            deliverDueTouches()
            channel.render(frameCount: count, scratch: deck, outgoing: scratch.outgoing)
            output.left.append(contentsOf: UnsafeBufferPointer(start: deck.left, count: count))
            output.right.append(contentsOf: UnsafeBufferPointer(start: deck.right, count: count))
            output.positions.append(contentsOf: UnsafeBufferPointer(start: deck.positions, count: count))
            output.rates.append(contentsOf: UnsafeBufferPointer(start: deck.rates, count: count))
            sampleCount += count
            remaining -= count
        }
        return output
    }

    @discardableResult
    func run(seconds: Double, block: Int = 256) -> Output {
        run(samples: Int((seconds * sampleRate).rounded()), block: block)
    }
}

/// Clips synthétiques des tests de la voix.
enum TestClips {
    /// Sinusoïde mono de `frequency` Hz, amplitude `amplitude`, phase initiale `phase` (rad).
    static func sine(frequency: Double, seconds: Double, sampleRate: Double = 48_000,
                     amplitude: Double = 1, phase: Double = 0) -> AudioClip {
        let count = Int((seconds * sampleRate).rounded())
        let samples = (0..<count).map { Float(amplitude * sin(2 * Double.pi * frequency * Double($0) / sampleRate + phase)) }
        return AudioClip(title: "sine", sampleRate: sampleRate, mono: samples)
    }

    /// Rampe codant la position : échantillon i = 0,5 × i / count (décodage exact par Hermite).
    static func positionRamp(seconds: Double, sampleRate: Double = 48_000) -> AudioClip {
        let count = Int((seconds * sampleRate).rounded())
        let samples = (0..<count).map { Float(0.5 * Double($0) / Double(count)) }
        return AudioClip(title: "ramp", sampleRate: sampleRate, mono: samples)
    }

    /// Bruit déterministe (LCG), gauche et droite différents.
    static func noise(frames: Int, sampleRate: Double = 48_000) -> AudioClip {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Float {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Double(state >> 11) / Double(1 << 53) * 1.6 - 0.8)
        }
        var left = [Float]()
        var right = [Float]()
        for _ in 0..<frames {
            left.append(next())
            right.append(next())
        }
        return AudioClip(title: "noise", sampleRate: sampleRate, left: left, right: right)
    }
}

/// Rendu direct d'une voix sur une trajectoire synthétique.
struct VoiceRig {
    var renderer: DeckRenderer
    let clip: AudioClip?

    init(clip: AudioClip?, outputSampleRate: Double = 48_000) {
        self.clip = clip
        renderer = DeckRenderer(outputSampleRate: outputSampleRate)
    }

    /// Rend la trajectoire par blocs de `block` trames ; renvoie (gauche, droite).
    mutating func render(positions: [Double], rates: [Double], block: Int = 512) -> (left: [Float], right: [Float]) {
        precondition(positions.count == rates.count)
        var left = [Float](repeating: .nan, count: positions.count)
        var right = [Float](repeating: .nan, count: positions.count)
        var start = 0
        while start < positions.count {
            let count = min(block, positions.count - start)
            positions.withUnsafeBufferPointer { p in
                rates.withUnsafeBufferPointer { r in
                    left.withUnsafeMutableBufferPointer { l in
                        right.withUnsafeMutableBufferPointer { rr in
                            renderer.render(clip: clip, positions: p.baseAddress! + start, rates: r.baseAddress! + start,
                                            frameCount: count, left: l.baseAddress! + start, right: rr.baseAddress! + start)
                        }
                    }
                }
            }
            start += count
        }
        return (left, right)
    }

    /// Trajectoire à vitesse constante `rate` depuis `start` (s), sortie à `outputSampleRate`.
    static func constantRate(_ rate: Double, from start: Double, samples: Int,
                             outputSampleRate: Double = 48_000) -> (positions: [Double], rates: [Double]) {
        ((0..<samples).map { start + rate * Double($0 + 1) / outputSampleRate },
         [Double](repeating: rate, count: samples))
    }
}
