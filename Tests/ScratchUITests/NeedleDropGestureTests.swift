import ScratchCore
import XCTest
@testable import ScratchUI

/// Needle drop sur l'aperçu complet (story 4.6 CA 4, 6 ; SF-71, SF-83, D-33 ; UX §5.8).
@MainActor
final class NeedleDropGestureTests: XCTestCase {
    private let engine = RecordingEngine()
    /// Son de 2 minutes sur 488 pt : 122 s affichées, 4 pt par seconde, 30 s à x = 128.
    private let geometry = OverviewGeometry(width: 488, duration: 120)
    private let zone = 44.0

    private func loadedDeck(duration: Double = 120, position: Double = 50, cue: Double? = nil,
                            held: Bool = false) -> DeckViewModel {
        let deck = DeckViewModel(deck: .a, engine: engine, waveformCache: WaveformCache { _, _ in nil })
        let clip = PreviewDeckIntents.syntheticClip(title: "a.wav", duration: duration)
        deck.apply(DeckSnapshot(clipID: clip.id, durationSeconds: duration, positionSeconds: position,
                                isHeld: held, motorOn: true, cueSeconds: cue))
        return deck
    }

    /// Geste complet, comme la vue : `seek` au relâchement s'il n'est ni annulé ni ignoré.
    private func drag(_ deck: DeckViewModel, from start: (Double, Double), to end: (Double, Double),
                      heldAtStart: Bool = false, heldAtEnd: Bool = false) {
        var gesture = NeedleDropGesture()
        gesture.begin(x: start.0, y: start.1, zoneHeight: zone, isHeld: heldAtStart)
        gesture.move(x: end.0, y: end.1, zoneHeight: zone)
        if let x = gesture.end(x: end.0, y: end.1, zoneHeight: zone, isHeld: heldAtEnd) {
            deck.needleDrop(toSeconds: geometry.seconds(atX: x))
        }
        XCTAssertFalse(gesture.isActive)
    }

    // AC4 — 6.11 « Positionner la tête sur l'aperçu » : au relâchement, en secondes, amorce comprise,
    // sans toucher au moteur.
    func testNeedleDropOnReleaseAtSeconds_SF71_D33() async {
        let deck = loadedDeck()
        var gesture = NeedleDropGesture()
        gesture.begin(x: 100, y: 30, zoneHeight: zone, isHeld: false)
        XCTAssertEqual(gesture.phase, .tracking)
        XCTAssertEqual(gesture.ghostX, 100, "ghost playhead under the finger")
        gesture.move(x: 128, y: 20, zoneHeight: zone)
        XCTAssertEqual(gesture.ghostX, 128, "the ghost follows")
        XCTAssertTrue(engine.sentCommands.isEmpty, "nothing moves before the release")
        drag(deck, from: (100, 30), to: (128, 20))
        XCTAssertEqual(engine.sentCommands, [.seek(.a, seconds: 30)])
        drag(deck, from: (2, 30), to: (2, 30))
        XCTAssertEqual(engine.sentCommands.last, .seek(.a, seconds: -1.5), "inside the lead-in")
        XCTAssertFalse(engine.sentCommands.contains { if case .motor = $0 { return true } else { return false } })
        XCTAssertEqual(DeckFormatting.clockText(tenths: DeckFormatting.tenths(geometry.seconds(atX: 128))),
                       "00:30,0", "time bubble")
    }

    // AC4 — 6.11 « Annuler un needle drop » : sortir de plus de 44 pt verticalement avant de relâcher.
    func testNeedleDropCancelledWhenLeavingOverview_D33() async {
        let deck = loadedDeck()
        var gesture = NeedleDropGesture()
        gesture.begin(x: 128, y: 30, zoneHeight: zone, isHeld: false)
        gesture.move(x: 128, y: zone + 44, zoneHeight: zone)
        XCTAssertEqual(gesture.phase, .tracking, "44 pt is still close enough")
        gesture.move(x: 128, y: zone + 45, zoneHeight: zone)
        XCTAssertEqual(gesture.phase, .outside)
        XCTAssertNil(gesture.ghostX, "the ghost disappears outside")
        gesture.move(x: 140, y: 10, zoneHeight: zone)
        XCTAssertEqual(gesture.ghostX, 140, "coming back resumes")
        drag(deck, from: (128, 30), to: (128, zone + 45))
        drag(deck, from: (128, 30), to: (128, -45))
        XCTAssertTrue(engine.sentCommands.isEmpty, "the position is unchanged")
        drag(deck, from: (128, 30), to: (600, 30))
        XCTAssertEqual(engine.sentCommands, [.seek(.a, seconds: 120)], "horizontal overshoot is bounded, not cancelled")
    }

    // AC4 — 6.11 « Needle drop ignoré pendant que je retiens le disque » : à l'appui et au relâchement.
    func testNeedleDropIgnoredWhileHeld_SF71() async {
        let deck = loadedDeck()
        var gesture = NeedleDropGesture()
        gesture.begin(x: 128, y: 30, zoneHeight: zone, isHeld: true)
        XCTAssertEqual(gesture.phase, .ignored)
        XCTAssertNil(gesture.ghostX, "no ghost playhead")
        gesture.move(x: 200, y: 30, zoneHeight: zone)
        XCTAssertNil(gesture.ghostX)
        drag(deck, from: (128, 30), to: (128, 30), heldAtStart: true)
        drag(deck, from: (128, 30), to: (128, 30), heldAtEnd: true)
        XCTAssertTrue(engine.sentCommands.isEmpty)
        // The model refuses it too while the snapshot shows the disc held.
        let held = loadedDeck(held: true)
        held.needleDrop(toSeconds: 30)
        held.nudgeNeedle(steps: 1)
        XCTAssertTrue(engine.sentCommands.isEmpty)
    }

    // AC6 — SF-83 : « Aperçu du son, platine A », valeur parlée, ajustable par ±5 % de la durée.
    func testOverviewAccessibilityValue_SF83() async {
        let deck = loadedDeck(duration: 225, position: 12.34, cue: 4)
        XCTAssertEqual(deck.overviewAccessibilityValue,
                       "position 12,3 secondes sur 3 minutes 45 secondes, CUE à 4 secondes")
        XCTAssertEqual(loadedDeck(duration: 225, position: 12.34).overviewAccessibilityValue,
                       "position 12,3 secondes sur 3 minutes 45 secondes, aucun CUE")
        XCTAssertEqual(DeckViewModel(deck: .b, engine: engine).overviewAccessibilityValue, "aucun son")
        deck.nudgeNeedle(steps: 1)
        deck.nudgeNeedle(steps: -1)
        guard case let .seek(_, forward)? = engine.sentCommands.first,
              case let .seek(_, backward)? = engine.sentCommands.last else { return XCTFail("no seek") }
        XCTAssertEqual(forward, 12.34 + 11.25, accuracy: 1e-9)
        XCTAssertEqual(backward, 12.34 - 11.25, accuracy: 1e-9)
    }
}
