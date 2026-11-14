import Foundation

/// Table de mixage : faders de voie, crossfader, courbe, hamster, coupures momentanées, limiteur doux
/// et mesures (spec 3.2, 3.5, 5.2 ; SF-12, SF-65 à SF-67, RM-06, RM-08, RM-52 ; D-06, D-13, D-26 ;
/// story 1.4). Fil audio uniquement pour `mix`, aucune allocation, aucun verrou.
///
/// - **Gain de voie** (RM-52, D-06) : `fader de voie × (coupure momentanée ouverte ? 1 : gain du
///   crossfader)`, la position étant inversée (`x → 1 − x`) **avant** la courbe si le hamster est actif.
///   La coupure de A vise toujours la voie A (et B la voie B), quel que soit le hamster.
/// - **Lissage** (RM-52, RM-08) : les deux facteurs sont lissés séparément par rampes linéaires.
///   Fader de voie : 5 ms. Facteur de crossfader : 1 ms en coupure franche (largeur de cut-in
///   `w ≤ 0,2`, repères de l'UX §5.12) et à chaque ouverture ou fermeture d'une coupure momentanée,
///   5 ms sinon (courbe douce : pas de « zip »). Les cibles sont recalculées au début de chaque appel
///   (les commandes arrivent entre deux tampons) ; une bascule du hamster suit le même lissage.
/// - **Sortie** : somme des deux voies, puis `SoftLimiter` (plafond −0,1 dBFS, sans latence).
/// - **Mesures**, réinitialisées à chaque appel : crête de chaque voie après le fader de voie et avant
///   le crossfader (VU-mètre, D-26), gains effectifs lissés, crête de sortie après limiteur et
///   réduction maximale du limiteur en dB.
///
/// La table ne lit ni n'écrit l'état des platines (SF-12, RM-06).
struct MixerRenderer {
    /// Lissage des faders de voie et du crossfader hors coupure franche.
    static let smoothingTime = TurntableConstants.gainSmoothingTime
    /// Montée en coupure franche et pour les coupures momentanées.
    static let hardCutTime = TurntableConstants.hardCutRiseTime
    /// Largeur de cut-in en dessous de laquelle la courbe est traitée en coupure franche (UX §5.12).
    static let hardCutWidth = 0.2

    private(set) var outputSampleRate: Double
    private(set) var crossfader = TurntableConstants.defaultCrossfader
    private(set) var crossfaderCurve = TurntableConstants.defaultCrossfaderCurve
    private(set) var hamster = false
    private(set) var lineFaders = DeckPair(repeating: TurntableConstants.defaultLineFader)
    private(set) var momentaryCuts = DeckPair(repeating: false)
    private(set) var channelGains = DeckPair<Double>(repeating: 0)
    private(set) var channelPeaks = DeckPair<Double>(repeating: 0)
    private(set) var outputPeak: Double = 0
    private(set) var limiterReduction: Double = 0

    // Smoothed factors (start silent: the first block fades in).
    private var faderA = SmoothedGain(0)
    private var faderB = SmoothedGain(0)
    private var crossA = SmoothedGain(0)
    private var crossB = SmoothedGain(0)
    private var appliedCuts = DeckPair(repeating: false)
    private var limiter: SoftLimiter
    private var smoothingSamples = 240
    private var hardCutSamples = 48

    init(outputSampleRate: Double) {
        let rate = outputSampleRate.isFinite && outputSampleRate > 0 ? outputSampleRate : 48_000
        self.outputSampleRate = rate
        limiter = SoftLimiter(sampleRate: rate)
        updateRampLengths()
    }

    mutating func setOutputSampleRate(_ rate: Double) {
        guard rate.isFinite, rate > 0 else { return }
        outputSampleRate = rate
        limiter.setSampleRate(rate)
        updateRampLengths()
    }

