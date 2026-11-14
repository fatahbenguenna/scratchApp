import Foundation
import ScratchCore
import XCTest
@testable import ScratchLibrary

extension LibrarySandbox {
    /// Fichiers d'origine, hors du bac à sable de l'app (Fichiers, Finder).
    var sourcesDirectory: URL { root.appendingPathComponent("Fichiers", isDirectory: true) }

    /// Horloge fixe des tests : 2026-11-06T21:20:00.6Z.
    static let clock: @Sendable () -> Date = { Date(timeIntervalSince1970: 1_794_000_000.6) }

    func makeImportStore(decoder: any AudioDecoding = FakeDecoder(),
                         capacity: any StorageCapacityProviding = FixedCapacity(bytes: nil),
                         chunkWriter: any ImportChunkWriting = FileHandleChunkWriter()) -> LibraryStore {
        LibraryStore(locations: locations, decoder: decoder, capacity: capacity, chunkWriter: chunkWriter,
                     now: Self.clock)
    }

    /// WAV d'origine nommé `name`, dans `Fichiers/` ou l'un de ses sous-dossiers.
    @discardableResult
    func source(_ name: String, seconds: Double = 0.5, seed: UInt32 = 1, folder: String? = nil) throws -> URL {
        var directory = sourcesDirectory
        if let folder { directory = directory.appendingPathComponent(folder, isDirectory: true) }
        return try WAVWriter.write(to: directory.appendingPathComponent(name), seconds: seconds, seed: seed)
    }

    func names(in directory: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    var bankNames: [String] { names(in: locations.soundBankDirectory) }
    var importNames: [String] { names(in: locations.importsDirectory) }

    /// État observable de la bibliothèque sur disque : copies, temporaires et index octet pour octet.
    func diskState() -> [String] {
        let index = (try? Data(contentsOf: locations.libraryIndexURL)).map { ContentHasher.sha256Hex(of: $0) } ?? "none"
        return bankNames.map { "bank/\($0)" } + importNames.map { "imports/\($0)" } + ["index \(index)"]
    }
}

/// Écriture du temporaire qui échoue après avoir écrit le premier bloc.
private struct FailingChunkWriter: ImportChunkWriting {
    let error: Error

    func write(_ chunk: Data, to handle: FileHandle) throws {
        try handle.write(contentsOf: chunk.prefix(10))
        throw error
    }
}

/// Import (story 3.2) : copie atomique, validation par la sonde, dédoublonnage, nommage, transaction.
final class ImportTests: XCTestCase {
    private var sandbox: LibrarySandbox!
    private let demo = LibraryEntry.demo(title: DemoSound.title, duration: DemoSound.duration)

    override func setUpWithError() throws {
        sandbox = try LibrarySandbox()
    }

    override func tearDownWithError() throws {
        sandbox.remove()
    }

    private func assertImportFails(_ expected: LibraryError, _ store: LibraryStore, _ source: URL,
                                   file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let result = try await store.importFile(at: source)
            XCTFail("expected \(expected), got \(result)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? LibraryError, expected, file: file, line: line)
        }
    }

    private func addedEntry(_ result: ImportResult, file: StaticString = #filePath, line: UInt = #line) throws -> LibraryEntry {
        guard case let .added(entry) = result else {
            XCTFail("expected .added, got \(result)", file: file, line: line)
            throw LibraryError.notFound
        }
        return entry
    }

    // MARK: - CA1, CA2

