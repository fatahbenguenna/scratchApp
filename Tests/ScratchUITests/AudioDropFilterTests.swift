import Foundation
import ScratchCore
import ScratchLibrary
import UniformTypeIdentifiers
import XCTest
@testable import ScratchUI

/// Glisser-déposer sur une platine (story 5.2 ; SF-73, D-27, UX §5.9).
@MainActor
final class AudioDropFilterTests: XCTestCase {
    /// Double de `DeckIntents` : enregistre les fichiers déposés.
    private final class RecordingIntents: DeckIntents {
        var dropped: [(URL, DeckID)] = []
        func importFile(on deck: DeckID) {}
        func loadDemo(on deck: DeckID) {}
        func importDroppedFile(_ url: URL, on deck: DeckID) { dropped.append((url, deck)) }
        func openLibrary() {}
        func openSettings() {}
        func revealLibraryInFinder() {}
    }

    /// CA 1, 2 — SF-73 : un seul fichier WAV, AIFF, MP3 ou M4A (AAC, ALAC) est accepté.
    func testAcceptsSingleAudioFile_SF73() {
        let audio = ["com.microsoft.waveform-audio", "public.aiff-audio", "public.mp3", "public.mpeg-4-audio",
                     "com.apple.m4a-audio"]
        for identifier in audio {
            XCTAssertEqual(AudioDropFilter.evaluate(itemTypes: [[identifier]], isBusy: false), .accept, identifier)
        }
        XCTAssertEqual(AudioDropFilter.evaluate(itemTypes: [["public.data", "public.mp3"]], isBusy: false), .accept)
        XCTAssertEqual(AudioDropFilter.audioType(in: ["public.data", "com.apple.m4a-audio"])?.identifier,
                       "com.apple.m4a-audio")
    }

    /// CA 3 — 6.13 « Déposer un fichier non audio » : PDF, texte, image, ou audio d'un format non
    /// pris en charge, refusés dès le survol.
    func testRejectsNonAudio_6_13() {
        for identifier in ["com.adobe.pdf", "public.plain-text", "public.png", "org.xiph.flac", "public.folder"] {
            XCTAssertEqual(AudioDropFilter.evaluate(itemTypes: [[identifier]], isBusy: false),
                           .reject(.unsupportedFormat), identifier)
        }
        XCTAssertEqual(AudioDropFilter.evaluate(itemTypes: [], isBusy: false), .reject(.unsupportedFormat))
        XCTAssertEqual(AudioDropRejection.unsupportedFormat.message, "Format non pris en charge")
    }

    /// CA 4 — D-27, 6.13 « Déposer plusieurs fichiers à la fois » : refusé dès le survol.
    func testRejectsMultipleFiles_D27() {
        XCTAssertEqual(AudioDropFilter.evaluate(itemTypes: [["public.mp3"], ["public.mp3"]], isBusy: false),
                       .reject(.multipleFiles))
        XCTAssertEqual(AudioDropRejection.multipleFiles.message, "Un seul fichier à la fois")
    }

    /// CA 5 : pendant un import sur la platine, le survol est refusé (« Import en cours… »).
    func testRejectsWhileImporting() {
        XCTAssertEqual(AudioDropFilter.evaluate(itemTypes: [["public.mp3"]], isBusy: true), .reject(.importInProgress))
        XCTAssertEqual(AudioDropRejection.importInProgress.message, "Import en cours…")
    }

    /// CA 1, 3 : un fichier du Finder n'annonce que son URL ; son extension décide.
    func testFinderFileURLsAreClassifiedByExtension() {
        XCTAssertEqual(AudioDropFilter.evaluate(itemTypes: [["public.file-url"]], isBusy: false), .resolveFileURL)
        for name in ["a.wav", "B.WAV", "c.aiff", "d.aif", "e.mp3", "f.m4a"] {
            XCTAssertTrue(AudioDropFilter.isAcceptedFile(URL(fileURLWithPath: "/tmp/\(name)")), name)
        }
        for name in ["doc.pdf", "notes.txt", "sans-extension", "son.flac"] {
            XCTAssertFalse(AudioDropFilter.isAcceptedFile(URL(fileURLWithPath: "/tmp/\(name)")), name)
        }
    }

    /// CA 1, 3 à 5 — UX §5.9 : états et textes de la zone ; une résolution tardive d'un survol
    /// terminé est ignorée.
    func testDropZoneStatesAndTexts_UX59() {
        let zone = DeckDropZoneModel(deck: .a)
        XCTAssertNil(zone.text)
        zone.enter(itemTypes: [["public.mp3"]], isBusy: false)
        XCTAssertEqual(zone.text, "Déposer pour charger sur la platine A")
        XCTAssertTrue(zone.acceptsDrop)
        zone.exit()
        XCTAssertEqual(zone.state, .inactive)

        zone.enter(itemTypes: [["public.mp3"], ["public.mp3"]], isBusy: false)
        XCTAssertEqual(zone.text, "Un seul fichier à la fois")
        XCTAssertFalse(zone.acceptsDrop)

        let token = zone.enter(itemTypes: [["public.file-url"]], isBusy: false)
        XCTAssertNotNil(token)
        XCTAssertTrue(zone.acceptsDrop, "accepted until the URL is known")
        zone.didResolve(URL(fileURLWithPath: "/tmp/document.pdf"), session: try! XCTUnwrap(token))
        XCTAssertEqual(zone.state, .rejected(.unsupportedFormat))

        let late = try! XCTUnwrap(zone.enter(itemTypes: [["public.file-url"]], isBusy: false))
        zone.exit()
        zone.didResolve(URL(fileURLWithPath: "/tmp/document.pdf"), session: late)
        XCTAssertEqual(zone.state, .inactive, "a late resolution never shows a stale zone")

        let busyZone = DeckDropZoneModel(deck: .b)
        busyZone.enter(itemTypes: [["public.mp3"]], isBusy: true)
        XCTAssertEqual(busyZone.text, "Import en cours…")
    }

