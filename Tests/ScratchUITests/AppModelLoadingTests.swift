import Foundation
import ScratchCore
import ScratchLibrary
import XCTest
@testable import ScratchUI

/// Parcours de chargement de l'`AppModel` (story 6.1). Ils s'appuient sur `RecordingEngine`, le
/// décodeur factice et le vrai `LibraryStore` dans un dossier temporaire.
@MainActor
final class AppModelLoadingTests: XCTestCase {
    private var library: TemporaryLibrary!
    private let demo = LibraryEntry.demo(title: DemoSound.title, duration: DemoSound.duration)
    private let nbsp = "\u{00A0}"

    override func setUp() async throws {
        library = try TemporaryLibrary()
    }

    override func tearDown() async throws {
        library.remove()
    }

    private func makeModel(engine: RecordingEngine = RecordingEngine(), decoder: FakeDecoder = FakeDecoder(),
                           capacity: Int64? = nil) -> AppModel {
        let store = library.makeStore(decoder: decoder, capacity: capacity)
        return AppModel(engine: engine, host: nil, library: store, preferences: InMemoryPreferencesStore(),
                        decoder: decoder, indexRecovery: { await store.indexRecovery })
    }

    private func q(_ text: String) -> String { "«\(nbsp)\(text)\(nbsp)»" }

    private func loadedClip(_ command: EngineCommand?) -> AudioClip? {
        if case let .load(_, clip)? = command { return clip }
        return nil
    }

    private static func snapshot(a: DeckSnapshot = .initial, b: DeckSnapshot = .initial) -> EngineSnapshot {
        EngineSnapshot(decks: DeckPair(a: a, b: b))
    }

    // MARK: - CA 2, 3, 4

    /// CA 3 — SF-02, SF-03, RM-57 : un import sur A copie le fichier, puis charge la copie sur A
    /// seule ; `loadedEntry` et `loadedClip` sont posés ; la platine B ne change pas.
    func testImportLoadsOnOriginDeckOnly_SF02_RM57() async throws {
        let engine = RecordingEngine()
        let decoder = FakeDecoder()
        let model = makeModel(engine: engine, decoder: decoder)
        await model.importAndLoad(try library.source("voix_funk.wav"), on: .a)

        XCTAssertEqual(engine.sentCommands.count, 1)
        let clip = try XCTUnwrap(loadedClip(engine.sentCommands.first))
        XCTAssertEqual(engine.sentCommands, [.load(.a, clip)])
        XCTAssertEqual(clip.title, "voix_funk.wav")
        XCTAssertEqual(model.deckA.loadedEntry?.fileName, "voix_funk.wav")
        XCTAssertTrue(model.deckA.loadedClip === clip)
        XCTAssertEqual(model.deckA.activity, .idle)
        XCTAssertNil(model.deckB.loadedEntry)
        XCTAssertNil(model.deckB.loadedClip)
        XCTAssertEqual(decoder.decoded.map(\.lastPathComponent), ["voix_funk.wav"])
        XCTAssertEqual(decoder.decoded.first?.deletingLastPathComponent().lastPathComponent, "Banque de sons",
                       "the copy is decoded, never the source")
        XCTAssertEqual(model.libraryEntries.map(\.fileName), ["", "voix_funk.wav"])
        XCTAssertNil(model.alert)
    }

    /// UX §7.2 : pendant le chargement, « Importer » est désactivé sur la platine concernée ; l'autre
    /// platine reste libre.
    func testImportIsDisabledOnTheBusyDeckOnly() async throws {
        let decoder = FakeDecoder()
        decoder.holdDecoding()
        let model = makeModel(decoder: decoder)
        let source = try library.source("long.wav")
        let task = Task { await model.importAndLoad(source, on: .a) }
        while !decoder.hasStartedDecoding { await Task.yield() }

        XCTAssertEqual(model.deckA.activity, .loading)
        XCTAssertEqual(model.deckA.activityText, "Chargement…")
        XCTAssertFalse(model.deckA.isImportEnabled)
        model.importFile(on: .a)
        XCTAssertFalse(model.isImportPickerPresented, "no second import on a busy deck")
        XCTAssertTrue(model.deckB.isImportEnabled)
        model.importFile(on: .b)
        XCTAssertTrue(model.isImportPickerPresented)
        XCTAssertEqual(model.importPickerDeck, .b)

        decoder.releaseDecoding()
        await task.value
        XCTAssertEqual(model.deckA.activity, .idle)
        XCTAssertEqual(model.deckA.loadedEntry?.fileName, "long.wav")
    }

