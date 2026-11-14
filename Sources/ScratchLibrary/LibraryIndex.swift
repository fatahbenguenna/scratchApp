import Foundation
import ScratchCore

/// Index persistant de la bibliothèque : `Application Support/ScratchApp/library.json` (5.3 ;
/// architecture §8 ; ADR-10).
///
/// - **Format** : `{"version": 1, "entries": [LibraryEntry]}`, clés triées, dates ISO 8601 à la
///   seconde (format figé par `LibraryContractsTests`). Le son de démonstration n'y figure jamais.
/// - **Écriture atomique** : fichier temporaire puis remplacement (`Data.write(options: .atomic)`) ;
///   un index n'est jamais à moitié écrit.
/// - **Lecture tolérante** (NFR12) : un document illisible, sans version ou d'une version inconnue
///   est déplacé vers `library.json.corrupt` (`library.json.corrupt_2`, `_3`… si ce nom est pris,
///   sans jamais écraser un document déjà mis de côté) et la bibliothèque repart vide. Une entrée
///   isolée illisible, en double ou qui se présente comme la démo est ignorée ; le document
///   d'origine est alors copié de la même façon, pour qu'aucune donnée ne soit perdue.
struct LibraryIndex: Sendable {
    /// Version du format écrit et seule version lue.
    static let currentVersion = 1

    /// Emplacement de `library.json`.
    let url: URL

    /// Résultat d'une lecture de l'index.
    struct LoadResult: Equatable {
        /// Entrées lues (jamais la démo), dans l'ordre du document.
        var entries: [LibraryEntry]
        /// Copie mise de côté du document lu, s'il était illisible en tout ou en partie.
        var setAsideURL: URL?
    }

    /// Lit l'index. Ne lève jamais d'erreur : un index absent donne une liste vide.
    func load() -> LoadResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return LoadResult(entries: [], setAsideURL: nil) }
        guard let data = try? Data(contentsOf: url),
              let document = try? Self.makeDecoder().decode(StoredDocument.self, from: data),
              document.version == Self.currentVersion
        else {
            return LoadResult(entries: [], setAsideURL: setAside(keepingOriginal: false))
        }
        var seen: Set<UUID> = []
        var entries: [LibraryEntry] = []
        for candidate in document.entries {
            guard let entry = candidate.entry, entry.origin != .demo, entry.id != LibraryEntry.demoID,
                  seen.insert(entry.id).inserted
            else { continue }
            entries.append(entry)
        }
        let skippedSome = entries.count != document.entries.count
        return LoadResult(entries: entries, setAsideURL: skippedSome ? setAside(keepingOriginal: true) : nil)
    }

    /// Écrit l'index de façon atomique (le son de démonstration est toujours exclu).
    /// Lève `LibraryError.writeFailed` si le dossier ou le fichier ne peut pas être écrit.
    func save(_ entries: [LibraryEntry]) throws {
        let stored = entries.filter { $0.origin != .demo && $0.id != LibraryEntry.demoID }
        do {
            let data = try Self.makeEncoder().encode(Document(version: Self.currentVersion, entries: stored))
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            throw LibraryError.writeFailed(reason: "library.json : \(error)")
        }
    }

    // MARK: - Format

    private struct Document: Encodable {
        let version: Int
        let entries: [LibraryEntry]
    }

    private struct StoredDocument: Decodable {
        let version: Int
        let entries: [TolerantEntry]
    }

    /// Entrée décodée sans faire échouer le document entier.
    private struct TolerantEntry: Decodable {
        let entry: LibraryEntry?

        init(from decoder: Decoder) throws {
            entry = try? LibraryEntry(from: decoder)
        }
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    // MARK: - Set-aside

    /// Déplace (ou copie) le document vers le premier nom libre `library.json.corrupt[_n]`.
    /// Renvoie l'emplacement obtenu, ou `nil` si l'opération a échoué.
    private func setAside(keepingOriginal: Bool) -> URL? {
        let fileManager = FileManager.default
        let directory = url.deletingLastPathComponent()
        let baseName = url.lastPathComponent + ".corrupt"
        var destination = directory.appendingPathComponent(baseName, isDirectory: false)
        var suffix = 2
        while (try? fileManager.attributesOfItem(atPath: destination.path)) != nil {
            destination = directory.appendingPathComponent("\(baseName)_\(suffix)", isDirectory: false)
            suffix += 1
        }
        do {
            if keepingOriginal {
                try fileManager.copyItem(at: url, to: destination)
            } else {
                try fileManager.moveItem(at: url, to: destination)
            }
            return destination
        } catch {
            return nil
        }
    }
}
