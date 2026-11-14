import Foundation
import Observation
import ScratchCore
import ScratchLibrary
import XCTest
@testable import ScratchUI

/// Modèle de présentation d'une platine (story 4.1) : textes, états des boutons, points d'accroche
/// de l'`AppModel`, valeurs VoiceOver.
@MainActor
final class DeckViewModelTests: XCTestCase {
    private func loaded(position: Double, duration: Double = 225, clip: AudioClip? = nil) -> DeckSnapshot {
        DeckSnapshot(clipID: (clip ?? Self.clip).id, durationSeconds: duration, positionSeconds: position)
    }

    private static let clip = PreviewDeckIntents.syntheticClip(title: "voix_funk.wav", duration: 225)

    // AC4 — SF-03, D-28 (scénario « Format de position »)
    func testPositionAndDurationFormats_SF03() async {
        let deck = DeckViewModel(deck: .a, engine: RecordingEngine())
        XCTAssertEqual(deck.positionText, "--:--,-")
        XCTAssertEqual(deck.durationText, "--:--,-")
        deck.apply(loaded(position: 12.34))
        XCTAssertEqual(deck.positionText, "00:12,3")
        XCTAssertEqual(deck.durationText, "03:45,0")
        deck.apply(loaded(position: -1.25))
        XCTAssertEqual(deck.positionText, "\u{2212}00:01,2", "lead-in: U+2212 sign, tenth rounded down")
        deck.apply(loaded(position: 12.39))
        XCTAssertEqual(deck.positionText, "00:12,3", "rounded down to the tenth")
        deck.apply(loaded(position: 12.3))
        XCTAssertEqual(deck.positionText, "00:12,3", "12.3 stored as 12.2999… still reads 12,3")
        deck.apply(loaded(position: 599.99, duration: 600))
        XCTAssertEqual(deck.positionText, "09:59,9")
        XCTAssertEqual(deck.durationText, "10:00,0")
        deck.apply(.initial)
        XCTAssertEqual(deck.positionText, "--:--,-")
        XCTAssertEqual(deck.durationText, "--:--,-")
    }

    // AC4 — UX §5.10, §10.2 : le texte de position ne change que lorsque le dixième change.
    func testPositionTextChangesOnlyWhenTenthChanges() async {
        let deck = DeckViewModel(deck: .a, engine: RecordingEngine())
        deck.apply(loaded(position: 12.31))
        let notified = Flag()
        withObservationTracking { _ = deck.positionText } onChange: { notified.isSet = true }
        deck.apply(loaded(position: 12.34))
        deck.apply(loaded(position: 12.36))
        XCTAssertFalse(notified.isSet, "same tenth: no change notification")
        deck.apply(loaded(position: 12.41))
        XCTAssertTrue(notified.isSet)
        XCTAssertEqual(deck.positionText, "00:12,4")
    }

    // AC3 — SF-04, SF-05, UX §5.2 : le bouton suit la commande, pas la vitesse réelle.
    func testStartStopReflectsCommandedState_SF04_SF05() async {
        let engine = RecordingEngine()
        let deck = DeckViewModel(deck: .a, engine: engine)
        XCTAssertEqual(deck.startStopTitle, "START")
        XCTAssertEqual(deck.startStopAccessibilityLabel, "START, platine A")
        XCTAssertEqual(deck.startStopAccessibilityValue, "moteur arrêté")
        var accelerating = loaded(position: 0)
        accelerating.motorOn = true
        accelerating.playbackRate = 0.3
        deck.apply(accelerating)
        XCTAssertEqual(deck.startStopTitle, "STOP", "STOP while accelerating")
        XCTAssertEqual(deck.startStopAccessibilityValue, "moteur en marche")
        var braking = accelerating
        braking.motorOn = false
        braking.playbackRate = 0.8
        deck.apply(braking)
        XCTAssertEqual(deck.startStopTitle, "START", "START while braking (6.2)")
        deck.toggleMotor()
        XCTAssertEqual(engine.sentCommands, [.motor(.a, on: true)], "a press while braking restarts")
        XCTAssertEqual(deck.startStopTitle, "STOP")
    }

