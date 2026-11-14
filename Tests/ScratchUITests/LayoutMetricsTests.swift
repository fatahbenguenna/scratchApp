import Foundation
import ScratchAudio
import ScratchCore
import ScratchLibrary
import XCTest
@testable import ScratchUI

/// Dispositions iPhone et iPad (story 4.4 ; UX §4.1 à §4.5, §5.18 ; D-29). Tailles de la zone sûre.
@MainActor
final class LayoutMetricsTests: XCTestCase {
    // AC1 — UX §4.1, D-29 : la disposition dépend de la taille de la fenêtre.
    func testLayoutSelectionRule_UX4_1() async {
        XCTAssertEqual(LayoutMetrics.kind(width: 393, height: 759, isMac: true), .sideBySide, "macOS: always A | B")
        XCTAssertEqual(LayoutMetrics.kind(width: 393, height: 759, isMac: false), .singleDeck, "iPhone portrait")
        XCTAssertEqual(LayoutMetrics.kind(width: 500, height: 1100, isMac: false), .singleDeck,
                       "iPad Split View narrower than 600")
        XCTAssertEqual(LayoutMetrics.kind(width: 734, height: 372, isMac: false), .compactSideBySide, "iPhone landscape")
        XCTAssertEqual(LayoutMetrics.kind(width: 820, height: 1136, isMac: false), .stacked, "iPad portrait")
        XCTAssertEqual(LayoutMetrics.kind(width: 1180, height: 776, isMac: false), .sideBySide, "iPad landscape")
    }

    // AC2 à AC4, AC8 — P de l'UX pour les tailles de référence (± 1 pt).
    func testReferencePlatterSizes() async {
        let iPhone = LayoutMetrics.singleDeck(width: 393, height: 759)
        XCTAssertEqual(iPhone.platter, 309, accuracy: 1, "iPhone 15 portrait")
        XCTAssertEqual(iPhone.idiom, .phone)
        let iPhoneSE = LayoutMetrics.singleDeck(width: 375, height: 647)
        XCTAssertEqual(iPhoneSE.idiom, .phoneCompact, "usable height < 700: compact variant")
        XCTAssertEqual(iPhoneSE.platter, 229, accuracy: 1)
        XCTAssertEqual(LayoutMetrics.singleDeck(width: 375, height: 728).platter, 280, accuracy: 1, "iPhone 13 mini")

        let landscape = LayoutMetrics.compactSideBySide(width: 734, height: 372)
        XCTAssertEqual(landscape.platter, 174, accuracy: 1, "iPhone 15 landscape")
        XCTAssertEqual(landscape.columnWidth, 236)
        XCTAssertEqual(landscape.mixerWidth, 246)
        XCTAssertEqual(landscape.columnChrome, 198)
        XCTAssertEqual(landscape.gap, 8)
        XCTAssertEqual(LayoutMetrics.compactSideBySide(width: 832, height: 419).platter, 221, accuracy: 1,
                       "iPhone 16 Pro Max landscape")

        let portrait = LayoutMetrics.stacked(width: 820, height: 1136)
        XCTAssertEqual(portrait.platter, 432, accuracy: 1, "iPad (10th gen) portrait")
        XCTAssertEqual(LayoutMetrics.bandHeight(height: 1136), 456)
        XCTAssertEqual(portrait.mixerWidth, 780, "bands and mixer are 780 wide")
        XCTAssertEqual(LayoutMetrics.stacked(width: 768, height: 1004).platter, 380, accuracy: 1, "iPad (6th gen)")
        XCTAssertEqual(LayoutMetrics.stacked(width: 1032, height: 1332).platter, 554, accuracy: 1, "iPad Pro 13 pouces")

        XCTAssertEqual(MainLayoutMetrics(width: 1180, height: 776, idiom: .tablet).platter, 362, "iPad landscape")
        XCTAssertEqual(MainLayoutMetrics(width: 1200, height: 760, idiom: .mac).platter, 396, "Mac")
    }

    // AC2 — UX §5.18 : pastilles et valeurs VoiceOver du sélecteur de platine.
    func testDeckSelectorStates() async {
        let engine = RecordingEngine()
        let deck = DeckViewModel(deck: .b, engine: engine)
        XCTAssertEqual(DeckSelector.dot(for: deck), .none)
        XCTAssertEqual(DeckSelector.accessibilityValue(for: deck, displayed: false), "vide")
        let clip = PreviewDeckIntents.syntheticClip(title: "b.wav", duration: 10)
        deck.apply(DeckSnapshot(clipID: clip.id, durationSeconds: 10))
        XCTAssertEqual(DeckSelector.dot(for: deck), .hollow)
        XCTAssertEqual(DeckSelector.accessibilityValue(for: deck, displayed: false), "son chargé, à l'arrêt")
        deck.setMotor(true)
        XCTAssertEqual(DeckSelector.dot(for: deck), .filled)
        XCTAssertEqual(DeckSelector.accessibilityValue(for: deck, displayed: true), "affichée, moteur en marche")
    }

    // AC2, AC7 — RM-60 : changer de platine affichée ou de disposition relâche un disque tenu.
    func testCancellingReleasesAHeldDisc_RM60() async {
        let engine = RecordingEngine()
        let deck = DeckViewModel(deck: .a, engine: engine)
        let clip = PreviewDeckIntents.syntheticClip(title: "a.wav", duration: 10)
        deck.apply(DeckSnapshot(clipID: clip.id, durationSeconds: 10))
        deck.discInput.updateGeometry(width: 200, height: 200)
        deck.discInput.contactBegan(1, at: ContactSample(x: 100, y: 20, time: 1))
        XCTAssertTrue(deck.discInput.isHolding)
        deck.discInput.cancelAll(time: 2)
        XCTAssertFalse(deck.discInput.isHolding)
        XCTAssertEqual(engine.sentCommands.last, .touchEnded(.a, time: 2))
        XCTAssertFalse(engine.sentCommands.contains { if case .motor = $0 { return true } else { return false } },
                       "motors unchanged")
    }
}
