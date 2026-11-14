import Foundation

/// Voix de lecture d'une platine : lit le clip le long de la trajectoire calculée par
/// `DeckPhysics` (spec 5.1 point 4, SF-07 à SF-09, SF-14, SF-72, SF-77, SF-80, RM-04, RM-05, RM-08,
/// RM-09, RM-55 ; architecture §6.5 ; story 1.3). Fil audio uniquement pour `render` et
/// `beginJumpCrossfade`, aucune allocation, aucun verrou.
///
/// Pour chaque échantillon de sortie :
/// 1. **Lecture** à l'indice fractionnaire `position × fréquence du clip`. Le rééchantillonnage vers
///    la sortie est implicite (incrément `vitesse × fréquence du clip / fréquence de sortie`) : la
///    hauteur ne dépend pas de la fréquence du clip et un changement de sortie ne redécode rien
///    (SF-80, D-22).
/// 2. **Interpolation Hermite 4 points** jusqu'à un rapport de décimation effectif de 2 ; au-delà
///    de 2,5, **filtre anti-repliement** (`AntiAliasingFilter`) ; entre les deux, fondu des deux
///    chemins (noyaux à phase nulle : aucun effet de peigne, aucune marche de timbre, SF-77, D-13).
/// 3. **Bornes** : amorce et au-delà de la fin sont des silences virtuels, sans lecture hors du
///    clip (RM-09). Fondus de bord en fonction de la position : 0,5 ms à l'entrée dans le son depuis
///    l'amorce (l'attaque reste franche), 2 ms avant la fin (le sillon fermé s'arrête sans clic, et
///    un mouvement arrière revient aussitôt dans le son, RM-55).
/// 4. **Saut** (CUE, needle drop) : fondu enchaîné de 5 ms entre l'ancienne tête, qui continue à la
///    même vitesse, et la nouvelle (SF-13, SF-71).
/// 5. **Disque immobile** : un gain de mouvement, suivi d'enveloppe de `|vitesse|` (attaque
///    immédiate, relâchement de 30 ms) ramène la sortie au silence quand le disque reste à l'arrêt,
///    même si l'échantillon sous la tête n'est pas nul (6.3 « Maintenir un disque immobile »). Les
///    inversions rapides d'un scratch ne le déclenchent pas ; sa remontée est limitée à 1 ms, ce qui
///    évite le clic d'un départ instantané (rattrapage de 0 ms) sans adoucir l'attaque d'un
///    « release ».
struct DeckRenderer {
    /// Largeur, en rapport de décimation, du fondu entre interpolation Hermite et filtre.
    static let blendWidth = 0.5
    /// Fondu de bord à l'entrée dans le son (en secondes de son).
    static let startFadeSeconds = 0.000_5
    /// Fondu de bord avant la fin du son (en secondes de son).
    static let endFadeSeconds = 0.002
    /// Vitesse (|vitesse de lecture|) en dessous de laquelle le disque est considéré à l'arrêt.
    static let motionThreshold = 0.02
    /// Constante de relâchement de l'enveloppe de mouvement.
    static let motionReleaseTime = 0.030
    /// Durée minimale d'une remontée complète du gain de mouvement.
    static let motionRiseTime = 0.001

    private(set) var outputSampleRate: Double
    private let antiAliasing = AntiAliasingFilter()

    /// Enveloppe de `|vitesse|` (attaque immédiate, relâchement exponentiel).
    private(set) var motionEnvelope: Double = 0
    /// Gain de mouvement appliqué à la sortie (0 disque à l'arrêt, 1 en mouvement).
    private(set) var motionGain: Double = 0
    private var envelopeRelease = 0.0
    private var gainRiseStep = 0.0

    private var crossfadeLength = 1
    private var crossfadeRemaining = 0
    private var crossfadePosition = 0.0

    init(outputSampleRate: Double) {
        self.outputSampleRate = outputSampleRate.isFinite && outputSampleRate > 0 ? outputSampleRate : 48_000
        updateRateDependentConstants()
    }

    /// Un fondu enchaîné est en cours (diagnostic, tests).
    var isCrossfading: Bool { crossfadeRemaining > 0 }

    mutating func setOutputSampleRate(_ rate: Double) {
        guard rate.isFinite, rate > 0 else { return }
        outputSampleRate = rate
        updateRateDependentConstants()
    }

    /// Réinitialise l'état interne (enveloppe de mouvement, fondu enchaîné) au chargement d'un son.
    mutating func reset() {
        motionEnvelope = 0
        motionGain = 0
        crossfadeRemaining = 0
        crossfadePosition = 0
    }

    /// Fil audio uniquement. Saut de la tête depuis `origin` (s) : la position d'avant continue à la
    /// vitesse du disque et s'efface en `jumpFadeDuration` pendant que la nouvelle apparaît.
    mutating func beginJumpCrossfade(from origin: Double) {
        guard origin.isFinite else { return }
        crossfadePosition = origin
        crossfadeRemaining = crossfadeLength
    }