    // AC3 — RM-02
    func testSpeedDefaultsTo33_RM02() async {
        let engine = RecordingEngine()
        let deck = DeckViewModel(deck: .b, engine: engine)
        XCTAssertEqual(deck.speed, .rpm33)
        deck.setSpeed(.rpm45)
        XCTAssertEqual(deck.speed, .rpm45)
        XCTAssertEqual(engine.sentCommands, [.speed(.b, .rpm45)])
    }

    // AC5 — SF-01 ; AC4 — pastilles et « Importer » désactivé (UX §7.2).
    func testEmptyDeckOffersImportAndDemo_SF01() async {
        let deck = DeckViewModel(deck: .a, engine: RecordingEngine())
        XCTAssertTrue(deck.showsEmptyActions)
        XCTAssertTrue(deck.isImportEnabled)
        XCTAssertEqual(deck.title, "Aucun son")
        XCTAssertFalse(deck.hasTitle)
        XCTAssertNil(deck.activityText)
        deck.activity = .importing(fileName: "voix_funk.wav")
        XCTAssertFalse(deck.showsEmptyActions, "an activity indicator replaces the empty actions")
        XCTAssertFalse(deck.isImportEnabled)
        XCTAssertEqual(deck.activityText, "Import de \u{AB}\u{A0}voix_funk.wav\u{A0}\u{BB}\u{2026}")
        deck.activity = .loading
        XCTAssertEqual(deck.activityText, "Chargement\u{2026}")
        deck.activity = .idle
        deck.apply(loaded(position: 0))
        XCTAssertFalse(deck.showsEmptyActions)
        var atEnd = loaded(position: 225)
        atEnd.isAtEnd = true
        deck.apply(atEnd)
        XCTAssertTrue(deck.isAtEnd, "« Fin du son » pill")
    }

    // AC5 — PO-01, scénario « START sur une platine vide » (6.2 « Démarrer sans fichier »).
    func testStartOnEmptyDeckSpinsAndHighlights_PO01() async {
        let engine = RecordingEngine()
        let deck = DeckViewModel(deck: .a, engine: engine)
        deck.toggleMotor()
        XCTAssertEqual(engine.sentCommands, [.motor(.a, on: true)])
        XCTAssertEqual(deck.emptyDeckHighlightCount, 1, "Importer and Charger la démo are highlighted")
        XCTAssertEqual(deck.emptyStartAnnouncement,
                       "Aucun son chargé sur la platine A. Importez un fichier ou chargez la démo.")
        deck.toggleMotor()
        deck.apply(loaded(position: 0))
        deck.toggleMotor()
        XCTAssertEqual(deck.emptyDeckHighlightCount, 1, "no highlight on a loaded deck")
        engine.acceptsCommands = false
        deck.apply(.initial)
        deck.setMotor(true)
        XCTAssertEqual(deck.emptyDeckHighlightCount, 1, "a lost command changes nothing")
    }

