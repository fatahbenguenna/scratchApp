/// Synthèse procédurale du son de démonstration (SF-76, D-20 ; story 3.3).
///
/// Déroulé (8 s à 48 kHz, stéréo) :
///
/// | Plage | Contenu |
/// |---|---|
/// | 0,00–0,80 s | « Stab » en la majeur : 4 notes de 5 partiels chacune plus une sous-basse, tous en phase à la fin de l'attaque (0,5 ms), décroissance exponentielle plus rapide pour les partiels aigus |
/// | 0,45–4,00 s | Voix « ahh » à 140 Hz : glissando d'entrée, vibrato de 5,5 Hz, trois formants de [a] (750, 1 200, 2 500 Hz) |
/// | 4,00–4,80 s | Second stab, en ré majeur |
/// | 4,45–7,60 s | Voix « ahh » à 165 Hz, plus courte, puis silence jusqu'au fondu final |
///
/// La voix démarre pendant la queue du stab : la zone 0–4 s, utilisée par le self-test (2.4), ne
/// contient aucun silence. Chaque voix est doublée : une version par canal, à vibratos décalés d'un
/// quart de période, mélangées à 70/30. Les notes des stabs sont légèrement panoramiquées. Les deux
/// canaux ne sont jamais en opposition de phase : la somme mono reste propre.
///
/// **Déterminisme.** Seules les quatre opérations IEEE 754 et l'arrondi entier sont utilisés :
/// oscillateurs récursifs, polynômes de Taylor (`DemoMath`), filtres résonants à deux pôles,
/// générateur congruentiel à graine fixe. Aucune fonction de la libm, aucun hasard : deux
/// générations donnent les mêmes échantillons bit à bit, sous Linux comme sur les plateformes Apple.
enum DemoSynthesizer {
    /// Crête visée après normalisation : 0,89, juste sous −1 dBFS (0,891).
    static let targetPeak: Float = 0.89

    /// Remplit les deux canaux (déjà à zéro) avec le son complet, normalisé à `targetPeak`.
    static func render(left: UnsafeMutableBufferPointer<Float>, right: UnsafeMutableBufferPointer<Float>,
                       sampleRate: Double) {
        precondition(left.count == right.count, "DemoSynthesizer: channel length mismatch")
        let output = StereoBuffer(left: left, right: right, sampleRate: sampleRate)

        Stab(rootFrequency: 220, startTime: 0, sampleRate: sampleRate).render(into: output)
        renderVoicePair(baseFrequency: 140, start: 0.45, end: 4.0, into: output)
        Stab(rootFrequency: 293.664_767_9, startTime: 4.0, sampleRate: sampleRate).render(into: output)
        renderVoicePair(baseFrequency: 165, start: 4.45, end: 7.6, into: output)

        output.fadeOut(duration: 0.02)
        output.normalize(peak: targetPeak)
    }

    private static func renderVoicePair(baseFrequency: Double, start: Double, end: Double, into output: StereoBuffer) {
        for (index, vibratoPhase) in [0.0, 0.25].enumerated() {
            var voice = Voice(baseFrequency: baseFrequency, start: start, end: end, vibratoPhase: vibratoPhase,
                              noiseSeed: UInt32(0x5EED_0000 + index), sampleRate: output.sampleRate)
            let own: Float = 0.7, other: Float = 0.3
            voice.render(into: output, leftGain: index == 0 ? own : other, rightGain: index == 0 ? other : own)
        }
    }
}

// MARK: - Output

/// Les deux canaux du clip, écrits sur place (aucun tableau intermédiaire de 8 s).
struct StereoBuffer {
    let left: UnsafeMutableBufferPointer<Float>
    let right: UnsafeMutableBufferPointer<Float>
    let sampleRate: Double

    var frameCount: Int { left.count }

    func frame(at time: Double) -> Int {
        min(max(Int((time * sampleRate).rounded()), 0), frameCount)
    }

