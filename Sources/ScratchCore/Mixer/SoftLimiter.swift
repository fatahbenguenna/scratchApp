import Foundation

/// Limiteur doux de sortie, stéréo lié, sans latence ajoutée (SF-65, D-13 ; story 1.4 CA 7).
///
/// À chaque échantillon, le gain requis est `plafond / max(|G|, |D|)` (1 si la crête est sous le
/// plafond). L'enveloppe de gain **descend instantanément** au gain requis (aucune anticipation,
/// donc aucune latence, SF-78) et **remonte** vers 1 avec une constante de 50 ms : après la première
/// crête, la réduction varie lentement (pas d'écrêtage ni de distorsion de forme d'onde). La sortie
/// ne dépasse jamais le plafond de −0,1 dBFS ; une dernière borne de sécurité couvre l'arrondi.
/// Aucune atténuation fixe : un son seul à 0 dBFS ne perd que 0,1 dB.
///
/// Fil audio uniquement, aucune allocation ; l'enveloppe rejoint exactement 1 (pas de dénormaux).
struct SoftLimiter {
    /// Plafond de sortie : −0,1 dBFS.
    static let ceiling: Float = 0.988_553_1
    /// Constante de temps de remontée du gain.
    static let releaseTime = 0.050

    private(set) var sampleRate: Double
    /// Gain courant de l'enveloppe (≤ 1).
    private(set) var gain: Double = 1
    private var releaseCoefficient = 0.0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 48_000
        updateCoefficient()
    }

    mutating func setSampleRate(_ rate: Double) {
        guard rate.isFinite, rate > 0 else { return }
        sampleRate = rate
        updateCoefficient()
    }

    mutating func reset() { gain = 1 }

    /// Fil audio uniquement. Limite un échantillon stéréo en place ; renvoie le gain appliqué.
    @inline(__always)
    mutating func process(left: inout Float, right: inout Float) -> Double {
        let peak = Double(max(abs(left), abs(right)))
        let ceiling = Double(Self.ceiling)
        let required = peak > ceiling ? ceiling / peak : 1
        var released = gain + (1 - gain) * releaseCoefficient
        if released > 1 - 1e-9 { released = 1 }
        gain = min(required, released)
        let applied = Float(gain)
        left = min(Self.ceiling, max(-Self.ceiling, left * applied))
        right = min(Self.ceiling, max(-Self.ceiling, right * applied))
        return gain
    }

    private mutating func updateCoefficient() {
        releaseCoefficient = 1 - exp(-1 / (Self.releaseTime * sampleRate))
    }
}