    /// CA 2, CA 4 — 6.1 « Annuler l'importation » : le sélecteur s'ouvre pour la platine d'origine ;
    /// l'annuler ne change rien ; un fichier choisi est importé sur cette platine.
    func testCancelledPickerChangesNothing_6_1() async throws {
        let engine = RecordingEngine()
        let model = makeModel(engine: engine)
        XCTAssertEqual(ImportPicker.contentTypes.map(\.identifier),
                       ["com.microsoft.waveform-audio", "public.aiff-audio", "public.mp3", "public.mpeg-4-audio"])

        model.importFile(on: .a)
        XCTAssertTrue(model.isImportPickerPresented)
        XCTAssertEqual(ImportPicker.message(for: model.importPickerDeck), "Importer sur la platine A")
        XCTAssertNil(model.finishImportPicking(.failure(CocoaError(.userCancelled))))
        XCTAssertFalse(model.isImportPickerPresented)
        model.importFile(on: .b)
        model.cancelImportPicking()
        XCTAssertEqual(engine.sentCommands, [])
        XCTAssertNil(model.alert)
        XCTAssertNil(model.deckA.loadedEntry)
        XCTAssertEqual(model.deckA.activity, .idle)

        model.importFile(on: .b)
        let task = try XCTUnwrap(model.finishImportPicking(.success(try library.source("beat.wav"))))
        await task.value
        XCTAssertEqual(model.deckB.loadedEntry?.fileName, "beat.wav")
        XCTAssertNil(model.deckA.loadedEntry)
    }

    /// CA 3 — SF-75 (`@P1`) : un contenu déjà présent charge l'entrée existante, sans nouvelle copie,
    /// avec le bandeau « Déjà dans la bibliothèque ».
    func testDuplicateImportLoadsExistingWithBanner_SF75() async throws {
        let model = makeModel()
        await model.importAndLoad(try library.source("boucle.wav", seed: 4), on: .a)
        let original = try XCTUnwrap(model.deckA.loadedEntry)
        await model.importAndLoad(try library.source("copie de boucle.wav", seed: 4), on: .b)

        XCTAssertEqual(model.deckB.loadedEntry, original)
        XCTAssertEqual(model.toasts.current?.text, "Déjà dans la bibliothèque : \(q("boucle.wav")) a été chargé.")
        XCTAssertEqual(model.libraryEntries.count, 2)
    }

    // MARK: - CA 5