    /// Fondu de fin : le dernier échantillon vaut exactement zéro (sillon fermé, RM-55).
    func fadeOut(duration: Double) {
        let length = min(frame(at: duration), frameCount)
        guard length > 1 else { return }
        for offset in 0 ..< length {
            let index = frameCount - length + offset
            let gain = Float(1 - DemoMath.smoothstep(Double(offset) / Double(length - 1)))
            left[index] *= gain
            right[index] *= gain
        }
    }

    /// Applique un gain unique pour que la crête des deux canaux vaille `peak` (pas d'écrêtage).
    func normalize(peak: Float) {
        var maximum: Float = 0
        for index in 0 ..< frameCount {
            maximum = max(maximum, left[index].magnitude, right[index].magnitude)
        }
        guard maximum > 0 else { return }
        let gain = peak / maximum
        for index in 0 ..< frameCount {
            left[index] *= gain
            right[index] *= gain
        }
    }
}

// MARK: - Stab

/// Accord majeur bref : chaque note a 5 partiels d'amplitude 1/k, phasés pour être tous à leur maximum
/// à la fin de l'attaque (0,5 ms) : la crête du stab est atteinte à cet instant, puis le son s'éteint
/// de façon exponentielle (aucun réalignement ultérieur ne la dépasse).
private struct Stab {
    private var oscillators: [DampedOscillator] = []
    private var leftGains: [Double] = []
    private var rightGains: [Double] = []
    private let startFrame: Int
    private let attackFrames: Int
    private let lengthFrames: Int
    private let fadeFrames: Int

    init(rootFrequency: Double, startTime: Double, sampleRate: Double) {
        startFrame = Int((startTime * sampleRate).rounded())
        attackFrames = Int((Self.attackTime * sampleRate).rounded())
        lengthFrames = Int((0.8 * sampleRate).rounded())
        fadeFrames = Int((0.1 * sampleRate).rounded())
        // Major triad, octave, and pans (−1 left … +1 right), equal-tempered ratios.
        let notes: [(ratio: Double, pan: Double, level: Double)] = [
            (1, 0, 1), (1.259_921_049_9, -0.35, 0.8), (1.498_307_076_9, 0.35, 0.8), (2, 0, 0.6),
        ]
        for note in notes {
            for harmonic in 1 ... 5 {
                let k = Double(harmonic)
                add(frequency: rootFrequency * note.ratio * k, decayTime: 0.16 / (1 + 0.6 * (k - 1)),
                    amplitude: note.level / k, pan: note.pan, sampleRate: sampleRate)
            }
        }
        add(frequency: rootFrequency / 2, decayTime: 0.2, amplitude: 0.9, pan: 0, sampleRate: sampleRate)
    }

    private static let attackTime = 0.000_5

    private mutating func add(frequency: Double, decayTime: Double, amplitude: Double, pan: Double,
                              sampleRate: Double) {
        // Phase chosen so that every partial reaches its maximum at the end of the attack.
        let alignedPhase = -frequency * Double(attackFrames) / sampleRate
        oscillators.append(DampedOscillator(frequency: frequency, decayTime: decayTime, amplitude: amplitude,
                                            sampleRate: sampleRate, phase: alignedPhase))
        leftGains.append(0.5 * (1 - pan))
        rightGains.append(0.5 * (1 + pan))
    }

    func render(into output: StereoBuffer) {
        var oscillators = self.oscillators
        let end = min(startFrame + lengthFrames, output.frameCount)
        guard startFrame < end else { return }
        for index in startFrame ..< end {
            let offset = index - startFrame
            var envelope = 1.0
            if offset < attackFrames {
                envelope = DemoMath.smoothstep(Double(offset) / Double(attackFrames))
            } else if offset >= lengthFrames - fadeFrames {
                envelope = 1 - DemoMath.smoothstep(Double(offset - (lengthFrames - fadeFrames)) / Double(fadeFrames))
            }
            var sumLeft = 0.0, sumRight = 0.0
            for j in 0 ..< oscillators.count {
                let value = oscillators[j].next()
                sumLeft += value * leftGains[j]
                sumRight += value * rightGains[j]
            }
            output.left[index] += Float(sumLeft * envelope)
            output.right[index] += Float(sumRight * envelope)
        }
    }
}

