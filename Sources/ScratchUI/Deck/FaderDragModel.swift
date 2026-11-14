import ScratchCore

/// Glisser d'un fader par son bouton (UX §5.0, §5.4) : déplacement relatif depuis le point de
/// saisie, valeur arrondie au pas, cran facultatif (la valeur reste à `detentValue` sur `detentWidth`
/// points de déplacement du doigt). Logique pure.
///
/// Pitch : toute la course (`travel` points) couvre −8 % … +8 % (16 points de pitch), pas de 0,1 %,
/// cran de 6 pt à 0 %.
struct FaderDragModel: Equatable {
    let range: ClosedRange<Double>
    let step: Double
    /// Déplacement du doigt, en points, pour toute la plage (hors cran).
    let travel: Double
    let detentValue: Double?
    let detentWidth: Double
    private var grabFinger = 0.0

    init(range: ClosedRange<Double>, step: Double, travel: Double, detentValue: Double? = nil, detentWidth: Double = 0) {
        self.range = range
        self.step = step
        self.travel = max(1, travel)
        self.detentValue = detentValue
        self.detentWidth = detentValue == nil ? 0 : max(0, detentWidth)
    }

    /// Pitch : ±8 % sur la course, pas de 0,1 %, cran de 6 pt à 0 % (UX §5.4).
    static func pitch(travel: Double) -> FaderDragModel {
        FaderDragModel(range: TurntableConstants.pitchRange, step: TurntableConstants.pitchStep, travel: travel,
                       detentValue: 0, detentWidth: 6)
    }

    /// Saisie du bouton à la valeur courante.
    mutating func begin(at value: Double) {
        grabFinger = finger(for: value)
    }

    /// Valeur après un déplacement du doigt de `translation` points depuis la saisie (positif = vers
    /// le haut ou vers la droite).
    func value(afterDrag translation: Double) -> Double {
        let raw = value(atFinger: grabFinger + translation)
        let quantized = (raw / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, quantized))
    }

    private var span: Double { range.upperBound - range.lowerBound }

    /// Position « doigt » du début du cran.
    private var detentStart: Double? {
        detentValue.map { ($0 - range.lowerBound) / span * travel }
    }

    private func finger(for value: Double) -> Double {
        let base = (value - range.lowerBound) / span * travel
        guard let detent = detentValue else { return base }
        if abs(value - detent) < step / 2 { return base + detentWidth / 2 }
        return value > detent ? base + detentWidth : base
    }

    private func value(atFinger finger: Double) -> Double {
        var position = finger
        if let start = detentStart {
            if finger >= start + detentWidth {
                position = finger - detentWidth
            } else if finger > start {
                position = start
            }
        }
        return range.lowerBound + min(1, max(0, position / travel)) * span
    }
}
