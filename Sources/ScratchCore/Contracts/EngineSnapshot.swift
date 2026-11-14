/// État d'une platine, publié par le fil audio une fois par tampon (PRD 5.3 point 3 ; architecture §5.1).
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
    /// Angle cumulé du disque (vinyle et étiquette), en radians, sens horaire positif, 0 = midi.
    /// Hors butée, `discAngle ≡ 2π × position / 1,8 (mod 2π)` : le moteur recale cette constante
    /// (correction d'au plus ±π) après chaque saut de position (CUE, needle drop, chargement) et à la
    /// sortie d'une butée (amorce, sillon fermé) ; en butée, le disque continue de tourner (RM-55).
    /// Disque tenu, le recalage ne déplace pas le disque sous le doigt et ne fait aucun saut de son.
    public var discAngle: Double
    /// Angle cumulé du plateau (indicateur de rotation sous le disque retenu, 6.9).
    public var platterAngle: Double
    /// Angle d'écran du repère (autocollant), en radians, sens horaire positif, 0 = midi (repère de
    /// lecture de la spécification UX, §5.1) : `stickerAngle = discAngle − 2π × (CUE ?? 0) / 1,8`.
    /// Calculé, jamais cumulé : il vaut 0 modulo 2π quand la tête est sur le CUE (ou sur 0 s sans
    /// CUE), tourne avec le disque, y compris en butée (RM-55), et reste juste après chaque recalage
    /// (SF-69, IC-09).
    public var stickerAngle: Double
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
        stickerAngle: Double = 0,
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
        self.stickerAngle = stickerAngle
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
    /// Gain effectif lissé de chaque voie (fader de voie × gain de crossfader ou 1 si coupure
    /// momentanée ouverte), dans 0…1 (PRD 5.3 point 3).
    public var channelGains: DeckPair<Double>
    /// Crête de la sortie stéréo sur le dernier tampon (après limiteur), linéaire.
    public var outputPeak: Double
    /// Réduction de gain maximale du limiteur doux sur le dernier tampon, en dB (≥ 0).
    public var limiterReduction: Double

    public init(
        crossfader: Double = TurntableConstants.defaultCrossfader,
        crossfaderCurve: Double = TurntableConstants.defaultCrossfaderCurve,
        hamster: Bool = false,
        lineFaders: DeckPair<Double> = DeckPair(repeating: TurntableConstants.defaultLineFader),
        momentaryCuts: DeckPair<Bool> = DeckPair(repeating: false),
        channelGains: DeckPair<Double> = DeckPair(repeating: 0),
        outputPeak: Double = 0,
        limiterReduction: Double = 0
    ) {
        self.crossfader = crossfader
        self.crossfaderCurve = crossfaderCurve
        self.hamster = hamster
        self.lineFaders = lineFaders
        self.momentaryCuts = momentaryCuts
        self.channelGains = channelGains
        self.outputPeak = outputPeak
        self.limiterReduction = limiterReduction
    }

    /// Indicateur « limiteur actif » : réduction d'au moins 1 dB (6.8 ; UX §5.16).
    public var limiterActive: Bool { limiterReduction >= 1 }

    /// Écrêtage : crête de sortie ≥ 0 dBFS après limiteur (ne devrait pas arriver ; UX §5.16).
    public var isClipping: Bool { outputPeak >= 1 }

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

    /// Rien ne bouge ni ne sonne : aucun moteur, aucun disque tenu ou en mouvement, VU-mètres à zéro.
    /// L'UI peut alors suspendre sa boucle d'affichage (UX §10.1 « Repos »).
    public var isIdle: Bool {
        !decks.a.isActive && !decks.b.isActive
            && max(decks.a.peakLevel, decks.b.peakLevel, mixer.outputPeak) < 1e-4
    }

    /// État au lancement : platines vides, réglages par défaut de la spec.
    public static let initial = EngineSnapshot()
}
