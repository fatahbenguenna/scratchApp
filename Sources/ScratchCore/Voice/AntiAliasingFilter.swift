import Foundation

/// Lecture filtrée d'un clip au-delà d'un rapport de décimation de 2 (SF-77, D-13 ; architecture
/// §6.5 ; story 1.3 CA 4).
///
/// Lire un clip `r` fois plus vite que la sortie (`r = |vitesse| × fréquence du clip / fréquence de
/// sortie`) replie tout contenu au-dessus de `fréquence de sortie / (2 r)`. La voix évalue alors,
/// à la position fractionnaire de la tête, un **sinus cardinal fenêtré** (fenêtre de Kaiser,
/// β = 5,65) dont la coupure suit le rapport : `fc = 0,45 / r` cycle par échantillon du clip, avec
/// 5 passages par zéro de part et d'autre. Réjection mesurée de la composante repliée d'une
/// sinusoïde de 12 kHz lue à 3× : environ 69 dB (critère 40 dB). Le noyau est normalisé par la somme
/// de ses coefficients (gain continu exactement 1, sans ondulation d'amplitude selon la phase).
///
/// **Coût borné** : `2 × 5 × r / 0,9` coefficients, soit environ 180 à 16× (sortie à 48 kHz) ; le
/// rapport est plafonné à `maximumRatio`. Aucune copie préfiltrée du clip (D-21, ADR-05).
///
/// **Bornes (RM-09)** : les indices hors du clip valent 0 et ne sont jamais lus.
///
/// Le noyau est tabulé une seule fois pour tout le processus (≈ 10 Ko, jamais libéré), à la création
/// de la première voix sur le fil de contrôle ; `sample` ne lit que la table. Fil audio uniquement
/// pour `sample`, aucune allocation.
struct AntiAliasingFilter {
    /// Passages par zéro de part et d'autre du centre.
    static let zeroCrossings = 5
    /// Coupure relative à la fréquence de Nyquist de la sortie, ramenée dans le clip (`fc = 0,45 / r`).
    static let cutoffScale = 0.45
    /// Paramètre de la fenêtre de Kaiser (≈ 60 dB de lobes secondaires).
    static let kaiserBeta = 5.65
    /// Points de table par passage par zéro (interpolation linéaire entre deux points).
    static let tableResolution = 512
    /// Rapport de décimation maximal pris en compte (coût borné).
    static let maximumRatio = 40.0

    private static let tableCount = zeroCrossings * tableResolution + 2
    private static let sharedTable: UnsafePointer<Float> = makeTable()

    private let table: UnsafePointer<Float>

    init() {
        table = Self.sharedTable
    }

    /// Fil audio uniquement. Valeurs gauche et droite filtrées à l'indice fractionnaire `x`, pour un
    /// rapport de décimation `ratio` (≥ 1 ; ramené dans [1 ; maximumRatio]).
    func sample(left: UnsafeBufferPointer<Float>, right: UnsafeBufferPointer<Float>,
                at x: Double, ratio: Double) -> (left: Float, right: Float) {
        let r = min(Self.maximumRatio, max(1, ratio))
        let twoCutoff = 2 * Self.cutoffScale / r
        let halfWidth = Double(Self.zeroCrossings) / twoCutoff
        let count = left.count
        guard x + halfWidth > 0, x - halfWidth < Double(count) else { return (0, 0) }
        let first = Int((x - halfWidth).rounded(.up))
        let last = Int((x + halfWidth).rounded(.down))
        let scale = twoCutoff * Double(Self.tableResolution)
        let limit = Self.tableCount - 2
        var weightSum: Float = 0
        var sumLeft: Float = 0
        var sumRight: Float = 0
        var index = first
        while index <= last {
            let u = abs(Double(index) - x) * scale
            let cell = Int(u)
            if cell <= limit {
                let fraction = Float(u - Double(cell))
                let a = table[cell]
                let weight = a + (table[cell + 1] - a) * fraction
                weightSum += weight
                if index >= 0, index < count {
                    sumLeft += weight * left[index]
                    sumRight += weight * right[index]
                }
            }
            index += 1
        }
        guard weightSum > 0 else { return (0, 0) }
        let normalization = 1 / weightSum
        return (sumLeft * normalization, sumRight * normalization)
    }

    /// Noyau prototype `sinc(u) × kaiser(u / N)` pour u ∈ [0 ; N], 0 au-delà.
    private static func makeTable() -> UnsafePointer<Float> {
        let table = UnsafeMutablePointer<Float>.allocate(capacity: tableCount)
        let n = Double(zeroCrossings)
        let normalization = besselI0(kaiserBeta)
        for i in 0..<tableCount {
            let u = Double(i) / Double(tableResolution)
            guard u < n else {
                table[i] = 0
                continue
            }
            let sinc = u == 0 ? 1 : sin(Double.pi * u) / (Double.pi * u)
            let ratio = u / n
            let window = besselI0(kaiserBeta * (1 - ratio * ratio).squareRoot()) / normalization
            table[i] = Float(sinc * window)
        }
        return UnsafePointer(table)
    }

    /// Fonction de Bessel modifiée de première espèce d'ordre 0 (série entière).
    static func besselI0(_ x: Double) -> Double {
        var sum = 1.0
        var term = 1.0
        let quarter = x * x / 4
        for k in 1...60 {
            term *= quarter / Double(k * k)
            sum += term
            if term < sum * 1e-17 { break }
        }
        return sum
    }
}
