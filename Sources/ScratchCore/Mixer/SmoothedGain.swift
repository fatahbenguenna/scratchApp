/// Gain lissé à la fréquence audio par rampe linéaire (RM-52, RM-08 ; story 1.4).
///
/// Chaque nouvelle cible est atteinte **exactement** en `rampSamples` échantillons depuis la valeur
/// courante (aucune marche, aucune traîne exponentielle ni dénormal) : avec une rampe de 1 ms à
/// 48 kHz, un gain passe de 0 à sa cible en 48 échantillons par pas de 1/48 de la cible (critère :
/// 99 % en 48 échantillons au plus, pas ≤ 1/8). Une cible identique à la cible courante ne relance
/// pas la rampe. Fil audio uniquement, aucune allocation.
struct SmoothedGain: Equatable, Sendable {
    private(set) var value: Double
    private(set) var target: Double
    private var step: Double = 0
    private var remaining = 0

    init(_ initial: Double) {
        value = initial
        target = initial
    }

    /// La valeur a rejoint la cible.
    var isSettled: Bool { remaining == 0 }

    /// Nouvelle cible, atteinte en `rampSamples` échantillons (1 au moins).
    mutating func setTarget(_ newTarget: Double, rampSamples: Int) {
        guard newTarget.isFinite, newTarget != target else { return }
        target = newTarget
        remaining = max(1, rampSamples)
        step = (target - value) / Double(remaining)
    }

    /// Valeur et cible posées sans rampe.
    mutating func reset(to newValue: Double) {
        value = newValue
        target = newValue
        remaining = 0
        step = 0
    }

    /// Fil audio uniquement. Avance d'un échantillon et renvoie la valeur.
    @inline(__always)
    mutating func next() -> Double {
        if remaining > 0 {
            remaining -= 1
            value = remaining == 0 ? target : value + step
        }
        return value
    }
}
