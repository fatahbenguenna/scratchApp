/// Lecture d'un clip le long de la trajectoire calculée par `DeckPhysics` (SF-77, SF-72, RM-55).
/// Fil audio uniquement, aucune allocation.
///
/// **Squelette (story EP1, James) : produit du silence.** À implémenter :
/// - interpolation Hermite cubique (4 points) entre échantillons, position en secondes ×
///   `clip.sampleRate` (le rééchantillonnage vers la sortie est implicite : incrément =
///   vitesse × clipRate / outputRate) ;
/// - amorce : positions < 0 → silence, sans lecture hors bornes (RM-09) ; sillon fermé : position ≥
///   durée → silence, fondu court à l'arrivée en butée pour éviter le clic (6.12) ;
/// - anti-repliement au-delà d'un rapport de décimation effectif |vitesse| × clipRate / outputRate
///   supérieur à 2 (filtre passe-bas à coupure adaptée, coût borné) ;
/// - fondu enchaîné de 5 ms entre l'ancienne et la nouvelle position lors d'un saut (CUE, needle
///   drop : SF-71, 6.6) ;
/// - crête de la voie pour le VU-mètre.
struct DeckRenderer {
    private(set) var outputSampleRate: Double

    init(outputSampleRate: Double) {
        self.outputSampleRate = outputSampleRate
    }

    mutating func setOutputSampleRate(_ rate: Double) {
        guard rate.isFinite, rate > 0 else { return }
        outputSampleRate = rate
    }

    /// Réinitialise l'état interne (historique du filtre, fondus) au chargement d'un son.
    mutating func reset() {}

    /// Écrit `frameCount` trames stéréo dans `left`/`right` (écrasement, pas d'accumulation).
    mutating func render(
        clip: AudioClip?,
        positions: UnsafePointer<Double>,
        rates: UnsafePointer<Double>,
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>
    ) {
        left.update(repeating: 0, count: frameCount)
        right.update(repeating: 0, count: frameCount)
    }
}
