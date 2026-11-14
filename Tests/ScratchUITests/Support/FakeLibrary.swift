import Foundation
import ScratchCore
import ScratchLibrary

/// Bibliothèque réelle (`LibraryStore`) dans un dossier temporaire unique, pour les tests de
/// l'`AppModel` (story 6.1, CA 9) : les parcours d'import, de dédoublonnage, de réconciliation et
/// de copie disparue passent par le vrai magasin de 3.1 et 3.2, avec le décodeur factice.
struct TemporaryLibrary {
    let root: URL
    let locations: LibraryLocations

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("appmodel-\(UUID().uuidString)")
        locations = LibraryLocations(documentsDirectory: root.appendingPathComponent("Documents", isDirectory: true),
                                     supportDirectory: root.appendingPathComponent("Support", isDirectory: true))
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
    }

    /// Fichiers d'origine, hors du bac à sable de l'app.
    var sources: URL { root.appendingPathComponent("Fichiers", isDirectory: true) }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func makeStore(decoder: any AudioDecoding, capacity: Int64? = nil) -> LibraryStore {
        LibraryStore(locations: locations, decoder: decoder, capacity: FixedCapacity(bytes: capacity))
    }

    /// WAV d'origine nommé `name` (dans un sous-dossier pour deux homonymes).
    func source(_ name: String, seconds: Double = 1, seed: UInt32 = 1, folder: String? = nil) throws -> URL {
        var directory = sources
        if let folder { directory = directory.appendingPathComponent(folder, isDirectory: true) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try TestWAV.data(seconds: seconds, seed: seed).write(to: url)
        return url
    }

    func copyURL(_ fileName: String) -> URL {
        locations.soundBankDirectory.appendingPathComponent(fileName)
    }
}

/// Espace libre fixe (ou inconnu avec `nil`).
struct FixedCapacity: StorageCapacityProviding {
    let bytes: Int64?

    func availableCapacity(forWritingAt url: URL) -> Int64? { bytes }
}