    /// CA1 — SF-02, RM-47, 5.3 : copie par un temporaire de `Imports/`, empreinte de la source,
    /// sonde sur la copie, déplacement dans `Banque de sons`, index écrit ; date à la seconde.
    func testImportCopiesHashesAndIndexes_SF02_RM47() async throws {
        let source = try sandbox.source("voix_funk.wav", seconds: 0.5)
        let decoder = FakeDecoder()
        let store = sandbox.makeImportStore(decoder: decoder)
        let entry = try addedEntry(try await store.importFile(at: source))

        XCTAssertEqual(entry.fileName, "voix_funk.wav")
        XCTAssertEqual(entry.title, "voix_funk.wav")
        XCTAssertEqual(entry.origin, .imported)
        XCTAssertEqual(entry.duration, 0.5, accuracy: 1e-9)
        XCTAssertEqual(entry.fileSize, Int64(try Data(contentsOf: source).count))
        XCTAssertEqual(entry.contentHash, try ContentHasher.sha256Hex(ofFileAt: source))
        XCTAssertEqual(entry.importedAt, Date(timeIntervalSince1970: 1_794_000_000))
        XCTAssertEqual(try Data(contentsOf: sandbox.copyURL("voix_funk.wav")), try Data(contentsOf: source))

        let probed = try XCTUnwrap(decoder.probedURLs.first)
        XCTAssertEqual(decoder.probedURLs.count, 1)
        XCTAssertEqual(probed.deletingLastPathComponent().lastPathComponent, "Imports", "the probe reads the copy")
        XCTAssertEqual(probed.pathExtension, "wav")
        XCTAssertEqual(sandbox.importNames, [], "the temporary is moved, not left behind")

        let entries = await store.entries
        XCTAssertEqual(entries, [demo, entry])
        XCTAssertEqual(try sandbox.indexedIDs(), [entry.id])
        let relaunched = await sandbox.makeImportStore().entries
        XCTAssertEqual(relaunched, [demo, entry], "the entry read back equals the one returned")
    }

    /// CA2 — SF-02, 6.1 « Un import ne modifie pas le fichier source » : contenu et date intacts ;
    /// aucun chemin de la source dans l'index.
    func testSourceIsNeverModified_SF02() async throws {
        let source = try sandbox.source("boucle.wav")
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: source.path)
        let bytes = try Data(contentsOf: source)

        _ = try await sandbox.makeImportStore().importFile(at: source)

        XCTAssertEqual(try Data(contentsOf: source), bytes)
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        XCTAssertEqual(attributes[.modificationDate] as? Date, date)
        let index = try String(contentsOf: sandbox.locations.libraryIndexURL, encoding: .utf8)
        XCTAssertFalse(index.contains("Fichiers"), "no external path or bookmark is kept")
    }

    // MARK: - CA3, CA7