// MARK: - Voice

/// Voix « ahh » : source glottique (dent de scie à bande limitée, PolyBLEP, et souffle léger) filtrée
/// par trois résonateurs en cascade aux formants de [a], avec glissando d'entrée et vibrato.
private struct Voice {
    private let startFrame: Int
    private let endFrame: Int
    private let attackFrames: Int
    private let releaseFrames: Int
    private let glideFrames: Int
    private let vibratoDelayFrames: Int
    private let vibratoRampFrames: Int
    private let baseIncrement: Double
    private var phase = 0.0
    private var vibrato: DampedOscillator
    private var formants: [Resonator]
    private var noise: UInt32

    // Voice character.
    private static let glideDepth = 0.06          // starts 6 % below the target pitch
    private static let vibratoDepth = 0.012       // ±1.2 % (about ±21 cents)
    private static let breathLevel = 0.06
    private static let level = 0.55

    init(baseFrequency: Double, start: Double, end: Double, vibratoPhase: Double, noiseSeed: UInt32,
         sampleRate: Double) {
        startFrame = Int((start * sampleRate).rounded())
        endFrame = Int((end * sampleRate).rounded())
        attackFrames = Int((0.06 * sampleRate).rounded())
        releaseFrames = Int((0.15 * sampleRate).rounded())
        glideFrames = Int((0.12 * sampleRate).rounded())
        vibratoDelayFrames = Int((0.3 * sampleRate).rounded())
        vibratoRampFrames = Int((0.4 * sampleRate).rounded())
        baseIncrement = baseFrequency / sampleRate
        vibrato = DampedOscillator(frequency: 5.5, decayTime: .infinity, amplitude: 1, sampleRate: sampleRate,
                                   phase: vibratoPhase)
        formants = [
            Resonator(frequency: 750, bandwidth: 90, sampleRate: sampleRate),
            Resonator(frequency: 1200, bandwidth: 110, sampleRate: sampleRate),
            Resonator(frequency: 2500, bandwidth: 160, sampleRate: sampleRate),
        ]
        noise = noiseSeed
    }

    mutating func render(into output: StereoBuffer, leftGain: Float, rightGain: Float) {
        let end = min(endFrame, output.frameCount)
        guard startFrame < end else { return }
        let length = end - startFrame
        for index in startFrame ..< end {
            let offset = index - startFrame
            // Pitch: entry glide, then delayed vibrato.
            let glide = offset < glideFrames
                ? 1 - Self.glideDepth * (1 - DemoMath.smoothstep(Double(offset) / Double(glideFrames)))
                : 1
            let lfo = vibrato.next()
            var depth = 0.0
            if offset >= vibratoDelayFrames {
                depth = Self.vibratoDepth
                    * DemoMath.smoothstep(Double(offset - vibratoDelayFrames) / Double(vibratoRampFrames))
            }
            let increment = baseIncrement * glide * (1 + depth * lfo)

            // Source: band-limited sawtooth plus a little breath noise.
            var source = 2 * phase - 1 - DemoMath.polyBLEP(phase: phase, increment: increment)
            noise = noise &* 1_664_525 &+ 1_013_904_223
            source += Self.breathLevel * (Double(noise >> 8) / 8_388_608 - 1)
            phase += increment
            if phase >= 1 { phase -= 1 }

            var sample = source
            for j in 0 ..< formants.count { sample = formants[j].process(sample) }

            var envelope = 1.0
            if offset < attackFrames {
                envelope = DemoMath.smoothstep(Double(offset) / Double(attackFrames))
            } else if offset >= length - releaseFrames {
                envelope = 1 - DemoMath.smoothstep(Double(offset - (length - releaseFrames)) / Double(releaseFrames))
            }
            let value = Float(sample * envelope * Self.level)
            output.left[index] += value * leftGain
            output.right[index] += value * rightGain
        }
    }
}

// MARK: - Building blocks

/// Sinusoïde récursive amortie : z ← z · r·e^{iω} (quatre produits et deux sommes par échantillon).
struct DampedOscillator {
    private var real: Double
    private var imaginary: Double
    private let c: Double
    private let s: Double