    /// CA 5 — RM-48, 6.1 : chaque erreur donne l'alerte française de l'UX §8.3 ; aucune commande
    /// n'est envoyée et le son déjà chargé reste en place.
    func testEachLibraryErrorShowsFrenchAlertAndKeepsDeck_RM48() async throws {
        let engine = RecordingEngine()
        let decoder = FakeDecoder()
        let model = makeModel(engine: engine, decoder: decoder)
        await model.loadDemoAndWait(on: .a)
        engine.clearSentCommands()

        let probeErrors: [(LibraryError, String, String)] = [
            (.unsupportedFormat, "Format non pris en charge",
             "\(q("son.wav")) n'est pas un fichier audio pris en charge. Formats acceptés : WAV, AIFF, MP3 et M4A (AAC ou ALAC)."),
            (.protectedContent, "Fichier protégé",
             "\(q("son.wav")) est protégé contre la copie (DRM). Les fichiers protégés ne sont pas pris en charge."),
            (.corrupted, "Fichier illisible",
             "\(q("son.wav")) est vide ou endommagé. Aucun son n'a été ajouté à la bibliothèque."),
            (.tooLong(duration: 1_512.4), "Son trop long",
             "\(q("son.wav")) dure 25 min 12 s. La durée maximale est de 10 minutes par son."),
            (.tooShort(duration: 0.04), "Son trop court",
             "\(q("son.wav")) dure moins de 50 millisecondes, la durée minimale acceptée."),
        ]
        let source = try library.source("son.wav")
        for (error, title, message) in probeErrors {
            decoder.failNextProbe(with: error)
            await model.importAndLoad(source, on: .a)
            XCTAssertEqual(model.alert?.title, title, "\(error)")
            XCTAssertEqual(model.alert?.message, message, "\(error)")
            model.dismissAlert()
        }

        let full = makeModel(engine: engine, decoder: decoder, capacity: 10)
        await full.importAndLoad(source, on: .a)
        XCTAssertEqual(full.alert?.title, "Espace de stockage insuffisant")
        XCTAssertEqual(full.alert?.message,
                       "\(q("son.wav")) n'a pas pu être copié dans ScratchApp. Libérez de l'espace sur \(AppAlert.deviceName), puis réessayez.")

        await model.importAndLoad(library.sources.appendingPathComponent("absent.wav"), on: .a)
        XCTAssertEqual(model.alert?.title, "Échec de l'import")
        XCTAssertEqual(model.alert?.message, "\(q("absent.wav")) n'a pas pu être copié dans ScratchApp. Réessayez.")

        XCTAssertEqual(engine.sentCommands, [], "no command after an error")
        XCTAssertEqual(model.deckA.loadedEntry, demo, "the loaded sound is kept")
        XCTAssertEqual(model.deckA.activity, .idle)
        await model.refreshLibrary()
        XCTAssertEqual(model.libraryEntries, [demo], "nothing was added to the library")
    }

    /// CA 5 — D-11, 6.13 « Copie supprimée en dehors de l'application » : au lancement, les entrées
    /// retirées par `reconcile()` sont signalées une seule fois par un bandeau.
    func testLaunchReconcileShowsBanner_D11() async throws {
        let first = makeModel()
        await first.importAndLoad(try library.source("boucle.wav"), on: .a)
        try FileManager.default.removeItem(at: library.copyURL("boucle.wav"))

        let relaunched = makeModel()
        await relaunched.launch()
        XCTAssertEqual(relaunched.toasts.current?.text,
                       "\(q("boucle.wav")) a été retiré de la bibliothèque : sa copie a été supprimée ou modifiée en dehors de ScratchApp.")
        XCTAssertEqual(relaunched.libraryEntries, [demo])
        relaunched.toasts.dismiss()
        await relaunched.launch()
        XCTAssertNil(relaunched.toasts.current, "launch runs once")

        let three = (1 ... 3).map { LibraryEntry(contentHash: "", fileName: "s\($0).wav", fileSize: 1, title: "s\($0).wav",
                                                 duration: 1, importedAt: Date(), origin: .imported) }
        XCTAssertEqual(BannerText.launch(recovery: .none, removed: three),
                       "3 sons ont été retirés de la bibliothèque : leurs copies ont été supprimées ou modifiées en dehors de ScratchApp.")
        XCTAssertNil(BannerText.launch(recovery: .none, removed: []))
    }

    /// CA 5 — D-11, 6.13 « Charger un son dont la copie a disparu » : alerte « Son introuvable »,
    /// liste mise à jour, aucune commande ; le son déjà chargé continue depuis la mémoire.
    func testMissingCopyOnLoadShowsSonIntrouvable_D11() async throws {
        let engine = RecordingEngine()
        let model = makeModel(engine: engine)
        await model.importAndLoad(try library.source("boucle.wav"), on: .a)
        let entry = try XCTUnwrap(model.deckA.loadedEntry)
        let clip = model.deckA.loadedClip
        try FileManager.default.removeItem(at: library.copyURL("boucle.wav"))
        engine.clearSentCommands()

        await model.load(entry, on: .b)
        XCTAssertEqual(model.alert?.title, "Son introuvable")
        XCTAssertEqual(model.alert?.message,
                       "La copie de \(q("boucle.wav")) a été supprimée ou modifiée en dehors de ScratchApp. Ce son a été retiré de la bibliothèque ; importez-le de nouveau.")
        XCTAssertEqual(engine.sentCommands, [])
        XCTAssertEqual(model.libraryEntries, [demo])
        XCTAssertTrue(model.deckA.loadedClip === clip, "the loaded sound keeps playing from memory")
        XCTAssertNil(model.deckB.loadedEntry)
    }

