import Foundation
import ScratchCore
import ScratchLibrary
import XCTest
@testable import ScratchUI

/// Écran Bibliothèque (story 3.5 ; SF-74, RM-49, UX §5.19, §8.4). Les tests utilisent
/// `RecordingEngine`, le décodeur factice et le vrai `LibraryStore` dans un dossier temporaire.
@MainActor
final class LibraryScreenTests: XCTestCase {
    private var library: TemporaryLibrary!
    private let demo = LibraryEntry.demo(title: DemoSound.title, duration: DemoSound.duration)
    private let nbsp = "\u{00A0}"

    override func setUp() async throws {
        library = try TemporaryLibrary()
    }

    override func tearDown() async throws {
        library.remove()
    }

    private func makeModel(engine: RecordingEngine = RecordingEngine(), store: (any LibraryStoring)? = nil) -> AppModel {
        let decoder = FakeDecoder()
        return AppModel(engine: engine, host: nil, library: store ?? library.makeStore(decoder: decoder),
                        preferences: InMemoryPreferencesStore(), decoder: decoder,
                        libraryFolder: library.locations.soundBankDirectory)
    }

    private func q(_ text: String) -> String { "«\(nbsp)\(text)\(nbsp)»" }

    /// Midi UTC : la même date dans tous les fuseaux de −11 h à +11 h.
    private static let november14 = Date(timeIntervalSince1970: 1_794_657_600) // 2026-11-14T12:00:00Z

    /// Bibliothèque dont `delete` échoue toujours (« Suppression impossible »).
    private struct FailingDeleteLibrary: LibraryStoring {
        let base: LibraryStore
        var entries: [LibraryEntry] { get async { await base.entries } }
        func reconcile() async -> [LibraryEntry] { await base.reconcile() }
        func importFile(at url: URL) async throws -> ImportResult { try await base.importFile(at: url) }
        func delete(id: UUID) async throws { throw LibraryError.writeFailed(reason: "disk") }
        func url(for id: UUID) async throws -> URL { try await base.url(for: id) }
    }

    // MARK: - CA 1, 7

    /// CA 1 — SF-74, D-20, D-36, 6.13 « Consulter la bibliothèque » : démo en tête (« 8,0 s ·
    /// Intégré »), puis mes sons ; durée, date, origine ; pastilles ; libellés VoiceOver ;
    /// identifiants ; texte de liste vide.
    func testListOrderAndRowTexts_SF74() {
        let older = LibraryEntry(contentHash: "", fileName: "voix_funk.wav", fileSize: 1, title: "voix_funk.wav",
                                 duration: 72.4, importedAt: Self.november14, origin: .imported)
        let newer = LibraryEntry(contentHash: "", fileName: "beat.wav", fileSize: 1, title: "beat.wav",
                                 duration: 225, importedAt: Self.november14.addingTimeInterval(60), origin: .imported)
        let list = LibraryListModel(entries: [demo, newer, older]) { $0 == older.id ? [.a] : ($0 == newer.id ? [.a, .b] : []) }

        XCTAssertEqual(list.demo.map(\.title), ["Son de démonstration"])
        XCTAssertEqual(list.mine.map(\.title), ["beat.wav", "voix_funk.wav"], "newest first, as the store orders them")
        let demoRow = list.demo[0]
        XCTAssertEqual(demoRow.subtitle, "8,0\(nbsp)s · Intégré")
        XCTAssertFalse(demoRow.isDeletable)
        XCTAssertEqual(demoRow.identifier, "library.row.demo")
        XCTAssertEqual(demoRow.accessibilityLabel, "\(q("Son de démonstration")), 8,0 secondes, son intégré")
        XCTAssertNil(demoRow.accessibilityValue)

        XCTAssertEqual(list.mine[0].subtitle, "3:45 · 14 nov. 2026 · Import")
        XCTAssertEqual(list.mine[0].accessibilityValue, "chargé sur les platines A et B")
        XCTAssertEqual(list.mine[1].subtitle, "1:12 · 14 nov. 2026 · Import")
        XCTAssertEqual(list.mine[1].accessibilityLabel,
                       "\(q("voix_funk.wav")), 1 minute 12 secondes, importé le 14 novembre 2026")
        XCTAssertEqual(list.mine[1].accessibilityValue, "chargé sur la platine A")
        XCTAssertEqual(list.mine[1].loadedOn, [.a])
        XCTAssertEqual(list.mine[1].identifier, "library.row.\(older.id.uuidString)")

        XCTAssertEqual(LibraryListModel.emptyText(for: .mac),
                       "Aucun son importé. Cliquez sur \(q("Importer")) ou déposez un fichier sur une platine.")
        XCTAssertEqual(LibraryListModel.emptyText(for: .phone), "Aucun son importé. Touchez \(q("Importer")) sur une platine.")
        XCTAssertEqual(LibraryListModel.emptyText(for: .pad),
                       "Aucun son importé. Touchez \(q("Importer")) ou déposez un fichier sur une platine.")
    }

