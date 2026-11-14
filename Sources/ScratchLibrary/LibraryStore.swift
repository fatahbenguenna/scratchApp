import Foundation
import ScratchCore

/// Bibliothèque locale persistante : copies dans `Documents/Banque de sons/`, index JSON dans
/// `Application Support/ScratchApp/library.json` (5.3 ; PRD 3.1, 3.2 ; architecture §8).
///
/// **Squelette (stories 3.1 et 3.2, Hugo) : ne contient que le son de démonstration et refuse les
/// imports.** À implémenter selon le contrat `LibraryStoring` : chargement de l'index au premier
/// accès (index illisible → mis de côté, index vide, erreur signalée), réconciliation (copie absente
/// ou de taille différente → entrée écartée), import en fichier temporaire du même volume puis
/// déplacement atomique, SHA-256 en flux, dédoublonnage, sonde du décodeur, suffixes anti-collision
/// (`nom-2.ext`), contrôle préalable de l'espace par un fournisseur injectable, écriture atomique de
/// l'index, suppression de la copie seule.
public actor LibraryStore: LibraryStoring {
    public let locations: LibraryLocations
    private let decoder: any AudioDecoding

    public init(locations: LibraryLocations, decoder: any AudioDecoding) {
        self.locations = locations
        self.decoder = decoder
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

    public func url(for id: UUID) async throws -> URL {
        throw LibraryError.notFound
    }
}