    /// CA 2 : le fichier déposé est remis à l'intention de cette platine, et d'elle seule.
    func testDropTriggersImportIntentForThatDeck() {
        let intents = RecordingIntents()
        let zone = DeckDropZoneModel(deck: .b)
        let url = URL(fileURLWithPath: "/tmp/voix_funk.wav")
        zone.deliver(url, to: intents)
        zone.deliver(nil, to: intents)
        XCTAssertEqual(intents.dropped.map { $0.0 }, [url])
        XCTAssertEqual(intents.dropped.map { $0.1 }, [.b])
    }

    /// CA 2 (iPad, Fichiers) : la copie temporaire garde le nom d'origine ; l'import la charge sur la
    /// platine, puis la supprime ; un fichier du Finder n'est jamais supprimé.
    func testStagedDropIsImportedThenRemoved() async throws {
        let library = try TemporaryLibrary()
        defer { library.remove() }
        let decoder = FakeDecoder()
        let store = library.makeStore(decoder: decoder)
        let model = AppModel(engine: RecordingEngine(), host: nil, library: store,
                             preferences: InMemoryPreferencesStore(), decoder: decoder)

        let representation = try library.source("tmp-4F2A.wav")
        let staged = try XCTUnwrap(DroppedFileLoader.stage(representation, suggestedName: "boucle", type: .wav))
        XCTAssertEqual(staged.lastPathComponent, "boucle.wav")
        XCTAssertTrue(DroppedFileLoader.isStaged(staged))
        await model.importDroppedFileAndWait(staged, on: .b)
        XCTAssertEqual(model.deckB.loadedEntry?.fileName, "boucle.wav")
        XCTAssertNil(model.deckA.loadedEntry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.deletingLastPathComponent().path))

        let finderFile = try library.source("finder.wav", seed: 2)
        XCTAssertFalse(DroppedFileLoader.isStaged(finderFile))
        await model.importDroppedFileAndWait(finderFile, on: .a)
        XCTAssertEqual(model.deckA.loadedEntry?.fileName, "finder.wav")
        XCTAssertTrue(FileManager.default.fileExists(atPath: finderFile.path), "a Finder file is never removed")
    }

    /// Suivi de la gate 5.2 : un chemin contenant `..` ne sort jamais du dossier des dépôts ; seule
    /// une copie de dépôt est supprimée, jamais un fichier voisin.
    func testStagedPathsCannotEscapeWithDotDot() throws {
        let staging = DroppedFileLoader.stagingDirectory
        let escaping = staging.appendingPathComponent("abc/../../ScratchApp-Drops-voisin/boucle.wav")
        XCTAssertFalse(DroppedFileLoader.isStaged(escaping))
        XCTAssertFalse(DroppedFileLoader.isStaged(staging.appendingPathComponent("../boucle.wav")))
        XCTAssertTrue(DroppedFileLoader.isStaged(staging.appendingPathComponent("abc/../def/boucle.wav")))

        let neighbour = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScratchApp-Drops-voisin-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: neighbour, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: neighbour) }
        let outside = neighbour.appendingPathComponent("boucle.wav")
        try Data("original".utf8).write(to: outside)
        DroppedFileLoader.removeStaged(staging.appendingPathComponent("x/../../\(neighbour.lastPathComponent)/boucle.wav"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path), "a path with .. never deletes outside the drops")
    }

    /// Suivi de la gate 5.2 : le lancement purge les copies laissées par un dépôt interrompu ; une
    /// copie récente (dépôt en cours) est gardée.
    func testLaunchPurgesInterruptedDrops() async throws {
        let library = try TemporaryLibrary()
        defer { library.remove() }
        let stale = try XCTUnwrap(DroppedFileLoader.stage(try library.source("interrompu.wav"), suggestedName: nil, type: .wav))
        let fresh = try XCTUnwrap(DroppedFileLoader.stage(try library.source("en-cours.wav", seed: 2), suggestedName: nil, type: .wav))
        defer { DroppedFileLoader.removeStaged(fresh) }
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-86_400)],
                                              ofItemAtPath: stale.deletingLastPathComponent().path)
        let decoder = FakeDecoder()
        let model = AppModel(engine: RecordingEngine(), host: nil, library: library.makeStore(decoder: decoder),
                             preferences: InMemoryPreferencesStore(), decoder: decoder)
        await model.launch()
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.deletingLastPathComponent().path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fresh.path), "a recent drop is never purged")
    }
}
