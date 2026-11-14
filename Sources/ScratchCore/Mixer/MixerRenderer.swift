/// Table de mixage : faders de voie, crossfader, hamster, coupures momentanées, limiteur doux et
/// mesures (SF-65 à SF-67, RM-52, arbitrage IC-06). Fil audio uniquement, aucune allocation.
///
/// **Squelette (story EP1, James) : tient les réglages et produit du silence.** À implémenter :
/// - gain de voie = fader de voie × (coupure momentanée ouverte ? 1 : gain du crossfader de la voie),
///   avec `x` inversé si hamster ;
/// - lissage de chaque gain à la fréquence audio (≤ 5 ms, RM-52) ; montée ≤ 1 ms en coupure franche
///   et pour les coupures momentanées ; bascule hamster sans clic (SF-67) ;
/// - somme avec marge et limiteur doux (aucun écrêtage numérique, 6.8), `limiterActive` ;
/// - crêtes de voie (après fader de voie, avant crossfader) et crête de sortie.
struct MixerRenderer {
    private(set) var outputSampleRate: Double
    private(set) var crossfader = TurntableConstants.defaultCrossfader
    private(set) var crossfaderCurve = TurntableConstants.defaultCrossfaderCurve
    private(set) var hamster = false
    private(set) var lineFaders = DeckPair(repeating: TurntableConstants.defaultLineFader)
    private(set) var momentaryCuts = DeckPair(repeating: false)
    private(set) var channelPeaks = DeckPair<Double>(repeating: 0)
    private(set) var outputPeak: Double = 0
    private(set) var limiterActive = false

    init(outputSampleRate: Double) {
        self.outputSampleRate = outputSampleRate
    }

    mutating func setOutputSampleRate(_ rate: Double) {
        guard rate.isFinite, rate > 0 else { return }
        outputSampleRate = rate
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

    /// Mixe les deux voies dans `left`/`right` (écrasement) et met à jour les mesures.
    mutating func mix(
        a: (left: UnsafePointer<Float>, right: UnsafePointer<Float>),
        b: (left: UnsafePointer<Float>, right: UnsafePointer<Float>),
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>
    ) {
        left.update(repeating: 0, count: frameCount)
        right.update(repeating: 0, count: frameCount)
        channelPeaks = DeckPair(repeating: 0)
        outputPeak = 0
        limiterActive = false
    }
}
