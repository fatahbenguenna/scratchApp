/// Constantes physiques et métier de la platine virtuelle.
///
/// Références : spec v2.0 — RM-50 (1 tour = 1,8 s), SF-72 (amorce de 2 s), SF-80 (durées limites),
/// SF-68 (couple moteur, feutrine), 5.1 (modèle physique).
public enum TurntableConstants {
    /// Vitesse de gravure virtuelle : le son est considéré comme gravé à 33⅓ tours (RM-50).
    public static let referenceRPM: Double = 100.0 / 3.0

    /// Durée de son correspondant à un tour complet de disque : 60 / 33⅓ = 1,8 s (RM-50).
    public static let secondsPerRevolution: Double = 60.0 / referenceRPM

    /// Amorce silencieuse placée avant le début du son (SF-72).
    public static let leadInSeconds: Double = 2.0

    /// Durée maximale d'un son en V1 (SF-80).
    public static let maximumDurationSeconds: Double = 600.0

    /// Durée minimale d'un son (SF-80).
    public static let minimumDurationSeconds: Double = 0.05

    /// Plage de pitch V1 : −8 % à +8 % (SF-11).
    public static let pitchRange: ClosedRange<Double> = -0.08...0.08

    /// Pas de réglage du pitch : 0,1 % (SF-11).
    public static let pitchStep: Double = 0.001

    /// Durées moteur par défaut et bornes (SF-04, SF-05, SF-68).
    public static let defaultStartDuration: Double = 0.7
    public static let defaultBrakeDuration: Double = 1.0
    public static let motorDurationRange: ClosedRange<Double> = 0.1...5.0

    /// Temps de rattrapage de la feutrine au relâchement (SF-68).
    public static let defaultSlipmatCatchUp: Double = 0.060
    public static let slipmatCatchUpRange: ClosedRange<Double> = 0.0...0.300

    /// Ralentissement maximal d'un disque relâché moteur arrêté (SF-10).
    public static let freeSpinStopDuration: Double = 0.150

    /// Vitesse de lecture maximale en valeur absolue (SF-77).
    public static let maximumPlaybackRate: Double = 16.0

    /// Constantes de temps du filtre de résistance (5.1) : 0 % → 2 ms, 100 % → 35 ms.
    public static let resistanceTimeConstantRange: ClosedRange<Double> = 0.002...0.035

    /// Rayon relatif de la zone morte centrale du disque (RM-61).
    public static let centerDeadZoneRatio: Double = 0.12

    /// Largeur de cut-in du crossfader en coupure franche (SF-66, 5.2).
    public static let crossfaderCutInWidth: Double = 0.03
}

/// Vitesses nominales sélectionnables (SF-04, 6.2).
public enum TurntableSpeed: String, CaseIterable, Codable, Sendable {
    case rpm33 = "33"
    case rpm45 = "45"

    /// Vitesse en tours par minute.
    public var rpm: Double {
        switch self {
        case .rpm33: return TurntableConstants.referenceRPM
        case .rpm45: return 45.0
        }
    }
}

/// Identifiant d'une platine (SF-64).
public enum DeckID: String, CaseIterable, Codable, Sendable {
    case a = "A"
    case b = "B"
}
