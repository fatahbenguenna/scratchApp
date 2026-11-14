import ScratchCore

/// Préférences conservées entre les lancements (SF-17, SF-24 ; architecture §8).
///
/// Persistées en un seul document JSON (`PreferencesStoring`). Le décodage est **tolérant** : une
/// clé absente prend la valeur par défaut, pour que l'ajout d'un réglage ne fasse pas perdre les
/// autres. Les sons chargés et l'état START/STOP ne sont jamais conservés (SF-17, RM-10).
public struct AppPreferences: Codable, Equatable, Sendable {
    /// Réglages propres à une platine.
    public struct Deck: Codable, Equatable, Sendable {
        public var speed: TurntableSpeed
        /// Pitch en fraction (−0,08…0,08).
        public var pitch: Double
        /// Résistance du vinyle 0…1.
        public var resistance: Double

        public init(speed: TurntableSpeed = .rpm33, pitch: Double = 0,
                    resistance: Double = TurntableConstants.defaultResistance) {
            self.speed = speed
            self.pitch = pitch
            self.resistance = resistance
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Deck()
            speed = (try? container.decodeIfPresent(TurntableSpeed.self, forKey: .speed)) ?? defaults.speed
            pitch = (try? container.decodeIfPresent(Double.self, forKey: .pitch)) ?? defaults.pitch
            resistance = (try? container.decodeIfPresent(Double.self, forKey: .resistance)) ?? defaults.resistance
        }
    }

    /// Réglages de la table de mixage.
    public struct Mixer: Codable, Equatable, Sendable {
        public var crossfader: Double
        public var crossfaderCurve: Double
        public var hamster: Bool
        public var lineFaders: DeckPair<Double>

        public init(crossfader: Double = TurntableConstants.defaultCrossfader,
                    crossfaderCurve: Double = TurntableConstants.defaultCrossfaderCurve,
                    hamster: Bool = false,
                    lineFaders: DeckPair<Double> = DeckPair(repeating: TurntableConstants.defaultLineFader)) {
            self.crossfader = crossfader
            self.crossfaderCurve = crossfaderCurve
            self.hamster = hamster
            self.lineFaders = lineFaders
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = Mixer()
            crossfader = (try? container.decodeIfPresent(Double.self, forKey: .crossfader)) ?? defaults.crossfader
            crossfaderCurve = (try? container.decodeIfPresent(Double.self, forKey: .crossfaderCurve)) ?? defaults.crossfaderCurve
            hamster = (try? container.decodeIfPresent(Bool.self, forKey: .hamster)) ?? defaults.hamster
            lineFaders = (try? container.decodeIfPresent(DeckPair<Double>.self, forKey: .lineFaders)) ?? defaults.lineFaders
        }
    }

    /// Version du format, pour une migration future.
    public var version: Int
    public var decks: DeckPair<Deck>
    public var mixer: Mixer
    public var motor: MotorTimings

    public static let currentVersion = 1

    public init(decks: DeckPair<Deck> = DeckPair(repeating: Deck()), mixer: Mixer = Mixer(),
                motor: MotorTimings = .defaults) {
        self.version = Self.currentVersion
        self.decks = decks
        self.mixer = mixer
        self.motor = motor
    }

    /// Valeurs du premier lancement (3.1, 3.2, SF-04, SF-05, SF-68).
    public static let defaults = AppPreferences()

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppPreferences.defaults
        version = (try? container.decodeIfPresent(Int.self, forKey: .version)) ?? Self.currentVersion
        decks = (try? container.decodeIfPresent(DeckPair<Deck>.self, forKey: .decks)) ?? defaults.decks
        mixer = (try? container.decodeIfPresent(Mixer.self, forKey: .mixer)) ?? defaults.mixer
        motor = (try? container.decodeIfPresent(MotorTimings.self, forKey: .motor)) ?? defaults.motor
    }

    /// Préférences correspondant à l'état courant du moteur (à enregistrer après un changement).
    public init(snapshot: EngineSnapshot) {
        self.init(
            decks: snapshot.decks.map { Deck(speed: $0.speed, pitch: $0.pitch, resistance: $0.resistance) },
            mixer: Mixer(crossfader: snapshot.mixer.crossfader, crossfaderCurve: snapshot.mixer.crossfaderCurve,
                         hamster: snapshot.mixer.hamster, lineFaders: snapshot.mixer.lineFaders),
            motor: snapshot.motorTimings
        )
    }

    /// Copie bornée aux plages de la spec ; une valeur non finie reprend la valeur par défaut.
    public func sanitized() -> AppPreferences {
        var copy = self
        copy.decks = decks.map { deck in
            Deck(speed: deck.speed,
                 pitch: deck.pitch.clamped(to: TurntableConstants.pitchRange, fallback: 0),
                 resistance: deck.resistance.clamped(to: 0...1, fallback: TurntableConstants.defaultResistance))
        }
        copy.mixer.crossfader = mixer.crossfader.clamped(to: 0...1, fallback: TurntableConstants.defaultCrossfader)
        copy.mixer.crossfaderCurve = mixer.crossfaderCurve.clamped(to: 0...1, fallback: TurntableConstants.defaultCrossfaderCurve)
        copy.mixer.lineFaders = mixer.lineFaders.map { $0.clamped(to: 0...1, fallback: TurntableConstants.defaultLineFader) }
        copy.motor = motor.clamped()
        return copy
    }

    /// Commandes qui appliquent ces préférences au moteur au lancement. Ne contient jamais de
    /// commande de moteur ni de chargement : aucune lecture automatique (SF-17, RM-10).
    public var engineCommands: [EngineCommand] {
        let values = sanitized()
        var commands: [EngineCommand] = []
        for deck in DeckID.allCases {
            commands.append(.speed(deck, values.decks[deck].speed))
            commands.append(.pitch(deck, values.decks[deck].pitch))
            commands.append(.resistance(deck, values.decks[deck].resistance))
            commands.append(.lineFader(deck, values.mixer.lineFaders[deck]))
        }
        commands.append(.crossfader(values.mixer.crossfader))
        commands.append(.crossfaderCurve(values.mixer.crossfaderCurve))
        commands.append(.hamster(values.mixer.hamster))
        commands.append(.startDuration(values.motor.startDuration))
        commands.append(.brakeDuration(values.motor.brakeDuration))
        commands.append(.slipmatCatchUp(values.motor.slipmatCatchUp))
        return commands
    }
}
