import Foundation
import ScratchCore
import XCTest
@testable import ScratchLibrary

/// Dossiers temporaires uniques (`Documents` et `Application Support/ScratchApp` séparés) pour un
/// test ; les entrées sont écrites directement dans `library.json` et `Banque de sons` (l'import
/// arrive en 3.2).
struct LibrarySandbox {
    let root: URL
    let locations: LibraryLocations

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("scratchlibrary-\(UUID().uuidString)")
        locations = LibraryLocations(
            documentsDirectory: root.appendingPathComponent("Documents", isDirectory: true),
            supportDirectory: root.appendingPathComponent("Application Support/ScratchApp", isDirectory: true))
        try FileManager.default.createDirectory(at: locations.soundBankDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: locations.supportDirectory, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Décodeur factice : la sonde et le décodage refusent tout (aucun fichier n'est importé ici).
    struct RejectingDecoder: AudioDecoding {
        func probe(url: URL) async throws -> AudioFileInfo { throw LibraryError.unsupportedFormat }
        func decode(url: URL, title: String) async throws -> AudioClip { throw LibraryError.unsupportedFormat }
    }

    func makeStore() -> LibraryStore {
        LibraryStore(locations: locations, decoder: RejectingDecoder())
    }

    func entry(id: UUID = UUID(), fileName: String, size: Int64, title: String? = nil,
               importedAt: Date = Date(timeIntervalSince1970: 1_794_000_000)) -> LibraryEntry {
        LibraryEntry(id: id, contentHash: String(repeating: "0", count: 64), fileName: fileName, fileSize: size,
                     title: title ?? fileName, duration: 2.5, importedAt: importedAt, origin: .imported)
    }

    func copyURL(_ fileName: String) -> URL {
        locations.soundBankDirectory.appendingPathComponent(fileName)
    }

    /// Écrit une copie de `size` octets dans `Banque de sons`.
    @discardableResult
    func writeCopy(_ fileName: String, size: Int) throws -> URL {
        let url = copyURL(fileName)
        try Data(repeating: 0x5A, count: size).write(to: url)
        return url
    }

    /// Écrit l'index avec un encodeur propre au test (indépendant de `LibraryIndex`).
    func writeIndex(_ entries: [LibraryEntry]) throws {
        struct Document: Encodable { let version: Int; let entries: [LibraryEntry] }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Document(version: 1, entries: entries)).write(to: locations.libraryIndexURL)
    }

    func writeRawIndex(_ contents: String) throws {
        try Data(contents.utf8).write(to: locations.libraryIndexURL)
    }

    func readIndexDocument() throws -> [String: Any] {
        let data = try Data(contentsOf: locations.libraryIndexURL)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// Identifiants présents dans `library.json`.
    func indexedIDs() throws -> [UUID] {
        let entries = try XCTUnwrap(readIndexDocument()["entries"] as? [[String: Any]])
        return entries.compactMap { ($0["id"] as? String).flatMap(UUID.init(uuidString:)) }
    }
}

final class LibraryStoreTests: XCTestCase {
    private var sandbox: LibrarySandbox!
    private let demo = LibraryEntry.demo(title: DemoSound.title, duration: DemoSound.duration)

    override func setUpWithError() throws {
        sandbox = try LibrarySandbox()
    }

    override func tearDownWithError() throws {
        sandbox.remove()
    }

    private func makeStore() -> LibraryStore {
        sandbox.makeStore()
    }

    private func assertThrows(_ expected: LibraryError, file: StaticString = #filePath, line: UInt = #line,
                              _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? LibraryError, expected, file: file, line: line)
        }
    }

    /// SF-74 : la démo est en tête, sans fichier, et ne peut pas être supprimée.
    func testDemoIsFirstAndProtected_SF74() async throws {
        let store = makeStore()
        let entries = await store.entries
        XCTAssertEqual(entries.first?.id, LibraryEntry.demoID)
        XCTAssertEqual(entries.first?.title, DemoSound.title)
        do {
            try await store.delete(id: LibraryEntry.demoID)
            XCTFail("the demo must not be deletable")
        } catch {
            XCTAssertEqual(error as? LibraryError, .demoCannotBeDeleted)
        }
        do {
            _ = try await store.url(for: LibraryEntry.demoID)
            XCTFail("the demo has no local copy")
        } catch {
            XCTAssertEqual(error as? LibraryError, .notFound)
        }
    }

    func testDemoClipMatchesItsContract_SF76() {
        let clip = DemoSound.makeClip()
        XCTAssertEqual(clip.title, DemoSound.title)
        XCTAssertEqual(clip.sampleRate, DemoSound.sampleRate)
        XCTAssertEqual(clip.duration, DemoSound.duration, accuracy: 1 / DemoSound.sampleRate)
        XCTAssertTrue(clip.left.allSatisfy(\.isFinite))
    }