    // AC7 — scénario « Le titre ne disparaît pas avant l'application du chargement ».
    func testLoadedEntryIsNotClearedBeforeLoadIsApplied() async {
        let deck = DeckViewModel(deck: .a, engine: RecordingEngine())
        let first = PreviewDeckIntents.syntheticClip(title: "a.wav", duration: 10)
        deck.loadedClip = first
        deck.loadedEntry = Self.entry("a.wav")
        deck.apply(.initial)
        XCTAssertEqual(deck.loadedEntry?.title, "a.wav", "load not applied yet: kept")
        deck.apply(loaded(position: 0, duration: 10, clip: first))
        XCTAssertEqual(deck.title, "a.wav")

        // Replacing: the previous clip is still shown until `.load` is applied.
        let second = PreviewDeckIntents.syntheticClip(title: "b.wav", duration: 20)
        deck.loadedClip = second
        deck.loadedEntry = Self.entry("b.wav")
        deck.apply(loaded(position: 3, duration: 10, clip: first))
        XCTAssertEqual(deck.loadedEntry?.title, "b.wav", "older clip still on deck: kept")
        deck.apply(loaded(position: 0, duration: 20, clip: second))
        XCTAssertEqual(deck.loadedClip?.id, second.id)

        // Unloaded after being shown: cleared.
        deck.apply(.initial)
        XCTAssertNil(deck.loadedEntry)
        XCTAssertNil(deck.loadedClip)
        XCTAssertEqual(deck.title, "Aucun son")

        // Superseded by a newer clip: cleared.
        deck.loadedClip = PreviewDeckIntents.syntheticClip(title: "c.wav", duration: 5)
        deck.loadedEntry = Self.entry("c.wav")
        let newer = PreviewDeckIntents.syntheticClip(title: "d.wav", duration: 5)
        deck.apply(loaded(position: 0, duration: 5, clip: newer))
        XCTAssertNil(deck.loadedEntry)
    }

    // AC4 — D-12 : titre = nom de la copie locale ; démo « Son de démonstration ».
    func testTitleIsLocalCopyNameOrDemo_D12() async {
        let deck = DeckViewModel(deck: .b, engine: RecordingEngine())
        deck.loadedEntry = Self.entry("voix_funk_2.wav")
        XCTAssertEqual(deck.title, "voix_funk_2.wav")
        XCTAssertEqual(deck.headerAccessibilityLabel, "Platine B, \u{AB}\u{A0}voix_funk_2.wav\u{A0}\u{BB}")
        deck.loadedEntry = .demo(title: DemoSound.title, duration: DemoSound.duration)
        XCTAssertEqual(deck.title, "Son de démonstration")
    }

    // AC9 — SF-83, UX §5.1, §5.10, §11.2.
    func testAccessibilityValuesForDisc_SF83() async {
        let deck = DeckViewModel(deck: .a, engine: RecordingEngine())
        XCTAssertEqual(deck.discAccessibilityValue, "vide")
        XCTAssertEqual(deck.headerAccessibilityValue, "aucun son")
        deck.apply(loaded(position: 0))
        XCTAssertEqual(deck.discAccessibilityValue, "à l'arrêt, position 0 seconde")
        var playing = loaded(position: 12.34)
        playing.motorOn = true
        playing.playbackRate = 1
        deck.apply(playing)
        XCTAssertEqual(deck.discAccessibilityValue, "en rotation, 33 tours un tiers, position 12,3 secondes")
        XCTAssertEqual(deck.headerAccessibilityValue, "position 12,3 secondes sur 3 minutes 45 secondes")
        var held = loaded(position: 8.2)
        held.isHeld = true
        deck.apply(held)
        XCTAssertEqual(deck.discAccessibilityValue, "tenu, position 8,2 secondes")
        var atEnd = loaded(position: 225)
        atEnd.isAtEnd = true
        deck.apply(atEnd)
        XCTAssertEqual(deck.discAccessibilityValue, "fin du son")
        XCTAssertEqual(DeckFormatting.spokenTime(tenths: 723), "1 minute 12,3 secondes")
        XCTAssertEqual(DeckFormatting.spokenTime(tenths: -12), "moins 1,2 seconde")
        XCTAssertEqual(DeckFormatting.spokenSpeed(.rpm45), "45 tours")
    }

    private final class Flag: @unchecked Sendable {
        var isSet = false
    }

    private static func entry(_ title: String) -> LibraryEntry {
        LibraryEntry(contentHash: "", fileName: title, fileSize: 1, title: title, duration: 10,
                     importedAt: Date(timeIntervalSince1970: 0), origin: .imported)
    }
}
