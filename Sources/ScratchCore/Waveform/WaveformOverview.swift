/// Résumé de forme d'onde d'un clip, pour l'aperçu complet et la bande zoomée (SF-70).
/// Calcul pur, à lancer hors du fil principal (tâche détachée) après le décodage.
///
/// **Squelette (story EP4, Léa) : résumé vide.** À implémenter : crête absolue (max |L|, |R|) par
/// tranche de `1 / bucketsPerSecond` seconde, dans 0…1 ; la bande zoomée (±1,8 s) lit les mêmes
/// tranches, ou un niveau plus fin calculé de la même façon.
public struct WaveformOverview: Equatable, Sendable {
    /// Durée couverte par une tranche, en secondes.
    public let bucketDuration: Double
    /// Crête par tranche, dans 0…1, de la position 0 à la fin du son.
    public let peaks: [Float]

    public init(bucketDuration: Double, peaks: [Float]) {
        self.bucketDuration = bucketDuration
        self.peaks = peaks
    }

    public static let empty = WaveformOverview(bucketDuration: 0, peaks: [])

    /// Calcule le résumé d'un clip.
    public static func compute(from clip: AudioClip, bucketsPerSecond: Double = 200) -> WaveformOverview {
        .empty
    }
}
