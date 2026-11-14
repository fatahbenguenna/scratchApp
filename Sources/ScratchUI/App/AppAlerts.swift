import Foundation
import ScratchCore
import ScratchLibrary
#if canImport(UIKit)
import UIKit
#endif

/// Alerte d'erreur à un seul bouton « OK » (UX §8.3). Après une erreur, la platine et la
/// bibliothèque sont inchangées (RM-48).
public struct AppAlert: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }

    /// Échec d'un import ou d'un chargement de « nom » (UX §8.3).
    @MainActor
    public static func failure(_ error: LibraryError, name: String) -> AppAlert {
        let quoted = DeckFormatting.quoted(name)
        switch error {
        case .insufficientStorage:
            return AppAlert(title: "Espace de stockage insuffisant",
                            message: "\(quoted) n'a pas pu être copié dans ScratchApp. Libérez de l'espace sur \(deviceName), puis réessayez.")
        case .unsupportedFormat:
            return AppAlert(title: "Format non pris en charge",
                            message: "\(quoted) n'est pas un fichier audio pris en charge. Formats acceptés : WAV, AIFF, MP3 et M4A (AAC ou ALAC).")
        case .protectedContent:
            return AppAlert(title: "Fichier protégé",
                            message: "\(quoted) est protégé contre la copie (DRM). Les fichiers protégés ne sont pas pris en charge.")
        case let .tooLong(duration):
            return AppAlert(title: "Son trop long",
                            message: "\(quoted) dure \(durationText(duration)). La durée maximale est de 10 minutes par son.")
        case .tooShort:
            return AppAlert(title: "Son trop court",
                            message: "\(quoted) dure moins de 50 millisecondes, la durée minimale acceptée.")
        case .corrupted:
            return AppAlert(title: "Fichier illisible",
                            message: "\(quoted) est vide ou endommagé. Aucun son n'a été ajouté à la bibliothèque.")
        case .writeFailed:
            return AppAlert(title: "Échec de l'import",
                            message: "\(quoted) n'a pas pu être copié dans ScratchApp. Réessayez.")
        case .notFound:
            return missingCopy(name: name)
        case .demoCannotBeDeleted:
            return AppAlert(title: "Suppression impossible", message: error.userMessage)
        }
    }

    /// Copie locale disparue ou modifiée au chargement (RM-48, D-11).
    public static func missingCopy(name: String) -> AppAlert {
        AppAlert(title: "Son introuvable",
                 message: "La copie de \(DeckFormatting.quoted(name)) a été supprimée ou modifiée en dehors de ScratchApp. Ce son a été retiré de la bibliothèque ; importez-le de nouveau.")
    }

    /// Le sélecteur n'a pas pu fournir le fichier choisi.
    static let pickerFailure = AppAlert(title: "Échec de l'import",
                                        message: "Le fichier choisi n'a pas pu être ouvert. Réessayez.")

    /// « cet iPhone », « cet iPad » ou « ce Mac » (UX §8.3).
    @MainActor
    static var deviceName: String {
        #if os(macOS)
        return "ce Mac"
        #elseif canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad ? "cet iPad" : "cet iPhone"
        #else
        return "cet appareil"
        #endif
    }

    /// Durée d'un son trop long : « 25 min 12 s », « 12 min », « 40 s ».
    static func durationText(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded(.down))) : 0
        let minutes = total / 60, rest = total % 60
        if minutes == 0 { return "\(rest) s" }
        return rest == 0 ? "\(minutes) min" : "\(minutes) min \(rest) s"
    }
}

/// Raison d'un chargement : elle décide du bandeau qui l'accompagne (UX §8.5).
enum LoadReason: Equatable, Sendable {
    /// Chargement depuis la bibliothèque (3.5).
    case library
    /// Nouvelle entrée créée par l'import.
    case imported
    /// Contenu déjà présent : l'entrée existante est chargée (SF-75).
    case duplicate
    /// Son de démonstration (SF-76).
    case demo
}

/// Confirmation de remplacement d'une platine chargée et active (SF-15, UX §8.4) : **Remplacer**
/// (par défaut, Retour) ou Annuler (Échap).
public struct ReplacementConfirmation: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let deck: DeckID
    /// Titre du son en place (« ancien »).
    public let currentTitle: String
    /// Entrée à charger (« nouveau » : l'entrée existante en cas de dédoublonnage).
    public let entry: LibraryEntry
    let reason: LoadReason

    init(deck: DeckID, currentTitle: String, entry: LibraryEntry, reason: LoadReason) {
        self.deck = deck
        self.currentTitle = currentTitle
        self.entry = entry
        self.reason = reason
    }

    public var title: String { "Remplacer le son de la platine \(deck.rawValue)\u{00A0}?" }

    public var message: String {
        let old = DeckFormatting.quoted(currentTitle), new = DeckFormatting.quoted(entry.title)
        return "La platine \(deck.rawValue) est en cours d'utilisation. \(old) sera remplacé par \(new) et la platine s'arrêtera. \(old) reste dans la bibliothèque."
    }
}

/// Textes des bandeaux (UX §8.5).
enum BannerText {
    static func duplicate(_ title: String) -> String {
        "Déjà dans la bibliothèque : \(DeckFormatting.quoted(title)) a été chargé."
    }

    static func addedWithoutReplacing(_ title: String) -> String {
        "\(DeckFormatting.quoted(title)) a été ajouté à la bibliothèque."
    }

    static let indexReset = "La bibliothèque était illisible : elle a été réinitialisée. Importez de nouveau vos sons."
    static let indexPartial = "Une partie de la bibliothèque était illisible : les sons concernés en ont été retirés. Importez-les de nouveau si besoin."

    /// Bandeau du lancement : l'index illisible prime sur les copies disparues (D-49).
    static func launch(recovery: LibraryIndexRecovery, removed: [LibraryEntry]) -> String? {
        switch recovery {
        case .reset: return indexReset
        case .partial: return indexPartial
        case .none: break
        }
        switch removed.count {
        case 0:
            return nil
        case 1:
            return "\(DeckFormatting.quoted(removed[0].title)) a été retiré de la bibliothèque : sa copie a été supprimée ou modifiée en dehors de ScratchApp."
        default:
            return "\(removed.count) sons ont été retirés de la bibliothèque : leurs copies ont été supprimées ou modifiées en dehors de ScratchApp."
        }
    }
}