    // MARK: - CA 6

    /// CA 6 — SF-76, RM-01, RM-57 : « Charger la démo » envoie `.load` seul (aucun moteur démarré) ;
    /// le clip est généré une fois et partagé entre A et B.
    func testLoadDemoSendsLoadWithoutMotor_SF76() async throws {
        let engine = RecordingEngine()
        let model = makeModel(engine: engine)
        await model.loadDemoAndWait(on: .a)
        await model.loadDemoAndWait(on: .b)

        let clipA = try XCTUnwrap(model.deckA.loadedClip)
        XCTAssertEqual(engine.sentCommands, [.load(.a, clipA), .load(.b, clipA)])
        XCTAssertTrue(model.deckB.loadedClip === clipA, "one demo clip shared by both decks")
        XCTAssertEqual(clipA.title, "Son de démonstration")
        XCTAssertEqual(model.deckA.loadedEntry, demo)
        XCTAssertEqual(model.deckB.loadedEntry, demo)
    }

    // MARK: - CA 7

    /// CA 7 — SF-15, D-19, D-40, 6.5. Platine chargée et active : confirmation ; refus → son
    /// conservé, nouveau son en bibliothèque, bandeau. Acceptation → remplacement. Platine chargée
    /// à l'arrêt, ou vide en rotation : chargement direct.
    func testReplacementRules_SF15_D40() async throws {
        let engine = RecordingEngine()
        let model = makeModel(engine: engine)
        await model.loadDemoAndWait(on: .a)
        let demoClip = try XCTUnwrap(model.deckA.loadedClip)
        engine.snapshot = Self.snapshot(a: DeckSnapshot(clipID: demoClip.id, durationSeconds: 8, motorOn: true))
        model.tick()
        engine.clearSentCommands()

        await model.importAndLoad(try library.source("nouveau.wav", seed: 2), on: .a)
        let confirmation = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(confirmation.title, "Remplacer le son de la platine A\(nbsp)?")
        XCTAssertEqual(confirmation.message,
                       "La platine A est en cours d'utilisation. \(q("Son de démonstration")) sera remplacé par \(q("nouveau.wav")) et la platine s'arrêtera. \(q("Son de démonstration")) reste dans la bibliothèque.")
        XCTAssertEqual(engine.sentCommands, [], "nothing is loaded before the answer")
        XCTAssertNil(model.resolveConfirmation(replace: false))
        XCTAssertEqual(engine.sentCommands, [])
        XCTAssertEqual(model.deckA.loadedEntry, demo, "refusal keeps the sound and its state")
        XCTAssertEqual(model.toasts.current?.text, "\(q("nouveau.wav")) a été ajouté à la bibliothèque.")
        XCTAssertTrue(model.libraryEntries.contains { $0.fileName == "nouveau.wav" })

        await model.importAndLoad(try library.source("autre.wav", seed: 3), on: .a)
        XCTAssertNotNil(model.confirmation)
        await model.resolveConfirmation(replace: true)?.value
        let replacement = try XCTUnwrap(loadedClip(engine.sentCommands.last))
        XCTAssertEqual(engine.sentCommands, [.load(.a, replacement)])
        XCTAssertEqual(model.deckA.loadedEntry?.fileName, "autre.wav")
        XCTAssertNil(model.confirmation)

        // Loaded but stopped: direct replacement (D-40).
        engine.snapshot = Self.snapshot(a: DeckSnapshot(clipID: replacement.id, durationSeconds: 1))
        engine.clearSentCommands()
        await model.loadDemoAndWait(on: .a)
        XCTAssertNil(model.confirmation)
        XCTAssertEqual(engine.sentCommands.count, 1)

        // Empty deck with a spinning platter: nothing to replace, direct load.
        engine.snapshot = Self.snapshot(b: DeckSnapshot(motorOn: true))
        engine.clearSentCommands()
        await model.loadDemoAndWait(on: .b)
        XCTAssertNil(model.confirmation)
        XCTAssertEqual(engine.sentCommands.count, 1)

        // The demo on an active deck asks too; refusing it shows no banner.
        engine.snapshot = Self.snapshot(b: DeckSnapshot(clipID: demoClip.id, durationSeconds: 8, isHeld: true))
        model.toasts.dismiss()
        await model.loadDemoAndWait(on: .b)
        XCTAssertEqual(model.confirmation?.deck, .b)
        model.resolveConfirmation(replace: false)
        XCTAssertNil(model.toasts.current)
    }

