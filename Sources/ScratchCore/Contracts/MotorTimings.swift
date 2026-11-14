/// Réglages moteur communs aux deux platines (SF-68, 3.3).
public struct MotorTimings: Codable, Equatable, Sendable {
    /// Durée de démarrage jusqu'à la vitesse cible, en secondes.
    public var startDuration: Double
    /// Durée de freinage jusqu'à l'arrêt, en secondes.
    public var brakeDuration: Double
    /// Temps de rattrapage de la feutrine (95 % de la vitesse du plateau), en secondes.
    public var slipmatCatchUp: Double

    public init(
        startDuration: Double = TurntableConstants.defaultStartDuration,
        brakeDuration: Double = TurntableConstants.defaultBrakeDuration,
        slipmatCatchUp: Double = TurntableConstants.defaultSlipmatCatchUp
    ) {
        self.startDuration = startDuration
        self.brakeDuration = brakeDuration
        self.slipmatCatchUp = slipmatCatchUp
    }

    /// Décodage tolérant : une clé absente ou illisible prend la valeur par défaut.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startDuration = (try? container.decodeIfPresent(Double.self, forKey: .startDuration))
            ?? TurntableConstants.defaultStartDuration
        brakeDuration = (try? container.decodeIfPresent(Double.self, forKey: .brakeDuration))
            ?? TurntableConstants.defaultBrakeDuration
        slipmatCatchUp = (try? container.decodeIfPresent(Double.self, forKey: .slipmatCatchUp))
            ?? TurntableConstants.defaultSlipmatCatchUp
    }

    /// Valeurs par défaut de la spec : 0,7 s, 1,0 s, 60 ms.
    public static let defaults = MotorTimings()

    /// Copie bornée aux plages de la spec (valeurs non finies remplacées par les valeurs par défaut).
    public func clamped() -> MotorTimings {
        MotorTimings(
            startDuration: startDuration.clamped(to: TurntableConstants.motorDurationRange,
                                                 fallback: TurntableConstants.defaultStartDuration),
            brakeDuration: brakeDuration.clamped(to: TurntableConstants.motorDurationRange,
                                                 fallback: TurntableConstants.defaultBrakeDuration),
            slipmatCatchUp: slipmatCatchUp.clamped(to: TurntableConstants.slipmatCatchUpRange,
                                                   fallback: TurntableConstants.defaultSlipmatCatchUp)
        )
    }
}

extension Double {
    /// Borne la valeur à `range` ; une valeur non finie est remplacée par `fallback`.
    public func clamped(to range: ClosedRange<Double>, fallback: Double) -> Double {
        guard isFinite else { return fallback }
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