    /// Fil audio uniquement. Écrit `frameCount` trames stéréo dans `left`/`right` (écrasement, pas
    /// d'accumulation) à partir des positions (s) et des vitesses de lecture signées de `DeckPhysics`.
    mutating func render(
        clip: AudioClip?,
        positions: UnsafePointer<Double>,
        rates: UnsafePointer<Double>,
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>
    ) {
        guard frameCount > 0 else { return }
        guard let clip else {
            left.update(repeating: 0, count: frameCount)
            right.update(repeating: 0, count: frameCount)
            crossfadeRemaining = 0
            return
        }
        let dt = 1 / outputSampleRate
        let ratioScale = clip.sampleRate / outputSampleRate
        let maximumRate = TurntableConstants.maximumPlaybackRate
        let lowerBound = -TurntableConstants.leadInSeconds
        let duration = clip.duration

        for index in 0..<frameCount {
            let rate = min(maximumRate, max(-maximumRate, rates[index].isFinite ? rates[index] : 0))
            let ratio = abs(rate) * ratioScale
            var value = read(clip, at: positions[index], ratio: ratio, duration: duration)

            if crossfadeRemaining > 0 {
                crossfadePosition = min(duration, max(lowerBound, crossfadePosition + rate * dt))
                let old = read(clip, at: crossfadePosition, ratio: ratio, duration: duration)
                let progress = Double(crossfadeLength - crossfadeRemaining + 1) / Double(crossfadeLength)
                let weight = Float(0.5 - 0.5 * cos(Double.pi * progress))
                value.left = old.left + (value.left - old.left) * weight
                value.right = old.right + (value.right - old.right) * weight
                crossfadeRemaining -= 1
            }

            let speed = abs(rate)
            motionEnvelope = speed >= motionEnvelope ? speed : max(speed, motionEnvelope * envelopeRelease)
            if motionEnvelope < 1e-9 { motionEnvelope = 0 }
            let target = Self.smoothstep(motionEnvelope / Self.motionThreshold)
            motionGain = target < motionGain ? target : min(target, motionGain + gainRiseStep)
            let gain = Float(motionGain)

            left[index] = value.left * gain
            right[index] = value.right * gain
        }
    }

    // MARK: Interne

    /// Lecture à la position `position` (s) : interpolation ou filtre selon `ratio`, fondus de bord.
    @inline(__always)
    private func read(_ clip: AudioClip, at position: Double, ratio: Double,
                      duration: Double) -> (left: Float, right: Float) {
        guard position.isFinite, position > 0, position < duration else { return (0, 0) }
        let edge = Self.raisedCosine(position / Self.startFadeSeconds)
            * Self.raisedCosine((duration - position) / Self.endFadeSeconds)
        let x = position * clip.sampleRate
        let blend = Self.smoothstep((ratio - TurntableConstants.antiAliasingRateThreshold) / Self.blendWidth)
        var value: (left: Float, right: Float)
        if blend <= 0 {
            value = HermiteInterpolator.sample(left: clip.left, right: clip.right, at: x)
        } else if blend >= 1 {
            value = antiAliasing.sample(left: clip.left, right: clip.right, at: x, ratio: ratio)
        } else {
            let direct = HermiteInterpolator.sample(left: clip.left, right: clip.right, at: x)
            let filtered = antiAliasing.sample(left: clip.left, right: clip.right, at: x, ratio: ratio)
            let weight = Float(blend)
            value = (direct.left + (filtered.left - direct.left) * weight,
                     direct.right + (filtered.right - direct.right) * weight)
        }
        if edge < 1 {
            let gain = Float(edge)
            value = (value.left * gain, value.right * gain)
        }
        return value
    }

    private mutating func updateRateDependentConstants() {
        envelopeRelease = exp(-1 / (Self.motionReleaseTime * outputSampleRate))
        gainRiseStep = 1 / (Self.motionRiseTime * outputSampleRate)
        crossfadeLength = max(1, Int((TurntableConstants.jumpFadeDuration * outputSampleRate).rounded()))
        crossfadeRemaining = min(crossfadeRemaining, crossfadeLength)
    }

    /// 0 en dessous de 0, 1 au-dessus de 1, raccord cubique C¹ entre les deux.
    @inline(__always)
    static func smoothstep(_ u: Double) -> Double {
        guard u > 0 else { return 0 }
        guard u < 1 else { return 1 }
        return u * u * (3 - 2 * u)
    }

    /// 0 en dessous de 0, 1 au-dessus de 1, demi-période de cosinus entre les deux.
    @inline(__always)
    static func raisedCosine(_ u: Double) -> Double {
        guard u > 0 else { return 0 }
        guard u < 1 else { return 1 }
        return 0.5 - 0.5 * cos(Double.pi * u)
    }
}
