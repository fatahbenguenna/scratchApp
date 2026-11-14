import Foundation
import ScratchCore

/// Bibliothèque locale persistante : copies dans `Documents/Banque de sons/`, index JSON dans
/// `Application Support/ScratchApp/library.json` (5.3 ; architecture §8).
///
/// **Squelette (story EP3, Hugo) : ne contient que le son de démonstration et refuse les imports.**
/// À implémenter selon le contrat `LibraryStoring` : chargement de l'index au premier accès
/// (index illisible → sauvegarde `library.json.corrupt` et index vide), import en fichier
/// temporaire puis déplacement atomique, dédoublonnage par SHA-256, suffixes anti-collision,
/// écriture atomique de l'index, suppression de la copie seule.
public actor LibraryStore: LibraryStoring {
    public let locations: LibraryLocations
    private let validator: any AudioFileValidating

    public init(locations: LibraryLocations, validator: any AudioFileValidating) {
        self.locations = locations
        self.validator = validator
    }

    public var entries: [LibraryEntry] {
        [LibraryEntry.demo(title: DemoSound.title, duration: DemoSound.duration)]
    }

    public func importFile(at url: URL) async throws -> ImportResult {
        throw LibraryError.writeFailed(reason: "LibraryStore.importFile n'est pas encore implémenté")
    }

    public func delete(id: UUID) async throws {
        if id == LibraryEntry.demoID { throw LibraryError.demoCannotBeDeleted }
        throw LibraryError.notFound
    }

    public func url(for id: UUID) async -> URL? {
        nil
    }
}
