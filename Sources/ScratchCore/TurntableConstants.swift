/// Constantes physiques et métier de la platine virtuelle.
///
/// Références : spec v2.0 — RM-50 (1 tour = 1,8 s), SF-72 (amorce de 2 s), SF-80 (durées limites),
/// SF-68 (couple moteur, feutrine), 5.1 (modèle physique), 5.2 (crossfader), RM-52 (lissage des gains).
///
/// Contrat partagé (architecture, §5) : toute modification passe par l'architecte.
public enum TurntableConstants {
    /// Vitesse de gravure virtuelle : le son est considéré comme gravé à 33⅓ tours (RM-50).
    public static let referenceRPM: Double = 100.0 / 3.0

    /// Durée de son correspondant à un tour complet de disque : 60 / 33⅓ = 1,8 s (RM-50).
    public static let secondsPerRevolution: Double = 60.0 / referenceRPM

    /// Vitesse angulaire nominale du disque à 33⅓ RPM, pitch 0 : 2π × 33⅓ / 60 rad/s (RM-50).
    public static let referenceAngularVelocity: Double = 2.0 * Double.pi * referenceRPM / 60.0

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
    ///
    /// Convention (arbitrage IC-03) : durée pour atteindre 95 % de la vitesse du plateau.
    /// Modèle du 1er ordre de constante τ = T / 3 (ln 20 ≈ 3) ; T = 0 aligne immédiatement le disque.
    public static let defaultSlipmatCatchUp: Double = 0.060
    public static let slipmatCatchUpRange: ClosedRange<Double> = 0.0...0.300

    /// Ralentissement maximal d'un disque relâché moteur arrêté (SF-10).
    ///
    /// Convention (arbitrage IC-03) : décélération linéaire (friction constante) jusqu'à 0.
    public static let freeSpinStopDuration: Double = 0.150

    /// Vitesse de lecture maximale en valeur absolue (SF-77).
    public static let maximumPlaybackRate: Double = 16.0

    /// Seuil de vitesse au-delà duquel le rendu atténue le repliement (SF-77).
    public static let antiAliasingRateThreshold: Double = 2.0

    /// Constantes de temps du filtre de résistance (5.1) : 0 % → 2 ms, 100 % → 35 ms.
    public static let resistanceTimeConstantRange: ClosedRange<Double> = 0.002...0.035

    /// Résistance par défaut (3.1) : 50 %.
    public static let defaultResistance: Double = 0.5

    /// Rayon relatif de la zone morte centrale du disque (RM-61).
    public static let centerDeadZoneRatio: Double = 0.12

    /// Largeur de cut-in du crossfader en coupure franche (SF-66, 5.2).
    public static let crossfaderCutInWidth: Double = 0.03

    /// Réglages initiaux de la table de mixage (3.2) : crossfader au centre, coupure franche,
    /// hamster désactivé, faders de voie à 100 %.
    public static let defaultCrossfader: Double = 0.5
    public static let defaultCrossfaderCurve: Double = 1.0
    public static let defaultLineFader: Double = 1.0

    /// Lissage des gains (RM-52, SF-67) : 5 ms au plus ; montée de 1 ms au plus en coupure franche.
    public static let gainSmoothingTime: Double = 0.005
    public static let hardCutRiseTime: Double = 0.001

    /// Fondu appliqué lors d'un saut de position : CUE, needle drop (SF-71).
    public static let jumpFadeDuration: Double = 0.005

    /// Relâchement du disque 80 ms après le dernier événement de défilement trackpad (SF-79).
    public static let trackpadReleaseDelay: Double = 0.080

    /// Pas du crossfader au clavier (3.5) : 5 %.
    public static let keyboardCrossfaderStep: Double = 0.05

    /// Taille de tampon audio visée (SF-78) : 256 trames à 48 kHz ≈ 5,3 ms.
    public static let preferredBufferFrames: Int = 256
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

    /// Vitesse de lecture nominale relative à la gravure 33⅓ (RM-50) : 1 à 33⅓, 1,35 à 45.
    public var nominalRate: Double { rpm / TurntableConstants.referenceRPM }
}

/// Identifiant d'une platine (SF-64).
public enum DeckID: String, CaseIterable, Codable, Sendable {
    case a = "A"
    case b = "B"
}