    // MARK: - CA 8

    /// CA 8 : platines qui portent une entrée (RM-57) et déchargement.
    func testDecksCarryingEntryAndUnload() async throws {
        let engine = RecordingEngine()
        let model = makeModel(engine: engine)
        await model.loadDemoAndWait(on: .a)
        await model.loadDemoAndWait(on: .b)
        XCTAssertEqual(model.decks(carrying: LibraryEntry.demoID), [.a, .b])

        engine.clearSentCommands()
        model.unload(.a)
        XCTAssertEqual(engine.sentCommands, [.unload(.a)])
        XCTAssertNil(model.deckA.loadedEntry)
        XCTAssertEqual(model.decks(carrying: LibraryEntry.demoID), [.b])
        XCTAssertEqual(model.decks(carrying: UUID()), [])
    }

    // MARK: - CA 10

    /// CA 10 — D-49, NFR12 : un index illisible au lancement donne le bandeau « réinitialisée »,
    /// une seule fois. Un index partiellement illisible donne son bandeau, prioritaire sur celui des
    /// entrées retirées par `reconcile()`.
    func testUnreadableIndexShowsBannerOnce_D49() async throws {
        try FileManager.default.createDirectory(at: library.locations.supportDirectory, withIntermediateDirectories: true)
        try Data("{ pas du JSON".utf8).write(to: library.locations.libraryIndexURL)
        let reset = makeModel()
        await reset.launch()
        XCTAssertEqual(reset.toasts.current?.text,
                       "La bibliothèque était illisible : elle a été réinitialisée. Importez de nouveau vos sons.")
        let next = makeModel()
        await next.launch()
        XCTAssertNil(next.toasts.current, "the unreadable index was set aside once")

        // One valid entry whose copy has disappeared, plus one unreadable entry.
        let gone = LibraryEntry(contentHash: String(repeating: "0", count: 64), fileName: "parti.wav", fileSize: 10,
                                title: "parti.wav", duration: 1, importedAt: Date(timeIntervalSince1970: 1_794_000_000),
                                origin: .imported)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let goneJSON = String(decoding: try encoder.encode(gone), as: UTF8.self)
        try Data(#"{"version": 1, "entries": [\#(goneJSON), {"id": "x"}]}"#.utf8).write(to: library.locations.libraryIndexURL)
        let partial = makeModel()
        await partial.launch()
        XCTAssertEqual(partial.toasts.current?.text,
                       "Une partie de la bibliothèque était illisible : les sons concernés en ont été retirés. Importez-les de nouveau si besoin.")
        XCTAssertEqual(partial.libraryEntries, [demo], "the missing copy was reconciled too")
        let after = makeModel()
        await after.launch()
        XCTAssertNil(after.toasts.current)
    }

    // MARK: - Textes et bandeaux

    /// UX §8.3, §5.21 : durée d'un son trop long, appareil, durée d'affichage des bandeaux, un seul
    /// bandeau à la fois.
    func testTextsAndToastQueue() async {
        XCTAssertEqual(AppAlert.durationText(1_512.9), "25 min 12 s")
        XCTAssertEqual(AppAlert.durationText(720), "12 min")
        XCTAssertEqual(AppAlert.durationText(40), "40 s")
        #if os(macOS)
        XCTAssertEqual(AppAlert.deviceName, "ce Mac")
        #endif
        XCTAssertEqual(Toast(text: String(repeating: "a", count: 80)).duration, 4)
        XCTAssertEqual(Toast(text: String(repeating: "a", count: 81)).duration, 6)

        let center = ToastCenter()
        center.show("premier")
        let first = center.current
        center.show("second")
        XCTAssertEqual(center.current?.text, "second", "the most recent banner replaces the previous one")
        center.dismiss(first)
        XCTAssertEqual(center.current?.text, "second", "dismissing a replaced banner does nothing")
        center.dismiss()
        XCTAssertNil(center.current)
    }
}