    /// UX §8.1 : durées `m:ss` dès 10 s, secondes et dixièmes en dessous ; forme parlée.
    func testDurationFormats_UX81() {
        XCTAssertEqual(LibraryFormatting.duration(225.9), "3:45")
        XCTAssertEqual(LibraryFormatting.duration(10), "0:10")
        XCTAssertEqual(LibraryFormatting.duration(4.27), "4,2\(nbsp)s")
        XCTAssertEqual(LibraryFormatting.duration(0.2), "0,2\(nbsp)s")
        XCTAssertEqual(LibraryFormatting.spokenDuration(72), "1 minute 12 secondes")
        XCTAssertEqual(LibraryFormatting.spokenDuration(180), "3 minutes")
        XCTAssertEqual(LibraryFormatting.spokenDuration(45), "45 secondes")
        XCTAssertEqual(LibraryFormatting.spokenDuration(1.5), "1,5 seconde")
        XCTAssertEqual(LibraryFormatting.date(Self.november14), "14 nov. 2026")
        XCTAssertEqual(LibraryFormatting.spokenDate(Self.november14), "14 novembre 2026")
    }

    /// CA 6, CA 7 : ⌘L ou le bouton ouvrent la feuille avec une liste à jour ; « OK » la ferme.
    func testOpenLibraryRefreshesTheList() async throws {
        let model = makeModel()
        await model.importAndLoad(try library.source("boucle.wav"), on: .a)
        let store = library.makeStore(decoder: FakeDecoder())
        let fresh = makeModel(store: store)
        XCTAssertEqual(fresh.libraryEntries, [])
        fresh.openLibrary()
        XCTAssertTrue(fresh.isLibraryPresented)
        await fresh.refreshLibrary()
        XCTAssertEqual(fresh.libraryEntries.map(\.fileName), ["", "boucle.wav"])
        fresh.closeLibrary()
        XCTAssertFalse(fresh.isLibraryPresented)
        XCTAssertEqual(fresh.libraryFolder?.lastPathComponent, "Banque de sons")
    }

    // MARK: - CA 2, 3

    /// CA 2 — SF-15, RM-57, 6.13 « Charger un son de la bibliothèque sur la platine B » : le parcours
    /// de 6.1 charge sur B seule et ferme la feuille. Si B est active, une confirmation est
    /// demandée : la feuille reste ouverte après un refus et se ferme après le remplacement.
    func testLoadOnBGoesThroughLoadingFlow_6_13() async throws {
        let engine = RecordingEngine()
        let model = makeModel(engine: engine)
        await model.importAndLoad(try library.source("voix_funk.wav"), on: .a)
        let entry = try XCTUnwrap(model.deckA.loadedEntry)
        let clipA = model.deckA.loadedClip
        engine.clearSentCommands()

        model.openLibrary()
        await model.loadFromLibrary(entry, on: .b)
        let clipB = try XCTUnwrap(model.deckB.loadedClip)
        XCTAssertEqual(engine.sentCommands, [.load(.b, clipB)])
        XCTAssertTrue(model.deckA.loadedClip === clipA, "deck A is not affected")
        XCTAssertEqual(model.deckB.loadedEntry, entry)
        XCTAssertFalse(model.isLibraryPresented, "the sheet closes after a load")

        engine.snapshot = EngineSnapshot(decks: DeckPair(a: .initial, b: DeckSnapshot(clipID: clipB.id, durationSeconds: 1,
                                                                                     motorOn: true)))
        engine.clearSentCommands()
        model.openLibrary()
        await model.loadFromLibrary(demo, on: .b)
        XCTAssertEqual(model.confirmation?.deck, .b)
        model.resolveConfirmation(replace: false)
        XCTAssertTrue(model.isLibraryPresented, "refusing keeps the list open")
        XCTAssertEqual(engine.sentCommands, [])

        await model.loadFromLibrary(demo, on: .b)
        await model.resolveConfirmation(replace: true)?.value
        XCTAssertEqual(model.deckB.loadedEntry, demo)
        XCTAssertFalse(model.isLibraryPresented, "the sheet closes after the replacement")
    }

