/// État d'une platine, publié par le fil audio une fois par tampon (architecture §5.1).
///
/// Type valeur **trivial** (aucune chaîne, aucun tableau, aucune référence) : il traverse le
/// triple tampon sans allocation. Les angles suivent les conventions d'`EngineCommand`.
public struct DeckSnapshot: Equatable, Sendable {
    /// Clip chargé, ou `nil` si la platine est vide.
    public var clipID: AudioClip.ID?
    /// Durée du son chargé (0 sans son).
    public var durationSeconds: Double
    /// Position de la tête, dans [−2 s ; durée] (SF-14, SF-72).
    public var positionSeconds: Double
    /// Vitesse de lecture signée : 1 = vitesse de gravure (33⅓, pitch 0), négative en arrière (RM-50).
    public var playbackRate: Double
    /// Angle cumulé du disque (vinyle), en radians, sens horaire positif. Continue de tourner en butée.
    public var discAngle: Double
    /// Angle cumulé du plateau (indicateur de rotation sous le disque retenu, 6.9).
    public var platterAngle: Double
    /// Angle cumulé du repère (SF-69). Hors butée, `markerAngle ≡ (position − CUE) × 2π / 1,8` :
    /// il vaut 0 modulo 2π quand la tête est sur le CUE (ou sur 0 s sans CUE). En butée (amorce,
    /// sillon fermé), il tourne avec le disque (RM-55) et il est recalé à la sortie de butée et à
    /// chaque saut (CUE, needle drop, chargement).
    public var markerAngle: Double
    /// Disque tenu par un doigt, un clic ou le trackpad.
    public var isHeld: Bool
    /// État START/STOP du moteur (RM-53 : un toucher ne le change jamais).
    public var motorOn: Bool
    public var speed: TurntableSpeed
    /// Pitch en fraction (−0,08…0,08).
    public var pitch: Double
    /// Résistance 0…1.
    public var resistance: Double
    /// CUE mémorisé, ou `nil` (CUE rappelle alors 0 s).
    public var cueSeconds: Double?
    /// Tête bloquée en fin de son (sillon fermé, RM-55).
    public var isAtEnd: Bool
    /// Tête dans l'amorce silencieuse (position < 0).
    public var isInLeadIn: Bool
    /// Crête de la voie sur le dernier tampon, après fader de voie et avant crossfader
    /// (VU-mètre de voie, SF-65). Linéaire, 1 = 0 dBFS. L'UI applique la balistique.
    public var peakLevel: Double

    public init(
        clipID: AudioClip.ID? = nil,
        durationSeconds: Double = 0,
        positionSeconds: Double = 0,
        playbackRate: Double = 0,
        discAngle: Double = 0,
        platterAngle: Double = 0,
        markerAngle: Double = 0,
        isHeld: Bool = false,
        motorOn: Bool = false,
        speed: TurntableSpeed = .rpm33,
        pitch: Double = 0,
        resistance: Double = TurntableConstants.defaultResistance,
        cueSeconds: Double? = nil,
        isAtEnd: Bool = false,
        isInLeadIn: Bool = false,
        peakLevel: Double = 0
    ) {
        self.clipID = clipID
        self.durationSeconds = durationSeconds
        self.positionSeconds = positionSeconds
        self.playbackRate = playbackRate
        self.discAngle = discAngle
        self.platterAngle = platterAngle
        self.markerAngle = markerAngle
        self.isHeld = isHeld
        self.motorOn = motorOn
        self.speed = speed
        self.pitch = pitch
        self.resistance = resistance
        self.cueSeconds = cueSeconds
        self.isAtEnd = isAtEnd
        self.isInLeadIn = isInLeadIn
        self.peakLevel = peakLevel
    }

    /// Un son est chargé.
    public var isLoaded: Bool { clipID != nil }

    /// Platine « active » au sens de SF-15 : moteur en marche, disque tenu ou en mouvement.
    /// Le remplacement de son son demande alors une confirmation.
    public var isActive: Bool { motorOn || isHeld || abs(playbackRate) > 1e-3 }

    /// Platine vide à l'état initial.
    public static let initial = DeckSnapshot()
}

/// État de la table de mixage (SF-65 à SF-67).
public struct MixerSnapshot: Equatable, Sendable {
    public var crossfader: Double
    public var crossfaderCurve: Double
    public var hamster: Bool
    public var lineFaders: DeckPair<Double>
    public var momentaryCuts: DeckPair<Bool>
    /// Crête de la sortie stéréo sur le dernier tampon (après limiteur), linéaire.
    public var outputPeak: Double
    /// Le limiteur doux a réduit le gain pendant le dernier tampon (indicateur de saturation, 6.8).
    public var limiterActive: Bool

    public init(
        crossfader: Double = TurntableConstants.defaultCrossfader,
        crossfaderCurve: Double = TurntableConstants.defaultCrossfaderCurve,
        hamster: Bool = false,
        lineFaders: DeckPair<Double> = DeckPair(repeating: TurntableConstants.defaultLineFader),
        momentaryCuts: DeckPair<Bool> = DeckPair(repeating: false),
        outputPeak: Double = 0,
        limiterActive: Bool = false
    ) {
        self.crossfader = crossfader
        self.crossfaderCurve = crossfaderCurve
        self.hamster = hamster
        self.lineFaders = lineFaders
        self.momentaryCuts = momentaryCuts
        self.outputPeak = outputPeak
        self.limiterActive = limiterActive
    }

    public static let initial = MixerSnapshot()
}

/// Instantané complet du moteur, cohérent (construit en un point du fil audio).
public struct EngineSnapshot: Equatable, Sendable {
    public var decks: DeckPair<DeckSnapshot>
    public var mixer: MixerSnapshot
    public var motorTimings: MotorTimings
    /// Fréquence de sortie utilisée par le rendu, en Hz.
    public var outputSampleRate: Double
    /// Nombre de trames rendues depuis la création du moteur (horloge audio).
    public var sampleTime: Int64

    public init(
        decks: DeckPair<DeckSnapshot> = DeckPair(repeating: .initial),
        mixer: MixerSnapshot = .initial,
        motorTimings: MotorTimings = .defaults,
        outputSampleRate: Double = 48_000,
        sampleTime: Int64 = 0
    ) {
        self.decks = decks
        self.mixer = mixer
        self.motorTimings = motorTimings
        self.outputSampleRate = outputSampleRate
        self.sampleTime = sampleTime
    }

    public subscript(deck: DeckID) -> DeckSnapshot { decks[deck] }

    /// État au lancement : platines vides, réglages par défaut de la spec.
    public static let initial = EngineSnapshot()
}
