import Foundation
import ScratchCore

/// Bibliothèque locale persistante : copies dans `Documents/Banque de sons/`, index JSON dans
/// `Application Support/ScratchApp/library.json` (5.3 ; PRD 3.1, 3.2 ; architecture §8 ; ADR-10).
///
/// - **Index** (story 3.1) : lu au premier accès (`LibraryIndex`, lecture tolérante, index illisible
///   mis de côté), puis tenu en mémoire, seul maître, et réécrit d'un bloc de façon atomique à chaque
///   changement. Aucune opération n'attend (`await`) entre la lecture et l'écriture de l'index.
/// - **Réconciliation** (RM-48, D-11) : une entrée dont la copie est absente ou de taille différente
///   de `fileSize` est retirée par `reconcile()` (au lancement) et par `url(for:)` (avant chaque
///   chargement). Les fichiers de `Banque de sons` absents de l'index sont ignorés en V1.
/// - **Sûreté des chemins** : une copie est toujours cherchée directement dans `Banque de sons` ; un
///   nom vide, commençant par `.`, ou contenant `/` ou `..` (index forgé) n'y désigne aucune copie,
///   et aucun fichier hors de ce dossier n'est jamais lu ni supprimé.
/// - **Démo** : entrée synthétique en tête, jamais écrite dans l'index (SF-74, SF-76).
///
/// **Import (story 3.2) : pas encore implémenté**, `importFile` lève une erreur. À venir : copie
/// dans un fichier temporaire du même volume, SHA-256 en flux, dédoublonnage, sonde du décodeur,
/// suffixes anti-collision (`nom_2.ext`, D-12), contrôle préalable de l'espace, déplacement
/// atomique puis écriture de l'index.
public actor LibraryStore: LibraryStoring {
    public let locations: LibraryLocations
    private let decoder: any AudioDecoding
    private let index: LibraryIndex
    // Imported entries once the index has been read (never the demo); nil until the first access.
    private var imported: [LibraryEntry]?
    /// Copie mise de côté du dernier index illisible lu par ce magasin (diagnostic).
    private(set) var setAsideIndexURL: URL?

    public init(locations: LibraryLocations, decoder: any AudioDecoding) {
        self.locations = locations
        self.decoder = decoder
        self.index = LibraryIndex(url: locations.libraryIndexURL)
    }

    /// Le son de démonstration en tête, puis les imports du plus récent au plus ancien (à date
    /// égale : par titre, puis par identifiant).
    public var entries: [LibraryEntry] {
        [Self.demoEntry] + Self.displayOrder(loadedEntries())
    }

    public func reconcile() async -> [LibraryEntry] {
        let current = loadedEntries()
        let removed = current.filter { !copyIsIntact($0) }
        guard !removed.isEmpty else { return [] }
        let removedIDs = Set(removed.map(\.id))
        replaceEntries(with: current.filter { !removedIDs.contains($0.id) })
        return Self.displayOrder(removed)
    }

    public func importFile(at url: URL) async throws -> ImportResult {
        throw LibraryError.writeFailed(reason: "LibraryStore.importFile n'est pas encore implémenté")
    }

    /// Supprime la copie de `Banque de sons`, puis l'entrée (RM-49). Un nom de copie forgé ne
    /// désigne aucun fichier : seule l'entrée est retirée. Lève `writeFailed` si la copie existe
    /// mais ne peut pas être supprimée (l'entrée est alors conservée).
    public func delete(id: UUID) async throws {
        if id == LibraryEntry.demoID { throw LibraryError.demoCannotBeDeleted }
        var current = loadedEntries()
        guard let position = current.firstIndex(where: { $0.id == id }) else { throw LibraryError.notFound }
        if let copy = copyURL(for: current[position]), let type = itemType(at: copy),
           type == .typeRegular || type == .typeSymbolicLink {
            do {
                try FileManager.default.removeItem(at: copy)
            } catch {
                throw LibraryError.writeFailed(reason: "suppression de \(copy.lastPathComponent) : \(error)")
            }
        }
        current.remove(at: position)
        replaceEntries(with: current)
    }

    public func url(for id: UUID) async throws -> URL {
        guard id != LibraryEntry.demoID else { throw LibraryError.notFound }
        var current = loadedEntries()
        guard let position = current.firstIndex(where: { $0.id == id }) else { throw LibraryError.notFound }
        if copyIsIntact(current[position]), let copy = copyURL(for: current[position]) {
            return copy
        }
        current.remove(at: position)
        replaceEntries(with: current)
        throw LibraryError.notFound
    }

    // MARK: - Index

    private static let demoEntry = LibraryEntry.demo(title: DemoSound.title, duration: DemoSound.duration)

    /// Entrées importées, l'index étant lu au premier appel.
    private func loadedEntries() -> [LibraryEntry] {
        if let imported { return imported }
        let result = index.load()
        imported = result.entries
        if let url = result.setAsideURL { setAsideIndexURL = url }
        return result.entries
    }

    /// Remplace les entrées en mémoire, puis réécrit l'index. Un échec d'écriture est sans effet sur
    /// la liste en mémoire : l'index sur disque garde au pire des entrées dont la copie a disparu,
    /// que la réconciliation suivante retire (RM-48).
    private func replaceEntries(with newEntries: [LibraryEntry]) {
        imported = newEntries
        try? index.save(newEntries)
    }

    static func displayOrder(_ entries: [LibraryEntry]) -> [LibraryEntry] {
        entries.sorted { lhs, rhs in
            if lhs.importedAt != rhs.importedAt { return lhs.importedAt > rhs.importedAt }
            if lhs.title != rhs.title { return lhs.title < rhs.title }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    // MARK: - Copies

    /// Un nom de copie ne désigne un fichier que s'il ne peut pas sortir de `Banque de sons`.
    static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix(".") && !name.contains("/") && !name.contains("\0")
            && name.range(of: "..") == nil
    }

    /// URL de la copie d'une entrée, directement dans `Banque de sons`, ou `nil` si son nom est forgé.
    private func copyURL(for entry: LibraryEntry) -> URL? {
        guard Self.isSafeFileName(entry.fileName) else { return nil }
        let directory = locations.soundBankDirectory
        let url = directory.appendingPathComponent(entry.fileName, isDirectory: false)
        guard url.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path
        else { return nil }
        return url
    }

    /// Type de l'élément à `url`, sans suivre un lien symbolique ; `nil` s'il n'existe pas.
    private func itemType(at url: URL) -> FileAttributeType? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return attributes[.type] as? FileAttributeType
    }

    /// La copie existe, est un fichier ordinaire et a la taille enregistrée (RM-48, IC-10).
    private func copyIsIntact(_ entry: LibraryEntry) -> Bool {
        guard let copy = copyURL(for: entry),
              let attributes = try? FileManager.default.attributesOfItem(atPath: copy.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber
        else { return false }
        return size.int64Value == entry.fileSize
    }
}
