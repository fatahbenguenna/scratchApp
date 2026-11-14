import ScratchCore
import XCTest
@testable import ScratchUI

/// Pitch, CUE et résistance (story 4.5 ; SF-11, SF-13, SF-21, SF-83 ; UX §5.4 à §5.6).
@MainActor
final class PitchCueResistanceTests: XCTestCase {
    private let engine = RecordingEngine()

    private func loadedDeck(position: Double = 12.34, cue: Double? = nil, held: Bool = false) -> DeckViewModel {
        let deck = DeckViewModel(deck: .a, engine: engine)
        let clip = PreviewDeckIntents.syntheticClip(title: "a.wav", duration: 225)
        deck.apply(DeckSnapshot(clipID: clip.id, durationSeconds: 225, positionSeconds: position, isHeld: held,
                                cueSeconds: cue))
        return deck
    }

    // AC1 — SF-11, UX §5.4 : toute la course = 16 points, pas de 0,1 %, cran de 6 pt à 0 %.
    func testPitchDragMapsFullTravelToSixteenPoints_SF11() async {
        var drag = FaderDragModel.pitch(travel: 160)
        drag.begin(at: -0.08)
        XCTAssertEqual(drag.value(afterDrag: 166), 0.08, accuracy: 1e-12, "whole travel (+ the 6 pt detent)")
        XCTAssertEqual(drag.value(afterDrag: 10), -0.07, accuracy: 1e-12)
        XCTAssertEqual(drag.value(afterDrag: 3.4), -0.077, accuracy: 1e-12, "rounded to the 0.1 % step")
        XCTAssertEqual(drag.value(afterDrag: -50), -0.08, accuracy: 1e-12, "bounded")
        drag.begin(at: 0)
        XCTAssertEqual(drag.value(afterDrag: 2), 0, "inside the detent")
        XCTAssertEqual(drag.value(afterDrag: -2.9), 0, "inside the detent")
        XCTAssertEqual(drag.value(afterDrag: 4), 0.001, accuracy: 1e-12, "past the detent")
        XCTAssertEqual(drag.value(afterDrag: -4), -0.001, accuracy: 1e-12)
        drag.begin(at: 0.03)
        XCTAssertEqual(drag.value(afterDrag: 0), 0.03, accuracy: 1e-12, "a grab without movement does not jump")
    }

    // AC1 — 6.6 « Remettre le pitch à zéro » : double-toucher et bouton « 0 » appellent la remise à zéro.
    func testPitchDoubleTapAndZeroButtonReset_6_6() async {
        let deck = DeckViewModel(deck: .a, engine: engine)
        deck.setPitch(0.053)
        XCTAssertFalse(deck.isPitchZero)
        deck.resetPitch()
        XCTAssertTrue(deck.isPitchZero, "the « 0 » indicator lights")
        XCTAssertEqual(engine.sentCommands.last, .pitch(.a, 0))
    }

    // AC1 — UX §5.4, §8.1 : valeur toujours signée, signe moins U+2212, virgule décimale.
    func testPitchTextIsSigned() async {
        let deck = DeckViewModel(deck: .b, engine: engine)
        XCTAssertEqual(deck.pitchText, "0,0\u{00A0}%")
        deck.setPitch(0.053)
        XCTAssertEqual(deck.pitchText, "+5,3\u{00A0}%")
        deck.setPitch(-0.02)
        XCTAssertEqual(deck.pitchText, "\u{2212}2,0\u{00A0}%")
        XCTAssertEqual(DeckFormatting.pitchText(0.08), "+8,0\u{00A0}%")
    }

    // AC2 — SF-13 : commandes, témoin CUE, désactivés à vide, annonce VoiceOver.
    func testCueButtonsSendCommandsAndAreDisabledWhenEmpty_SF13() async {
        let empty = DeckViewModel(deck: .a, engine: engine)
        empty.setCue()
        empty.recallCue()
        XCTAssertEqual(engine.sentCommands, [], "disabled on an empty deck")
        XCTAssertEqual(empty.setCueCount, 0)

        let deck = loadedDeck()
        XCTAssertFalse(deck.hasCue)
        XCTAssertEqual(deck.cueAccessibilityValue, "aucun CUE, retour au début")
        deck.setCue()
        XCTAssertEqual(engine.sentCommands, [.setCue(.a)])
        XCTAssertEqual(deck.setCueCount, 1, "150 ms flash and announcement")
        XCTAssertEqual(deck.setCueAnnouncement, "Point CUE mémorisé à 12,3 secondes")
        deck.recallCue()
        XCTAssertEqual(engine.sentCommands.last, .recallCue(.a))
        let withCue = loadedDeck(cue: 12.34)
        XCTAssertTrue(withCue.hasCue, "CUE indicator lit")
        XCTAssertEqual(withCue.cueAccessibilityValue, "CUE à 12,3 secondes")
    }

    // AC3 — 6.6 « Définir / Rappeler un CUE pendant que je retiens le disque ».
    func testCueWorksWhileHeld_6_6() async {
        let deck = loadedDeck(position: 3, held: true)
        XCTAssertTrue(deck.isHeld)
        deck.setCue()
        deck.recallCue()
        XCTAssertEqual(engine.sentCommands, [.setCue(.a), .recallCue(.a)])
    }

    // AC4 — SF-21 : 50 % par défaut, bornes, pas de 1 % au doigt.
    func testResistanceDefaultAndStep_SF21() async {
        let deck = DeckViewModel(deck: .a, engine: engine)
        XCTAssertEqual(deck.resistance, 0.5)
        XCTAssertEqual(deck.resistanceText, "50\u{00A0}%")
        deck.setResistance((0.734 * 100).rounded() / 100)
        XCTAssertEqual(deck.resistance, 0.73, accuracy: 1e-12, "1 % step with the finger")
        deck.setResistance(1.4)
        XCTAssertEqual(deck.resistanceText, "100\u{00A0}%")
        XCTAssertEqual(engine.sentCommands.last, .resistance(.a, 1))
    }

    // AC6 — 6.16 « Régler le pitch par les actions d'accessibilité » : ±0,1 % ; résistance ±5 %.
    func testAccessibilityAdjustments_6_16() async {
        let deck = DeckViewModel(deck: .a, engine: engine)
        deck.nudgePitch(steps: 1)
        XCTAssertEqual(deck.pitchText, "+0,1\u{00A0}%")
        deck.nudgePitch(steps: -2)
        XCTAssertEqual(deck.pitchText, "\u{2212}0,1\u{00A0}%")
        deck.setResistance(deck.resistance + 0.05)
        XCTAssertEqual(deck.resistanceText, "55\u{00A0}%")
    }
}