    /// CA1 — SF-74, D-36 : démo en tête (« Intégré »), puis imports du plus récent au plus ancien ;
    /// à date égale, par titre puis par identifiant. Chaque entrée garde tous ses champs.
    func testEntriesOrderDemoFirstThenNewest_SF74() async throws {
        let t0 = Date(timeIntervalSince1970: 1_794_000_000)
        let oldest = sandbox.entry(fileName: "ancien.wav", size: 1, importedAt: t0)
        let newest = sandbox.entry(fileName: "recent.wav", size: 2, importedAt: t0 + 100)
        let tieB = sandbox.entry(fileName: "b.wav", size: 3, importedAt: t0 + 50)
        let tieA = sandbox.entry(fileName: "a.wav", size: 4, importedAt: t0 + 50)
        try sandbox.writeIndex([oldest, tieB, newest, tieA])

        let entries = await makeStore().entries
        XCTAssertEqual(entries, [demo, newest, tieA, tieB, oldest])
        XCTAssertEqual(entries.first?.origin, .demo)
        XCTAssertTrue(entries.dropFirst().allSatisfy { $0.origin == .imported && $0.isDeletable })
    }

    /// CA1 : sans index, la bibliothèque ne contient que la démo et rien n'est écrit.
    func testMissingIndexGivesTheDemoOnly() async throws {
        let store = makeStore()
        let entries = await store.entries
        let removed = await store.reconcile()
        XCTAssertEqual(entries, [demo])
        XCTAssertEqual(removed, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.locations.libraryIndexURL.path))
    }

    /// CA3 — NFR12, scénario « Index illisible » : seule la démo reste, l'ancien contenu est dans
    /// `library.json.corrupt`, sans plantage ; un second index illisible ne l'écrase pas.
    func testUnreadableIndexIsSetAsideAndLibraryStartsEmpty_NFR12() async throws {
        try sandbox.writeRawIndex("{ pas du JSON")
        let store = makeStore()
        let entries = await store.entries
        XCTAssertEqual(entries, [demo])
        let corrupt = sandbox.locations.supportDirectory.appendingPathComponent("library.json.corrupt")
        XCTAssertEqual(try String(contentsOf: corrupt, encoding: .utf8), "{ pas du JSON")
        let setAside = await store.setAsideIndexURL
        XCTAssertEqual(setAside?.lastPathComponent, "library.json.corrupt")

        try sandbox.writeRawIndex("[]")
        let entriesAfterSecondFailure = await makeStore().entries
        XCTAssertEqual(entriesAfterSecondFailure, [demo])
        XCTAssertEqual(try String(contentsOf: corrupt, encoding: .utf8), "{ pas du JSON")
        let second = sandbox.locations.supportDirectory.appendingPathComponent("library.json.corrupt_2")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "[]")
    }

    /// CA4 — RM-48, D-11, scénario « Copie supprimée en dehors de l'application » : copie absente
    /// ou de taille différente → entrée retirée de la liste et de l'index, renvoyée une seule fois.
    /// Un fichier de `Banque de sons` absent de l'index est ignoré.
    func testReconcileRemovesAndReturnsMissingOrResizedCopies_RM48_D11() async throws {
        let t0 = Date(timeIntervalSince1970: 1_794_000_000)
        let boucle = sandbox.entry(fileName: "boucle.wav", size: 12_345, importedAt: t0 + 2)
        let resized = sandbox.entry(fileName: "modifie.wav", size: 100, importedAt: t0 + 1)
        let intact = sandbox.entry(fileName: "intact.wav", size: 64, importedAt: t0)
        try sandbox.writeCopy("boucle.wav", size: 12_345)
        try sandbox.writeCopy("modifie.wav", size: 99)
        try sandbox.writeCopy("intact.wav", size: 64)
        try sandbox.writeCopy("orphelin.wav", size: 10)
        try sandbox.writeIndex([boucle, resized, intact])
        try FileManager.default.removeItem(at: sandbox.copyURL("boucle.wav"))

        let store = makeStore()
        let removed = await store.reconcile()
        XCTAssertEqual(removed, [boucle, resized])
        let entries = await store.entries
        XCTAssertEqual(entries, [demo, intact])
        XCTAssertEqual(try sandbox.indexedIDs(), [intact.id])
        let secondPass = await store.reconcile()
        XCTAssertEqual(secondPass, [])
        let nextLaunch = await makeStore().reconcile()
        XCTAssertEqual(nextLaunch, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.copyURL("orphelin.wav").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.copyURL("modifie.wav").path),
                      "reconciliation never deletes files")
    }

    /// CA4 : sans changement, `reconcile()` ne réécrit pas l'index.
    func testReconcileWithoutChangeLeavesTheIndexUntouched() async throws {
        let entry = sandbox.entry(fileName: "a.wav", size: 8)
        try sandbox.writeCopy("a.wav", size: 8)
        try sandbox.writeIndex([entry])
        let before = try Data(contentsOf: sandbox.locations.libraryIndexURL)
        let removed = await makeStore().reconcile()
        XCTAssertEqual(removed, [])
        XCTAssertEqual(try Data(contentsOf: sandbox.locations.libraryIndexURL), before)
    }

    /// CA4 — D-11, scénario « Charger un son dont la copie a disparu » : `url(for:)` vérifie la
    /// copie ; absente ou modifiée → entrée retirée et `notFound`, sans retour par `reconcile()`.
    func testURLForMissingCopyRemovesEntryAndThrowsNotFound_D11() async throws {
        let boucle = sandbox.entry(fileName: "boucle.wav", size: 12_345)
        let other = sandbox.entry(fileName: "autre.wav", size: 32)
        try sandbox.writeCopy("boucle.wav", size: 12_345)
        try sandbox.writeCopy("autre.wav", size: 32)
        try sandbox.writeIndex([boucle, other])
        let store = makeStore()
        let url = try await store.url(for: boucle.id)
        XCTAssertEqual(url.standardizedFileURL, sandbox.copyURL("boucle.wav").standardizedFileURL)

        try FileManager.default.removeItem(at: sandbox.copyURL("boucle.wav"))
        await assertThrows(.notFound) { _ = try await store.url(for: boucle.id) }
        var entries = await store.entries
        XCTAssertFalse(entries.contains { $0.id == boucle.id })
        XCTAssertEqual(try sandbox.indexedIDs(), [other.id])
        let removed = await store.reconcile()
        XCTAssertEqual(removed, [], "the caller already knows this entry")

        try sandbox.writeCopy("autre.wav", size: 33)
        await assertThrows(.notFound) { _ = try await store.url(for: other.id) }
        entries = await store.entries
        XCTAssertEqual(entries, [demo])
        await assertThrows(.notFound) { _ = try await store.url(for: UUID()) }
    }

    /// CA6 — RM-49, scénario « Supprimer un son non chargé » : la copie est supprimée, puis
    /// l'entrée ; le fichier d'origine, hors du bac à sable, n'est pas modifié.
    func testDeleteRemovesCopyThenEntry_RM49() async throws {
        let original = sandbox.root.appendingPathComponent("Fichiers/boucle.wav")
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        let originalBytes = Data(repeating: 0x5A, count: 12_345)
        try originalBytes.write(to: original)
        let boucle = sandbox.entry(fileName: "boucle.wav", size: 12_345)
        let other = sandbox.entry(fileName: "autre.wav", size: 32)
        try sandbox.writeCopy("boucle.wav", size: 12_345)
        try sandbox.writeCopy("autre.wav", size: 32)
        try sandbox.writeIndex([boucle, other])

        let store = makeStore()
        try await store.delete(id: boucle.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.copyURL("boucle.wav").path))
        let entries = await store.entries
        XCTAssertEqual(entries, [demo, other])
        XCTAssertEqual(try sandbox.indexedIDs(), [other.id])
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.copyURL("autre.wav").path))
        await assertThrows(.notFound) { try await store.delete(id: boucle.id) }
    }

    /// CA6 — RM-49 : une copie déjà disparue n'empêche pas la suppression de l'entrée.
    func testDeleteEntryWhoseCopyIsAlreadyGone() async throws {
        let entry = sandbox.entry(fileName: "parti.wav", size: 5)
        try sandbox.writeIndex([entry])
        let store = makeStore()
        try await store.delete(id: entry.id)
        let entries = await store.entries
        XCTAssertEqual(entries, [demo])
        XCTAssertEqual(try sandbox.indexedIDs(), [])
    }

    /// CA6 — SF-74 : la démo lève `demoCannotBeDeleted`, une entrée inconnue `notFound` ; la liste
    /// ne change pas.
    func testDeleteDemoAndUnknownEntry_SF74() async throws {
        let entry = sandbox.entry(fileName: "a.wav", size: 8)
        try sandbox.writeCopy("a.wav", size: 8)
        try sandbox.writeIndex([entry])
        let store = makeStore()
        await assertThrows(.demoCannotBeDeleted) { try await store.delete(id: LibraryEntry.demoID) }
        await assertThrows(.notFound) { try await store.delete(id: UUID()) }
        let entries = await store.entries
        XCTAssertEqual(entries, [demo, entry])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.copyURL("a.wav").path))
    }

    /// CA6 : un nom de copie forgé dans l'index (`../x`, chemin absolu, `.cache`) ne désigne aucun
    /// fichier ; ni `reconcile()`, ni `url(for:)`, ni `delete(id:)` ne touchent un fichier hors de
    /// `Banque de sons`, ni un fichier caché.
    func testForgedFileNamesNeverEscapeTheSoundBank() async throws {
        let outside = sandbox.locations.documentsDirectory.appendingPathComponent("x")
        try Data(repeating: 1, count: 7).write(to: outside)
        let absolute = sandbox.root.appendingPathComponent("victime.wav")
        try Data(repeating: 2, count: 9).write(to: absolute)
        try sandbox.writeCopy(".cache", size: 3)
        let forged = [
            sandbox.entry(fileName: "../x", size: 7),
            sandbox.entry(fileName: absolute.path, size: 9),
            sandbox.entry(fileName: ".cache", size: 3),
            sandbox.entry(fileName: "", size: 0),
        ]
        func assertVictimsIntact(file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(try? Data(contentsOf: outside), Data(repeating: 1, count: 7), file: file, line: line)
            XCTAssertEqual(try? Data(contentsOf: absolute), Data(repeating: 2, count: 9), file: file, line: line)
            XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.copyURL(".cache").path), file: file, line: line)
        }

        try sandbox.writeIndex(forged)
        for entry in forged {
            await assertThrows(.notFound) { _ = try await makeStore().url(for: entry.id) }
        }
        assertVictimsIntact()

        try sandbox.writeIndex(forged)
        let store = makeStore()
        for entry in forged { try await store.delete(id: entry.id) }
        let entries = await store.entries
        XCTAssertEqual(entries, [demo])
        assertVictimsIntact()

        try sandbox.writeIndex(forged)
        let removed = await makeStore().reconcile()
        XCTAssertEqual(Set(removed.map(\.id)), Set(forged.map(\.id)))
        assertVictimsIntact()

        for name in ["..", "../x", "a/b.wav", "/etc/x", ".cache", "", "a..b.wav", "nul\0.wav"] {
            XCTAssertFalse(LibraryStore.isSafeFileName(name), name)
        }
        for name in ["boucle.wav", "voix funk_2.m4a", "é.aiff"] {
            XCTAssertTrue(LibraryStore.isSafeFileName(name), name)
        }
    }

    /// CA7 — RM-58 : l'UUID d'une entrée survit à la relecture de l'index et à la réconciliation
    /// des autres entrées.
    func testIdentifiersAreStableAcrossReloads_RM58() async throws {
        let keptID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let kept = sandbox.entry(id: keptID, fileName: "garde.wav", size: 16)
        let lost = sandbox.entry(fileName: "perdu.wav", size: 16)
        try sandbox.writeCopy("garde.wav", size: 16)
        try sandbox.writeIndex([kept, lost])

        let firstLaunch = await makeStore().entries
        XCTAssertEqual(firstLaunch.map(\.id), [LibraryEntry.demoID, kept.id, lost.id])
        let removed = await makeStore().reconcile()
        XCTAssertEqual(removed.map(\.id), [lost.id])
        let afterReconcile = await makeStore().entries
        XCTAssertEqual(afterReconcile, [demo, kept])
        XCTAssertEqual(afterReconcile.last?.id, keptID)
    }

    /// CA8 — SF-20, scénario « Retrouver la bibliothèque après relancement » : une nouvelle instance
    /// sur les mêmes emplacements retrouve les mêmes entrées, y compris après une écriture du magasin.
    func testLibraryPersistsAcrossInstances_6_13() async throws {
        let t0 = Date(timeIntervalSince1970: 1_794_000_000)
        let voix = sandbox.entry(fileName: "voix_funk.wav", size: 20, importedAt: t0 + 1)
        let boucle = sandbox.entry(fileName: "boucle.wav", size: 10, importedAt: t0)
        try sandbox.writeCopy("voix_funk.wav", size: 20)
        try sandbox.writeCopy("boucle.wav", size: 10)
        try sandbox.writeIndex([voix, boucle])

        let first = makeStore()
        try await first.delete(id: boucle.id)
        let before = await first.entries
        let after = await makeStore().entries
        XCTAssertEqual(after, before)
        XCTAssertEqual(after, [demo, voix])
    }

    /// CA9 : l'import reste hors périmètre (story 3.2) et lève une erreur sans rien écrire.
    func testImportIsNotImplementedYet() async throws {
        let source = sandbox.root.appendingPathComponent("source.wav")
        try Data(repeating: 0, count: 4).write(to: source)
        do {
            _ = try await makeStore().importFile(at: source)
            XCTFail("import arrives with story 3.2")
        } catch {
            guard case .writeFailed = error as? LibraryError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: sandbox.locations.soundBankDirectory.path), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.locations.libraryIndexURL.path))
    }
}
