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
/// - **Import** (story 3.2, voir `importFile(at:)`). Une étape ne commence que si la précédente a
///   réussi :
///   1. contrôle préalable de l'espace libre ;
///   2. copie en flux dans `Application Support/ScratchApp/Imports/<UUID>.<ext>`, avec calcul de
///      l'empreinte SHA-256 pendant la copie ;
///   3. dédoublonnage (SF-75) ;
///   4. sonde du décodeur ;
///   5. nouveau dédoublonnage, car d'autres imports ont pu aboutir pendant la sonde ;
///   6. nom de copie libre (`nom_2.ext`, D-12) ;
///   7. déplacement atomique dans `Banque de sons` ;
///   8. écriture atomique de l'index.
///
///   Sur toute erreur, le temporaire et la copie sont supprimés, et l'index comme la liste restent
///   inchangés (RM-48). Les temporaires orphelins sont purgés au premier accès. La copie se fait
///   sur l'acteur : deux imports simultanés sont sérialisés, sauf pendant la sonde.
public actor LibraryStore: LibraryStoring {
    public let locations: LibraryLocations
    private let decoder: any AudioDecoding
    private let capacity: any StorageCapacityProviding
    private let chunkWriter: any ImportChunkWriting
    private let now: @Sendable () -> Date
    private let index: LibraryIndex
    // Imported entries once the index has been read (never the demo); nil until the first access.
    private var imported: [LibraryEntry]?
    /// Copie mise de côté du dernier index illisible lu par ce magasin (diagnostic ; 6.1, D-49).
    private(set) var setAsideIndexURL: URL?
    // Outcome of the index read at the first access (D-49).
    private var recovery = LibraryIndexRecovery.none

    /// Espace exigé en plus de la taille du fichier : 10 Mio, ou 5 % de la taille si c'est plus.
    static let storageMargin: Int64 = 10 * 1_048_576

    /// - Parameter capacity: fournisseur de l'espace libre (par défaut, celui du système).
    public init(locations: LibraryLocations, decoder: any AudioDecoding,
                capacity: any StorageCapacityProviding = SystemStorageCapacity()) {
        self.init(locations: locations, decoder: decoder, capacity: capacity, chunkWriter: FileHandleChunkWriter(),
                  now: { Date() })
    }

    /// Magasin dont l'écriture des temporaires et l'horloge sont injectées (tests).
    init(locations: LibraryLocations, decoder: any AudioDecoding, capacity: any StorageCapacityProviding,
         chunkWriter: any ImportChunkWriting, now: @escaping @Sendable () -> Date) {
        self.locations = locations
        self.decoder = decoder
        self.capacity = capacity
        self.chunkWriter = chunkWriter
        self.now = now
        self.index = LibraryIndex(url: locations.libraryIndexURL)
    }

    /// Le son de démonstration en tête, puis les imports du plus récent au plus ancien (à date
    /// égale : par titre, puis par identifiant).
    public var entries: [LibraryEntry] {
        [Self.demoEntry] + Self.displayOrder(loadedEntries())
    }

    /// Issue de la lecture de l'index (D-49, story 6.1 CA 10) : `.reset` si un index illisible a été
    /// mis de côté, `.partial` si des entrées ont été ignorées, `.none` sinon. L'index est lu au
    /// premier accès ; grâce au correctif #51, un même document n'est signalé qu'à un seul lancement.
    /// Hors du contrat `LibraryStoring` : `ScratchAppMain` la transmet à l'`AppModel`.
    public var indexRecovery: LibraryIndexRecovery {
        _ = loadedEntries()
        return recovery
    }

    public func reconcile() async -> [LibraryEntry] {
        let current = loadedEntries()
        let removed = current.filter { !copyIsIntact($0) }
        guard !removed.isEmpty else { return [] }
        let removedIDs = Set(removed.map(\.id))
        replaceEntries(with: current.filter { !removedIDs.contains($0.id) })
        return Self.displayOrder(removed)
    }

    /// Copie `source` dans `Banque de sons` et l'ajoute à l'index (SF-02, RM-47, RM-48, SF-75, D-12).
    ///
    /// La source n'est que lue : ni son contenu ni sa date ne changent, et aucun chemin externe n'est
    /// conservé. L'accès à portée de sécurité est ouvert et refermé par l'appelant (6.1).
    ///
    /// Erreurs, toutes sans trace (pas de copie, ni d'entrée, ni de changement d'index) :
    /// - espace insuffisant, au contrôle préalable ou à l'écriture → `insufficientStorage` ;
    /// - erreur de la sonde (`unsupportedFormat`, `protectedContent`, `corrupted`, `tooLong`,
    ///   `tooShort`) → propagée ;
    /// - source introuvable ou illisible, autre échec d'écriture → `writeFailed(reason:)` ;
    /// - tâche annulée → `CancellationError`.
    public func importFile(at source: URL) async throws -> ImportResult {
        _ = loadedEntries() // first access: index read, orphan temporaries purged
        let sourceSize = try Self.sourceFileSize(source)
        try checkCapacity(forFileOfSize: sourceSize)
        let copy = try copyToTemporary(from: source)
        do {
            if let existing = intactEntry(withContentHash: copy.contentHash) {
                Self.removeTemporary(copy.url)
                return .existing(existing)
            }
            try Task.checkCancellation()
            let info: AudioFileInfo
            do {
                info = try await decoder.probe(url: copy.url)
            } catch {
                throw Self.probeError(error)
            }
            // Other imports may have completed while the probe was suspended: check again.
            if let existing = intactEntry(withContentHash: copy.contentHash) {
                Self.removeTemporary(copy.url)
                return .existing(existing)
            }
            return .added(try commit(copy, sourceName: source.lastPathComponent, info: info))
        } catch {
            Self.removeTemporary(copy.url)
            throw error
        }
    }

    /// Supprime la copie de `Banque de sons`, puis l'entrée (RM-49). Un nom de copie forgé ne
    /// désigne aucun fichier : seule l'entrée est retirée. Lève `writeFailed` si la copie existe
    /// mais ne peut pas être supprimée (l'entrée est alors conservée).
    public func delete(id: UUID) async throws {
        if id == LibraryEntry.demoID { throw LibraryError.demoCannotBeDeleted }
        var current = loadedEntries()
        guard let position = current.firstIndex(where: { $0.id == id }) else { throw LibraryError.notFound }
        if let copy = copyURL(for: current[position]), let type = Self.itemType(at: copy),
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
        purgeImportTemporaries()
        let result = index.load()
        imported = result.entries
        if let url = result.setAsideURL { setAsideIndexURL = url }
        recovery = result.recovery
        if result.recovery == .partial {
            // The original is already set aside: rewrite the cleaned index so that it is set aside once (#51).
            try? index.save(result.entries)
        }
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

    // MARK: - Import

    /// Copie temporaire d'une source, avec son empreinte et sa taille.
    private struct TemporaryCopy {
        let url: URL
        let contentHash: String
        let size: Int64
    }

    /// Espace exigé pour importer un fichier de `size` octets.
    static func requiredCapacity(forFileOfSize size: Int64) -> Int64 {
        size + max(storageMargin, size / 20)
    }

    private static func sourceFileSize(_ source: URL) throws -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: source.resolvingSymlinksInPath().path)
        else { throw LibraryError.writeFailed(reason: "source introuvable ou inaccessible : \(source.lastPathComponent)") }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw LibraryError.unsupportedFormat }
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func checkCapacity(forFileOfSize size: Int64) throws {
        let directory = locations.supportDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let available = capacity.availableCapacity(forWritingAt: directory) else { return }
        if available < Self.requiredCapacity(forFileOfSize: size) { throw LibraryError.insufficientStorage }
    }

    /// Copie la source par blocs de 1 Mio dans `Imports/`, en calculant son empreinte au passage.
    private func copyToTemporary(from source: URL) throws -> TemporaryCopy {
        let fileManager = FileManager.default
        let directory = locations.importsDirectory
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw LibraryError.writing(error, context: "dossier Imports")
        }
        let input: FileHandle
        do {
            input = try FileHandle(forReadingFrom: source)
        } catch {
            throw LibraryError.writeFailed(reason: "source illisible : \(error)")
        }
        defer { try? input.close() }
        let pathExtension = source.pathExtension
        let temporary = directory.appendingPathComponent(
            pathExtension.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(pathExtension)", isDirectory: false)
        guard fileManager.createFile(atPath: temporary.path, contents: nil) else {
            throw LibraryError.writeFailed(reason: "fichier temporaire impossible à créer")
        }
        do {
            let output = try FileHandle(forWritingTo: temporary)
            defer { try? output.close() }
            var hasher = SHA256()
            var size: Int64 = 0
            var reachedEnd = false
            while !reachedEnd {
                try ContentHasher.withLocalAutoreleasePool {
                    let chunk: Data?
                    do {
                        chunk = try input.read(upToCount: ContentHasher.readChunkSize)
                    } catch {
                        throw LibraryError.writeFailed(reason: "source illisible : \(error)")
                    }
                    guard let chunk, !chunk.isEmpty else {
                        reachedEnd = true
                        return
                    }
                    hasher.update(chunk)
                    try chunkWriter.write(chunk, to: output)
                    size += Int64(chunk.count)
                }
            }
            try output.synchronize()
            return TemporaryCopy(url: temporary, contentHash: SHA256.hexString(hasher.finalize()), size: size)
        } catch {
            Self.removeTemporary(temporary)
            throw LibraryError.writing(error, context: "copie temporaire")
        }
    }

    /// Entrée de même contenu dont la copie est intacte (SF-75).
    private func intactEntry(withContentHash contentHash: String) -> LibraryEntry? {
        loadedEntries().first { $0.contentHash == contentHash && copyIsIntact($0) }
    }

    /// Nom libre, déplacement atomique, puis index. Aucune attente : aucun autre import ne s'intercale.
    private func commit(_ copy: TemporaryCopy, sourceName: String, info: AudioFileInfo) throws -> LibraryEntry {
        let fileManager = FileManager.default
        let bank = locations.soundBankDirectory
        do {
            try fileManager.createDirectory(at: bank, withIntermediateDirectories: true)
        } catch {
            throw LibraryError.writing(error, context: "dossier Banque de sons")
        }
        // An entry of the same content whose copy has disappeared is replaced (3.1 reconciliation).
        let kept = loadedEntries().filter { $0.contentHash != copy.contentHash || copyIsIntact($0) }
        let takenNames = Set(kept.map { CopyNaming.comparisonKey($0.fileName) })
        let name = CopyNaming.availableName(for: CopyNaming.sanitizedName(sourceName)) { candidate in
            takenNames.contains(CopyNaming.comparisonKey(candidate))
                || Self.itemType(at: bank.appendingPathComponent(candidate, isDirectory: false)) != nil
        }
        guard Self.isSafeFileName(name) else { throw LibraryError.writeFailed(reason: "nom de copie refusé : \(name)") }
        let destination = bank.appendingPathComponent(name, isDirectory: false)
        do {
            try fileManager.moveItem(at: copy.url, to: destination)
        } catch {
            throw LibraryError.writing(error, context: "déplacement de la copie")
        }
        let entry = LibraryEntry(id: UUID(), contentHash: copy.contentHash, fileName: name, fileSize: copy.size,
                                 title: name, duration: info.duration, importedAt: Self.wholeSecond(now()),
                                 origin: .imported)
        let updated = kept + [entry]
        do {
            try index.save(updated)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        imported = updated
        return entry
    }

    /// Erreurs de la sonde : celles du contrat et l'annulation passent ; toute autre erreur
    /// devient `unsupportedFormat` (R-11 : jamais de son muet accepté).
    private static func probeError(_ error: Error) -> Error {
        if error is LibraryError || error is CancellationError { return error }
        return LibraryError.unsupportedFormat
    }

    /// Dates de l'index à la seconde (ISO 8601 sans fraction) : l'entrée en mémoire égale l'entrée relue.
    static func wholeSecond(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    private static func removeTemporary(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Supprime les temporaires laissés par un import interrompu (arrêt de l'app pendant la copie).
    private func purgeImportTemporaries() {
        let fileManager = FileManager.default
        let directory = locations.importsDirectory
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
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
    private static func itemType(at url: URL) -> FileAttributeType? {
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

// MARK: - Temporary file writing

/// Écriture d'un bloc du fichier temporaire d'import ; point d'injection des tests (disque plein
/// ou erreur d'écriture simulés).
protocol ImportChunkWriting: Sendable {
    func write(_ chunk: Data, to handle: FileHandle) throws
}

/// Écriture réelle, par `FileHandle`.
struct FileHandleChunkWriter: ImportChunkWriting {
    func write(_ chunk: Data, to handle: FileHandle) throws {
        try handle.write(contentsOf: chunk)
    }
}