    /// CA3 — 6.1 « Échec de copie faute d'espace » : contrôle préalable (taille + 10 Mio) et disque
    /// plein à l'écriture → `insufficientStorage`, sans aucune trace ; autre échec → `writeFailed`.
    func testInsufficientStorageLeavesNoTrace_6_1() async throws {
        _ = try await sandbox.makeImportStore().importFile(at: try sandbox.source("existant.wav", seed: 9))
        let before = sandbox.diskState()
        let source = try sandbox.source("boucle.wav")
        let size = Int64(try Data(contentsOf: source).count)
        let required = LibraryStore.requiredCapacity(forFileOfSize: size)
        XCTAssertEqual(required, size + 10 * 1_048_576)
        XCTAssertEqual(LibraryStore.requiredCapacity(forFileOfSize: 1_000_000_000), 1_050_000_000, "5 % margin")

        await assertImportFails(.insufficientStorage, sandbox.makeImportStore(capacity: FixedCapacity(bytes: required - 1)),
                                source)
        XCTAssertEqual(sandbox.diskState(), before)

        for error in [POSIXError(.ENOSPC) as Error, CocoaError(.fileWriteOutOfSpace)] {
            let store = sandbox.makeImportStore(chunkWriter: FailingChunkWriter(error: error))
            await assertImportFails(.insufficientStorage, store, source)
            XCTAssertEqual(sandbox.diskState(), before, "\(error)")
        }
        let denied = sandbox.makeImportStore(chunkWriter: FailingChunkWriter(error: CocoaError(.fileWriteNoPermission)))
        do {
            _ = try await denied.importFile(at: source)
            XCTFail("expected writeFailed")
        } catch {
            guard case .writeFailed = error as? LibraryError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(sandbox.diskState(), before)

        let exactlyEnough = sandbox.makeImportStore(capacity: FixedCapacity(bytes: required))
        let accepted = try await exactlyEnough.importFile(at: source)
        XCTAssertTrue(accepted.isNew)
    }

    /// CA3 — RM-48, 6.1 (incompatible, protégé, corrompu ou vide, trop long, trop court) : l'erreur
    /// de la sonde est propagée et rien n'est conservé ; une source introuvable donne `writeFailed`.
    func testProbeErrorsLeaveNoTrace_RM48() async throws {
        _ = try await sandbox.makeImportStore().importFile(at: try sandbox.source("existant.wav", seed: 9))
        let before = sandbox.diskState()
        let source = try sandbox.source("son.wav")
        let errors: [LibraryError] = [
            .unsupportedFormat, .protectedContent, .corrupted, .tooLong(duration: 1_500), .tooShort(duration: 0.04),
        ]
        for error in errors {
            let store = sandbox.makeImportStore(decoder: FakeDecoder(script: { _ in throw error }))
            await assertImportFails(error, store, source)
            XCTAssertEqual(sandbox.diskState(), before, "\(error)")
        }
        struct Unexpected: Error {}
        let unexpected = sandbox.makeImportStore(decoder: FakeDecoder(script: { _ in throw Unexpected() }))
        await assertImportFails(.unsupportedFormat, unexpected, source)

        let text = sandbox.sourcesDirectory.appendingPathComponent("notes.wav")
        try Data("pas un son".utf8).write(to: text)
        await assertImportFails(.unsupportedFormat, sandbox.makeImportStore(), text)
        let empty = sandbox.sourcesDirectory.appendingPathComponent("vide.wav")
        try Data().write(to: empty)
        await assertImportFails(.corrupted, sandbox.makeImportStore(), empty)
        let truncated = sandbox.sourcesDirectory.appendingPathComponent("tronque.wav")
        try WAVWriter.data(seconds: 1).prefix(600).write(to: truncated)
        await assertImportFails(.corrupted, sandbox.makeImportStore(), truncated)
        await assertImportFails(.unsupportedFormat, sandbox.makeImportStore(), sandbox.sourcesDirectory)
        do {
            _ = try await sandbox.makeImportStore().importFile(at: sandbox.sourcesDirectory.appendingPathComponent("absent.wav"))
            XCTFail("expected writeFailed")
        } catch {
            guard case .writeFailed = error as? LibraryError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(sandbox.diskState(), before)
    }

    /// CA3, CA7 — RM-48 : un index impossible à écrire annule l'import ; la copie déplacée est
    /// supprimée, la liste est inchangée.
    func testFailedIndexWriteRollsBackTheCopy_RM48() async throws {
        let store = sandbox.makeImportStore()
        let first = try addedEntry(try await store.importFile(at: try sandbox.source("boucle.wav", seed: 1)))
        let index = sandbox.locations.libraryIndexURL
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index.appendingPathComponent("bloque"), withIntermediateDirectories: true)

        do {
            _ = try await store.importFile(at: try sandbox.source("autre.wav", seed: 2))
            XCTFail("the index cannot be written")
        } catch {
            guard case .writeFailed = error as? LibraryError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(sandbox.bankNames, ["boucle.wav"])
        XCTAssertEqual(sandbox.importNames, [])
        let entries = await store.entries
        XCTAssertEqual(entries, [demo, first])
    }

    /// CA7 : les temporaires orphelins d'`Imports/` sont purgés au premier accès du magasin.
    func testOrphanTemporariesArePurged() async throws {
        let imports = sandbox.locations.importsDirectory
        try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
        try Data("interrompu".utf8).write(to: imports.appendingPathComponent("\(UUID().uuidString).wav"))
        try Data("interrompu".utf8).write(to: imports.appendingPathComponent(UUID().uuidString))
        XCTAssertEqual(sandbox.importNames.count, 2)
        let entries = await sandbox.makeImportStore().entries
        XCTAssertEqual(entries, [demo])
        XCTAssertEqual(sandbox.importNames, [])
    }

    // MARK: - CA4

    /// CA4 — SF-75, scénario « Contenu déjà présent » : même empreinte → `.existing` avec l'entrée
    /// de « boucle.wav », sans seconde copie ni seconde sonde.
    func testDuplicateContentReturnsExisting_SF75() async throws {
        let decoder = FakeDecoder()
        let store = sandbox.makeImportStore(decoder: decoder)
        let original = try addedEntry(try await store.importFile(at: try sandbox.source("boucle.wav", seed: 5)))
        let result = try await store.importFile(at: try sandbox.source("copie de boucle.wav", seed: 5))

        XCTAssertEqual(result, .existing(original))
        XCTAssertFalse(result.isNew)
        XCTAssertEqual(sandbox.bankNames, ["boucle.wav"])
        XCTAssertEqual(sandbox.importNames, [])
        XCTAssertEqual(decoder.probedURLs.count, 1)
        let entries = await store.entries
        XCTAssertEqual(entries, [demo, original])
    }

    /// CA4 : si la copie de l'entrée de même empreinte a disparu, l'import redevient un ajout et
    /// remplace l'entrée périmée.
    func testDuplicateOfAVanishedCopyIsAddedAgain_SF75() async throws {
        let store = sandbox.makeImportStore()
        let stale = try addedEntry(try await store.importFile(at: try sandbox.source("boucle.wav", seed: 5)))
        try FileManager.default.removeItem(at: sandbox.copyURL("boucle.wav"))
        let fresh = try addedEntry(try await store.importFile(at: try sandbox.source("copie de boucle.wav", seed: 5)))

        XCTAssertNotEqual(fresh.id, stale.id)
        XCTAssertEqual(fresh.contentHash, stale.contentHash)
        let entries = await store.entries
        XCTAssertEqual(entries, [demo, fresh])
        XCTAssertEqual(try sandbox.indexedIDs(), [fresh.id])
    }

    // MARK: - CA5

    /// CA5 — D-12, scénario « Importer deux fichiers portant le même nom » : `voix_funk_2.wav`, puis
    /// `_3` ; aucune copie écrasée ; titres = noms des copies ; un fichier hors index n'est jamais
    /// écrasé ; casse et normalisation Unicode comptent comme le même nom.
    func testHomonymGetsUnderscoreSuffix_D12() async throws {
        let store = sandbox.makeImportStore()
        let first = try addedEntry(try await store.importFile(at: try sandbox.source("voix_funk.wav", seed: 1)))
        let firstBytes = try Data(contentsOf: sandbox.copyURL("voix_funk.wav"))
        let second = try addedEntry(try await store.importFile(
            at: try sandbox.source("voix_funk.wav", seed: 2, folder: "Drive")))
        let third = try addedEntry(try await store.importFile(
            at: try sandbox.source("Voix_Funk.wav", seed: 3, folder: "Bureau")))

        XCTAssertEqual(second.fileName, "voix_funk_2.wav")
        XCTAssertEqual(third.fileName, "Voix_Funk_3.wav")
        XCTAssertEqual([first.title, second.title, third.title], ["voix_funk.wav", "voix_funk_2.wav", "Voix_Funk_3.wav"])
        XCTAssertEqual(try Data(contentsOf: sandbox.copyURL("voix_funk.wav")), firstBytes)

        try sandbox.writeCopy("orphelin.wav", size: 3)
        let orphan = try addedEntry(try await store.importFile(at: try sandbox.source("orphelin.wav", seed: 4)))
        XCTAssertEqual(orphan.fileName, "orphelin_2.wav")
        XCTAssertEqual(try Data(contentsOf: sandbox.copyURL("orphelin.wav")).count, 3, "never overwritten")

        let composed = try addedEntry(try await store.importFile(at: try sandbox.source("\u{E9}t\u{E9}.wav", seed: 6)))
        let decomposed = try addedEntry(try await store.importFile(
            at: try sandbox.source("e\u{301}te\u{301}.wav", seed: 7, folder: "NFD")))
        XCTAssertEqual(composed.fileName, "\u{E9}t\u{E9}.wav")
        XCTAssertEqual(CopyNaming.comparisonKey(decomposed.fileName), CopyNaming.comparisonKey("\u{E9}t\u{E9}_2.wav"))
    }

    /// CA5 (assainissement validé) : un nom que la bibliothèque refuserait (`..`, point en tête)
    /// est assaini, et l'entrée survit à la réconciliation.
    func testUnsafeSourceNamesAreSanitized() async throws {
        let store = sandbox.makeImportStore()
        let dots = try addedEntry(try await store.importFile(at: try sandbox.source("remix..final.wav", seed: 1)))
        let hidden = try addedEntry(try await store.importFile(at: try sandbox.source(".cache.wav", seed: 2)))
        XCTAssertEqual(dots.fileName, "remix.final.wav")
        XCTAssertEqual(hidden.fileName, "cache.wav")
        let removed = await store.reconcile()
        XCTAssertEqual(removed, [])
    }

    // MARK: - CA6

    /// CA6 — SF-20, 6.1 « Recharger un son déjà importé sans accéder à Drive » : la source supprimée,
    /// `url(for:)` donne la copie locale vérifiée.
    func testReloadDoesNotNeedTheSource_SF20() async throws {
        let source = try sandbox.source("voix_funk.wav")
        let store = sandbox.makeImportStore()
        let entry = try addedEntry(try await store.importFile(at: source))
        try FileManager.default.removeItem(at: sandbox.sourcesDirectory)

        let relaunched = sandbox.makeImportStore()
        let removed = await relaunched.reconcile()
        XCTAssertEqual(removed, [])
        let url = try await relaunched.url(for: entry.id)
        XCTAssertEqual(url.standardizedFileURL, sandbox.copyURL("voix_funk.wav").standardizedFileURL)
    }

    // MARK: - CA8

    /// CA8 : deux imports simultanés du même contenu, sondés en même temps, donnent une seule copie
    /// (`.added` puis `.existing`) ; deux homonymes simultanés reçoivent deux noms distincts.
    func testConcurrentIdenticalImportsGiveOneCopy() async throws {
        let rendezvous = ProbeRendezvous()
        let decoder = FakeDecoder(script: { url in
            await rendezvous.arrive(waitingFor: 2)
            return try FakeDecoder.wavInfo(at: url)
        })
        let store = sandbox.makeImportStore(decoder: decoder)
        let sourceA = try sandbox.source("platine A.wav", seed: 8)
        let sourceB = try sandbox.source("platine B.wav", seed: 8)
        async let first = store.importFile(at: sourceA)
        async let second = store.importFile(at: sourceB)
        let results = try await [first, second]

        XCTAssertEqual(decoder.probedURLs.count, 2, "both imports reached the probe before either committed")
        XCTAssertEqual(results.filter(\.isNew).count, 1)
        XCTAssertEqual(results[0].entry, results[1].entry)
        XCTAssertEqual(sandbox.bankNames.count, 1)
        XCTAssertEqual(sandbox.importNames, [])

        let homonymRendezvous = ProbeRendezvous()
        let homonymStore = sandbox.makeImportStore(decoder: FakeDecoder(script: { url in
            await homonymRendezvous.arrive(waitingFor: 2)
            return try FakeDecoder.wavInfo(at: url)
        }))
        let homonymA = try sandbox.source("x.wav", seed: 10, folder: "A")
        let homonymB = try sandbox.source("x.wav", seed: 11, folder: "B")
        async let left = homonymStore.importFile(at: homonymA)
        async let right = homonymStore.importFile(at: homonymB)
        let names = try await [left, right].map(\.entry.fileName)
        XCTAssertEqual(Set(names), ["x.wav", "x_2.wav"])
    }

    /// Annulation pendant la sonde : `CancellationError`, aucune trace.
    func testCancelledImportLeavesNoTrace() async throws {
        let before = sandbox.diskState()
        let rendezvous = ProbeRendezvous()
        let store = sandbox.makeImportStore(decoder: FakeDecoder(script: { url in
            await rendezvous.arrive(waitingFor: 1)
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return try FakeDecoder.wavInfo(at: url)
        }))
        let source = try sandbox.source("long.wav")
        let task = Task { try await store.importFile(at: source) }
        while await rendezvous.arrivals == 0 { await Task.yield() }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled import must not complete")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertEqual(sandbox.diskState(), before)
    }

    /// T1 : l'espace libre du système est connu pour un dossier existant.
    func testSystemStorageCapacity() throws {
        let capacity = try XCTUnwrap(SystemStorageCapacity().availableCapacity(forWritingAt: sandbox.root))
        XCTAssertGreaterThan(capacity, 0)
    }
}
