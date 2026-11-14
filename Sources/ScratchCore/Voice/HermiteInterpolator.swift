/// Interpolation Hermite cubique à 4 points (Catmull-Rom, forme « x » d'Olli Niemitalo) entre
/// les échantillons d'un clip (SF-77 ; architecture §6.5).
///
/// Erreur mesurée sur une sinusoïde de 1 kHz échantillonnée à 48 kHz, lue de 0,25× à 2× : environ
/// −90 dB (critère −60 dB, story 1.3 CA 3). Noyau symétrique : phase nulle, ce qui permet de le
/// fondre sans effet de peigne avec le filtre anti-repliement.
///
/// **Bornes (RM-09)** : les voisins d'indice < 0 ou ≥ `frameCount` valent 0 et ne sont jamais lus ;
/// l'amorce et l'au-delà de la fin sont des silences virtuels. Les voisins sont pris dans l'ordre
/// des indices du clip, quel que soit le sens de lecture.
///
/// Fil audio uniquement : fonctions pures, aucune allocation.
enum HermiteInterpolator {
    /// Valeur entre `y0` (t = 0) et `y1` (t = 1), `ym1` et `y2` étant les voisins extérieurs.
    @inline(__always)
    static func value(_ ym1: Float, _ y0: Float, _ y1: Float, _ y2: Float, t: Float) -> Float {
        let c1 = 0.5 * (y1 - ym1)
        let c2 = ym1 - 2.5 * y0 + 2 * y1 - 0.5 * y2
        let c3 = 0.5 * (y2 - ym1) + 1.5 * (y0 - y1)
        return ((c3 * t + c2) * t + c1) * t + y0
    }

    /// Fil audio uniquement. Valeurs gauche et droite à l'indice fractionnaire `x` (en échantillons
    /// du clip). Hors de [−2 ; frameCount + 1[, renvoie (0, 0) sans lire le clip.
    @inline(__always)
    static func sample(left: UnsafeBufferPointer<Float>, right: UnsafeBufferPointer<Float>,
                       at x: Double) -> (left: Float, right: Float) {
        let count = left.count
        guard x > -2, x < Double(count + 1) else { return (0, 0) }
        let base = x.rounded(.down)
        let index = Int(base)
        let t = Float(x - base)
        if index >= 1, index + 2 < count {
            return (value(left[index - 1], left[index], left[index + 1], left[index + 2], t: t),
                    value(right[index - 1], right[index], right[index + 1], right[index + 2], t: t))
        }
        // Near the edges: neighbours outside the clip are virtual zeros (never read).
        return (value(guarded(left, index - 1), guarded(left, index), guarded(left, index + 1), guarded(left, index + 2), t: t),
                value(guarded(right, index - 1), guarded(right, index), guarded(right, index + 1), guarded(right, index + 2), t: t))
    }

    @inline(__always)
    private static func guarded(_ buffer: UnsafeBufferPointer<Float>, _ index: Int) -> Float {
        index >= 0 && index < buffer.count ? buffer[index] : 0
    }
}