    /// - Parameters:
    ///   - decayTime: constante de temps τ de la décroissance, en secondes (`.infinity` : aucune).
    ///   - phase: phase initiale en fraction de période (0 : cosinus).
    init(frequency: Double, decayTime: Double, amplitude: Double, sampleRate: Double, phase: Double = 0) {
        let omega = 2 * DemoMath.pi * frequency / sampleRate
        let radius = decayTime.isFinite ? DemoMath.exponential(-1 / (decayTime * sampleRate)) : 1
        c = radius * DemoMath.cosine(omega)
        s = radius * DemoMath.sine(omega)
        real = amplitude * DemoMath.cosine(2 * DemoMath.pi * phase)
        imaginary = amplitude * DemoMath.sine(2 * DemoMath.pi * phase)
    }

    /// Valeur courante (partie réelle), puis avance d'un échantillon.
    mutating func next() -> Double {
        let value = real
        let newReal = real * c - imaginary * s
        imaginary = real * s + imaginary * c
        real = newReal
        return value
    }
}

/// Résonateur à deux pôles de Klatt, de gain unité en continu.
struct Resonator {
    private let a: Double
    private let b: Double
    private let c: Double
    private var y1 = 0.0
    private var y2 = 0.0

    init(frequency: Double, bandwidth: Double, sampleRate: Double) {
        let radius = DemoMath.exponential(-DemoMath.pi * bandwidth / sampleRate)
        c = -radius * radius
        b = 2 * radius * DemoMath.cosine(2 * DemoMath.pi * frequency / sampleRate)
        a = 1 - b - c
    }

    mutating func process(_ x: Double) -> Double {
        let y = a * x + b * y1 + c * y2
        y2 = y1
        y1 = y
        return y
    }
}

/// Fonctions élémentaires calculées par polynômes (Horner) avec les seules opérations IEEE 754 de
/// base : résultats identiques sur toutes les plateformes, contrairement à la libm.
enum DemoMath {
    static let pi = 3.141_592_653_589_793

    /// Sinus, après réduction de l'argument à [−π, π] (Taylor jusqu'au degré 21).
    static func sine(_ x: Double) -> Double {
        let r = reduced(x), r2 = r * r
        var p = 1.0
        for k in stride(from: 10, through: 1, by: -1) {
            p = 1 - r2 / Double(2 * k * (2 * k + 1)) * p
        }
        return r * p
    }

    /// Cosinus, après réduction de l'argument à [−π, π] (Taylor jusqu'au degré 20).
    static func cosine(_ x: Double) -> Double {
        let r = reduced(x), r2 = r * r
        var p = 1.0
        for k in stride(from: 10, through: 1, by: -1) {
            p = 1 - r2 / Double((2 * k - 1) * 2 * k) * p
        }
        return p
    }

    /// Exponentielle : argument divisé par deux jusqu'à |y| ≤ 1/8, Taylor (degré 12), puis carrés.
    static func exponential(_ x: Double) -> Double {
        var y = x, halvings = 0
        while y.magnitude > 0.125 {
            y *= 0.5
            halvings += 1
        }
        var p = 1.0
        for k in stride(from: 12, through: 1, by: -1) {
            p = 1 + y / Double(k) * p
        }
        for _ in 0 ..< halvings { p *= p }
        return p
    }

    /// Courbe en S de 0 à 1 (3t² − 2t³), bornée.
    static func smoothstep(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }

    /// Correction PolyBLEP d'une dent de scie (phase dans [0, 1), incrément par échantillon).
    static func polyBLEP(phase t: Double, increment dt: Double) -> Double {
        if t < dt {
            let x = t / dt
            return x + x - x * x - 1
        }
        if t > 1 - dt {
            let x = (t - 1) / dt
            return x * x + x + x + 1
        }
        return 0
    }

    private static func reduced(_ x: Double) -> Double {
        let twoPi = 2 * pi
        return x - twoPi * (x / twoPi).rounded()
    }
}