    /// CA 3 — D-11, 6.13 « Charger un son dont la copie a disparu » : « Son introuvable », la ligne
    /// disparaît, la platine n'est pas modifiée et la feuille reste ouverte.
    func testMissingCopyShowsAlertAndRemovesRow_D11() async throws {
        let engine = RecordingEngine()
        let model = makeModel(engine: engine)
        await model.importAndLoad(try library.source("boucle.wav"), on: .a)
        let entry = try XCTUnwrap(model.deckA.loadedEntry)
        try FileManager.default.removeItem(at: library.copyURL("boucle.wav"))
        engine.clearSentCommands()

        model.openLibrary()
        await model.loadFromLibrary(entry, on: .b)
        XCTAssertEqual(model.alert?.title, "Son introuvable")
        XCTAssertEqual(model.libraryEntries, [demo])
        XCTAssertEqual(engine.sentCommands, [])
        XCTAssertNil(model.deckB.loadedEntry)
        XCTAssertTrue(model.isLibraryPresented)
    }

    // MARK: - CA 4, 5

    /// CA 4 — RM-49, 6.13 « Supprimer un son chargé sur une platine » : la confirmation nomme les
    /// platines. Une fois confirmée, chaque platine est arrêtée et vidée, puis la copie est
    /// supprimée ; l'original reste intact.
    func testDeleteLoadedSoundUnloadsThenDeletes_RM49() async throws {
        let engine = RecordingEngine()
        let model = makeModel(engine: engine)
        let source = try library.source("boucle.wav")
        let originalBytes = try Data(contentsOf: source)
        await model.importAndLoad(source, on: .a)
        let entry = try XCTUnwrap(model.deckA.loadedEntry)
        await model.loadFromLibrary(entry, on: .b)
        engine.clearSentCommands()

        model.requestDelete(entry)
        let confirmation = try XCTUnwrap(model.deletionConfirmation)
        XCTAssertEqual(confirmation.title, "Supprimer \(q("boucle.wav"))\(nbsp)?")
        XCTAssertEqual(confirmation.message,
                       "Ce son est chargé sur les platines A et B\(nbsp): elles seront vidées et arrêtées. La copie de ce son sera supprimée de ScratchApp. Le fichier d'origine n'est pas modifié.")
        let task = try XCTUnwrap(model.resolveDeletion(confirm: true))
        XCTAssertEqual(engine.sentCommands, [.motor(.a, on: false), .unload(.a), .motor(.b, on: false), .unload(.b)],
                       "decks are stopped and emptied before the copy is deleted")
        await task.value

        XCTAssertFalse(FileManager.default.fileExists(atPath: library.copyURL("boucle.wav").path))
        XCTAssertEqual(try Data(contentsOf: source), originalBytes, "the original file is never touched")
        XCTAssertEqual(model.libraryEntries, [demo])
        XCTAssertEqual(model.decks(carrying: entry.id), [])
        XCTAssertNil(model.deletionConfirmation)
    }

    /// CA 4 — 6.13 « Supprimer un son non chargé » : message sans platine ; Annuler ne change rien ;
    /// un échec donne « Suppression impossible ».
    func testDeleteUnloadedSoundAndFailure_RM49() async throws {
        let model = makeModel()
        await model.importAndLoad(try library.source("boucle.wav"), on: .a)
        let entry = try XCTUnwrap(model.deckA.loadedEntry)
        model.unload(.a)

        model.requestDelete(entry)
        XCTAssertEqual(model.deletionConfirmation?.message,
                       "La copie de ce son sera supprimée de ScratchApp. Le fichier d'origine n'est pas modifié.")
        XCTAssertNil(model.resolveDeletion(confirm: false))
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.copyURL("boucle.wav").path))

        let failing = makeModel(store: FailingDeleteLibrary(base: library.makeStore(decoder: FakeDecoder())))
        failing.requestDelete(entry)
        await failing.resolveDeletion(confirm: true)?.value
        XCTAssertEqual(failing.alert?.title, "Suppression impossible")
        XCTAssertEqual(failing.alert?.message, "\(q("boucle.wav")) n'a pas pu être supprimé. Réessayez.")
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.copyURL("boucle.wav").path))

        model.requestDelete(entry)
        await model.resolveDeletion(confirm: true)?.value
        XCTAssertEqual(model.libraryEntries, [demo], "the list refreshes after a deletion")
    }

    /// CA 5 — SF-74, 6.13 « Le son de démonstration ne peut pas être supprimé » : aucune action ni
    /// confirmation de suppression pour la démo.
    func testDemoHasNoDeleteAction_6_13() {
        let model = makeModel()
        model.requestDelete(demo)
        XCTAssertNil(model.deletionConfirmation)
        let row = LibraryRowItem(entry: demo, loadedOn: [])
        XCTAssertFalse(row.isDeletable)
    }
}
