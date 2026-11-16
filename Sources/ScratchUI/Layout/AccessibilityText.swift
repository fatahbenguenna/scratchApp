import ScratchCore

/// Textes parlés de l'écran principal (story 5.3 CA 1 ; UX §8.1, §8.6, §11.2) : source unique des
/// formats VoiceOver, testée commande par commande.
///
/// Les nombres suivent l'UX §8.1 : virgule décimale, espace insécable avant « % », signe moins
/// typographique ; le temps se dit « 1 minute 12,3 secondes ».
enum AccessibilityText {
    // MARK: Nombres

    /// « 12,3 secondes », « 1 minute 12,3 secondes », « moins 1,2 seconde » (amorce).
    static func time(_ seconds: Double) -> String {
        DeckFormatting.spokenTime(tenths: DeckFormatting.tenths(seconds))
    }

    /// Pourcentage entier : « 50 % ».
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))\u{00A0}%"
    }

    // MARK: Platine

    /// CUE : « CUE à 12,3 secondes », ou « aucun CUE, retour au début » (UX §5.6).
    static func cue(_ seconds: Double?) -> String {
        guard let seconds else { return "aucun CUE, retour au début" }
        return "CUE à " + time(seconds)
    }

    /// Aperçu : valeur de l'en-tête suivie du CUE, « …, CUE à 4 secondes » ou « …, aucun CUE ».
    static func overview(header: String, isLoaded: Bool, cue: Double?) -> String {
        guard isLoaded else { return header }
        return header + ", " + (cue.map { "CUE à " + time($0) } ?? "aucun CUE")
    }

    // MARK: Table de mixage

    /// Crossfader : « 50 %, centre », « butée gauche, voie A » (butées physiques, D-09).
    static func crossfader(_ position: Double, leftDeck: DeckID, rightDeck: DeckID) -> String {
        if position <= 0 { return "butée gauche, voie \(leftDeck.rawValue)" }
        if position >= 1 { return "butée droite, voie \(rightDeck.rawValue)" }
        let text = percent(position)
        return abs(position - 0.5) < 0.005 ? text + ", centre" : text
    }

    /// Courbe : « coupure franche », « douce » ou « 60 % » (UX §5.13).
    static func curve(_ value: Double) -> String {
        if value >= 1 { return "coupure franche" }
        if value <= 0 { return "douce" }
        return percent(value)
    }

    /// Interrupteur : « activé » ou « désactivé ».
    static func toggle(_ isOn: Bool) -> String { isOn ? "activé" : "désactivé" }

    // MARK: Annonces (UX §8.6)

    /// « Platine A : « voix_funk.wav » chargé, 3 minutes 45 secondes. »
    static func loaded(deck: DeckID, title: String, duration: Double) -> String {
        "Platine \(deck.rawValue)\u{00A0}: \(DeckFormatting.quoted(title)) chargé, \(time(duration))."
    }

    /// « Point CUE mémorisé à 12,3 secondes »
    static func setCue(at seconds: Double) -> String { "Point CUE mémorisé à " + time(seconds) }

    /// « Aucun son chargé sur la platine A. Importez un fichier ou chargez la démo. »
    static func emptyStart(deck: DeckID) -> String {
        "Aucun son chargé sur la platine \(deck.rawValue). Importez un fichier ou chargez la démo."
    }

    /// « Platine A vidée. » (son supprimé de la bibliothèque, 3.5)
    static func cleared(deck: DeckID) -> String { "Platine \(deck.rawValue) vidée." }
}

/// Ordre de lecture VoiceOver dans une platine (UX §11.3) : en-tête et Importer, disque, aperçu,
/// transport, pitch, résistance, quel que soit l'arrangement (colonne ou bande). Priorités décroissantes
/// pour `accessibilitySortPriority`.
enum DeckReadingOrder {
    static let header: Double = 6
    static let disc: Double = 5
    static let overview: Double = 4
    static let transport: Double = 3
    static let pitch: Double = 2
    static let resistance: Double = 1
}
