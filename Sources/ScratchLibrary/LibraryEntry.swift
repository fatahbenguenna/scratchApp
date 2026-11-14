import Foundation

/// Entrée de la bibliothèque locale (SF-74, RM-58 ; architecture §5.2).
///
/// Format persistant (`library.json`) : les noms de propriétés sont les clés JSON et ne changent
/// pas sans migration. Les dates sont encodées en ISO 8601.
public struct LibraryEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// Origine d'un son (SF-74, SF-55). `microphone` et `mix` sont réservés aux options P2 (10.3, 10.5).
    public enum Origin: String, Codable, Sendable, CaseIterable {
        case imported
        case demo
        case microphone
        case mix
    }

    /// Identifiant interne stable : ne change jamais, même après un renommage (RM-58).
    public let id: UUID
    /// Empreinte SHA-256 du contenu, en hexadécimal minuscule (64 caractères) : dédoublonnage
    /// (SF-75) et, en P2, association des pointeurs (10.4). Vide pour le son de démonstration.
    public var contentHash: String
    /// Nom du fichier de la copie dans `Documents/Banque de sons/` (avec suffixe anti-collision
    /// éventuel, SF-60). Vide pour le son de démonstration, qui n'a pas de fichier.
    public var fileName: String
    /// Titre affiché.
    public var title: String
    /// Durée en secondes.
    public var duration: Double
    /// Date d'import (ou de création).
    public var importedAt: Date
    public var origin: Origin

    public init(id: UUID = UUID(), contentHash: String, fileName: String, title: String,
                duration: Double, importedAt: Date, origin: Origin) {
        self.id = id
        self.contentHash = contentHash
        self.fileName = fileName
        self.title = title
        self.duration = duration
        self.importedAt = importedAt
        self.origin = origin
    }

    /// Le son peut être supprimé de la bibliothèque (le son de démonstration ne peut pas l'être, SF-74).
    public var isDeletable: Bool { origin != .demo }

    /// Identifiant fixe du son de démonstration.
    public static let demoID = UUID(uuidString: "5C2A7C40-DE30-4D3A-9B1E-000000000001")!

    /// Entrée du son de démonstration : toujours en tête de liste, jamais persistée, sans fichier.
    public static func demo(title: String, duration: Double) -> LibraryEntry {
        LibraryEntry(id: demoID, contentHash: "", fileName: "", title: title, duration: duration,
                     importedAt: Date(timeIntervalSince1970: 0), origin: .demo)
    }
}

/// Résultat d'un import (SF-02, SF-75).
public enum ImportResult: Equatable, Sendable {
    /// Nouvelle copie créée et ajoutée à l'index.
    case added(LibraryEntry)
    /// Contenu identique déjà présent (même SHA-256) : aucune copie, l'entrée existante est réutilisée.
    case existing(LibraryEntry)

    public var entry: LibraryEntry {
        switch self {
        case let .added(entry), let .existing(entry): return entry
        }
    }

    public var isNew: Bool {
        if case .added = self { return true }
        return false
    }
}