    /// Cibles des gains de voie : `(fader, facteur de crossfader)` pour A et B (CA 1, 5).
    var targetGains: (faderA: Double, crossA: Double, faderB: Double, crossB: Double) {
        let position = hamster ? 1 - crossfader : crossfader
        let curve = CrossfaderCurve.gains(position: position, curve: crossfaderCurve)
        return (lineFaders.a, momentaryCuts.a ? 1 : curve.a, lineFaders.b, momentaryCuts.b ? 1 : curve.b)
    }

    mutating func setCrossfader(_ value: Double) {
        guard value.isFinite else { return }
        crossfader = value.clamped(to: 0...1, fallback: TurntableConstants.defaultCrossfader)
    }

    mutating func setCrossfaderCurve(_ value: Double) {
        guard value.isFinite else { return }
        crossfaderCurve = value.clamped(to: 0...1, fallback: TurntableConstants.defaultCrossfaderCurve)
    }

    mutating func setHamster(_ on: Bool) { hamster = on }

    mutating func setLineFader(_ deck: DeckID, _ value: Double) {
        guard value.isFinite else { return }
        lineFaders[deck] = value.clamped(to: 0...1, fallback: TurntableConstants.defaultLineFader)
    }

    mutating func setMomentaryCut(_ deck: DeckID, open: Bool) { momentaryCuts[deck] = open }

    /// Fil audio uniquement. Mixe les deux voies dans `left`/`right` (écrasement) et met à jour les
    /// mesures du tampon.
    mutating func mix(
        a: (left: UnsafePointer<Float>, right: UnsafePointer<Float>),
        b: (left: UnsafePointer<Float>, right: UnsafePointer<Float>),
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>
    ) {
        updateTargets()
        var peakA: Float = 0
        var peakB: Float = 0
        var peakOut: Float = 0
        var smallestGain = 1.0
        for index in 0..<max(0, frameCount) {
            let fA = Float(faderA.next())
            let fB = Float(faderB.next())
            let gA = fA * Float(crossA.next())
            let gB = fB * Float(crossB.next())
            let aL = a.left[index], aR = a.right[index]
            let bL = b.left[index], bR = b.right[index]
            peakA = max(peakA, max(abs(aL), abs(aR)) * fA)
            peakB = max(peakB, max(abs(bL), abs(bR)) * fB)
            var outL = aL * gA + bL * gB
            var outR = aR * gA + bR * gB
            smallestGain = min(smallestGain, limiter.process(left: &outL, right: &outR))
            peakOut = max(peakOut, max(abs(outL), abs(outR)))
            left[index] = outL
            right[index] = outR
        }
        channelPeaks = DeckPair(a: Double(peakA), b: Double(peakB))
        channelGains = DeckPair(a: faderA.value * crossA.value, b: faderB.value * crossB.value)
        outputPeak = Double(peakOut)
        limiterReduction = smallestGain < 1 ? -20 * log10(smallestGain) : 0
    }

    // MARK: Interne

    private mutating func updateTargets() {
        let targets = targetGains
        faderA.setTarget(targets.faderA, rampSamples: smoothingSamples)
        faderB.setTarget(targets.faderB, rampSamples: smoothingSamples)
        let hardCurve = CrossfaderCurve.cutInWidth(curve: crossfaderCurve) <= Self.hardCutWidth
        let rampA = hardCurve || appliedCuts.a != momentaryCuts.a ? hardCutSamples : smoothingSamples
        let rampB = hardCurve || appliedCuts.b != momentaryCuts.b ? hardCutSamples : smoothingSamples
        crossA.setTarget(targets.crossA, rampSamples: rampA)
        crossB.setTarget(targets.crossB, rampSamples: rampB)
        appliedCuts = momentaryCuts
    }

    private mutating func updateRampLengths() {
        smoothingSamples = max(1, Int((Self.smoothingTime * outputSampleRate).rounded()))
        hardCutSamples = max(1, Int((Self.hardCutTime * outputSampleRate).rounded()))
    }
}
