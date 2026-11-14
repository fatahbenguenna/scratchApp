import Foundation

/// Enveloppe min/max d'un son, multirésolution (story 4.6 CA 1 ; NFR4 ; UX §10.2).
///
/// - Niveau de base : un point (minimum et maximum des deux canaux) par bloc d'environ 1/300 s ;
/// - niveaux réduits : chacun regroupe deux points du précédent, jusqu'à quelques points pour tout
///   le son ; l'aperçu et la bande zoomée lisent le niveau le plus grossier qui garde au moins un
///   point par colonne d'écran.
///
/// Valeurs stockées en `Int16` (pleine échelle = 32 767) : pour 10 min, ≈ 180 000 points, soit
/// ≈ 0,7 Mo pour la base et ≈ 1,4 Mo avec les niveaux réduits (2 Mo au plus par son).
/// Immuable après l'analyse : partagée entre fils et entre les deux platines (RM-57).
public final class WaveformPeaks: Sendable {
    /// Un niveau de résolution.
    struct Level: Sendable {
        let pointsPerSecond: Double
        let minimums: [Int16]
        let maximums: [Int16]
        var count: Int { minimums.count }
    }

    /// Durée du son analysé, en secondes.
    public let duration: Double
    /// Niveaux, du plus fin (base) au plus grossier.
    let levels: [Level]

    /// Points par seconde du niveau de base (≈ 300).
    public var pointsPerSecond: Double { levels[0].pointsPerSecond }
    /// Nombre de points du niveau de base.
    public var baseCount: Int { levels[0].count }
    /// Mémoire occupée par les points, tous niveaux compris.
    public var byteCount: Int { levels.reduce(0) { $0 + $1.count * 2 * MemoryLayout<Int16>.stride } }

    /// - Precondition: `minimums` et `maximums` de même longueur, non vides ; `pointsPerSecond` > 0.
    init(pointsPerSecond: Double, duration: Double, minimums: [Int16], maximums: [Int16]) {
        precondition(minimums.count == maximums.count && !minimums.isEmpty && pointsPerSecond > 0)
        self.duration = duration
        var levels = [Level(pointsPerSecond: pointsPerSecond, minimums: minimums, maximums: maximums)]
        while let last = levels.last, last.count > 8 {
            levels.append(Self.halved(last))
        }
        self.levels = levels
    }

    private static func halved(_ level: Level) -> Level {
        let count = (level.count + 1) / 2
        var minimums = [Int16](repeating: 0, count: count)
        var maximums = [Int16](repeating: 0, count: count)
        for index in 0..<count {
            let first = 2 * index
            let second = min(first + 1, level.count - 1)
            minimums[index] = min(level.minimums[first], level.minimums[second])
            maximums[index] = max(level.maximums[first], level.maximums[second])
        }
        return Level(pointsPerSecond: level.pointsPerSecond / 2, minimums: minimums, maximums: maximums)
    }

    /// Points lus au moins par intervalle, quand le niveau de base le permet : l'enveloppe ne
    /// déborde ainsi que d'un quart d'intervalle de chaque côté.
    static let minimumPointsPerSpan = 4.0

    /// Niveau le plus grossier qui garde au moins quatre points sur une durée `span`.
    func level(forSpan span: Double) -> Level {
        var chosen = levels[0]
        for level in levels.dropFirst() {
            guard level.pointsPerSecond * span >= Self.minimumPointsPerSpan else { break }
            chosen = level
        }
        return chosen
    }

    /// Enveloppe sur [`start` ; `end`[, en fraction de la pleine échelle (−1…1), ou `nil` hors du son
    /// (amorce, après la fin). Sans allocation : appelée une fois par colonne au rendu d'une tuile.
    func envelope(from start: Double, to end: Double) -> (min: Float, max: Float)? {
        guard end > start, end > 0, start < duration else { return nil }
        let level = level(forSpan: end - start)
        let lower = min(level.count - 1, Int(max(0, start) * level.pointsPerSecond))
        let upper = min(level.count, max(lower + 1, Int((min(end, duration) * level.pointsPerSecond).rounded(.up))))
        var low = Int16.max
        var high = Int16.min
        for index in lower..<upper {
            low = min(low, level.minimums[index])
            high = max(high, level.maximums[index])
        }
        return (Float(low) / Self.fullScale, Float(high) / Self.fullScale)
    }

    static let fullScale: Float = 32_767

    /// Quantifie un échantillon sur la pleine échelle `Int16` (valeur non finie : 0).
    static func quantize(_ value: Float) -> Int16 {
        guard value.isFinite else { return 0 }
        return Int16((min(max(value, -1), 1) * fullScale).rounded())
    }
}
