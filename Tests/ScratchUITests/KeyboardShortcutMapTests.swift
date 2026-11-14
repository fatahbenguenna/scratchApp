import Foundation
import ScratchAudio
import ScratchCore
import ScratchLibrary
import XCTest
@testable import ScratchUI

/// Carte des raccourcis Mac, appui et relâchement, répétition, modificateurs (story 5.1).
@MainActor
final class KeyboardShortcutMapTests: XCTestCase {
    private struct EmptyLibrary: LibraryStoring {
        var entries: [LibraryEntry] { get async { [] } }
        func reconcile() async -> [LibraryEntry] { [] }
        func importFile(at url: URL) async throws -> ImportResult { throw LibraryError.unsupportedFormat }
        func delete(id: UUID) async throws { throw LibraryError.notFound }
        func url(for id: UUID) async throws -> URL { throw LibraryError.notFound }
    }

    private let engine = RecordingEngine()

    private func makeModel() -> AppModel {
        AppModel(engine: engine, host: nil, library: EmptyLibrary(), preferences: InMemoryPreferencesStore(),
                 decoder: AudioFileDecoder())
    }

    private func press(_ keyCode: UInt16, _ modifiers: KeyModifiers = [], repeat isRepeat: Bool = false,
                       with dispatcher: inout KeyboardDispatcher, on model: AppModel) {
        let result = dispatcher.keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat, isActive: true)
        result.effects.forEach { KeyboardRouter.apply($0, to: model) }
    }

    // AC1 — spec 3.5 : toute la table, par code de touche.
    func testKeyCodesMapToActions_3_5() async {
        let table: [(UInt16, KeyModifiers, KeyboardAction)] = [
            (12, [], .toggleMotor(.a)), (35, [], .toggleMotor(.b)), (0, [], .setCue(.a)), (1, [], .recallCue(.a)),
            (37, [], .setCue(.b)), (40, [], .recallCue(.b)), (3, [], .momentaryCut(.a)), (38, [], .momentaryCut(.b)),
            (6, [], .pitchDown(.a)), (7, [], .pitchUp(.a)), (43, [], .pitchDown(.b)), (47, [], .pitchUp(.b)),
            (123, [], .crossfaderStepLeft), (124, [], .crossfaderStepRight), (123, .shift, .crossfaderLeftStop),
            (125, .shift, .crossfaderCenter), (124, .shift, .crossfaderRightStop),
        ]
        for (keyCode, modifiers, action) in table {
            XCTAssertEqual(KeyboardShortcutMap.action(keyCode: keyCode, modifiers: modifiers), action, "\(keyCode)")
        }
        XCTAssertEqual(KeyboardShortcutMap.entries.count, table.count, "a single map for keys, menus and help")
        XCTAssertNil(KeyboardShortcutMap.action(keyCode: 125, modifiers: []), "↓ alone does nothing")
    }

    // AC1, AC6 — D-08 : position physique ; l'aide et les menus montrent le caractère réel.
    func testAzertyUsesPhysicalPositions_D08() async {
        XCTAssertEqual(KeyboardShortcutMap.action(keyCode: 12, modifiers: []), .toggleMotor(.a),
                       "the key printed « A » on AZERTY sits at QWERTY Q: START/STOP A")
        let azertyKeys: [UInt16: String] = [12: "a", 0: "q", 6: "w", 43: ";", 47: ":"]
        let azerty = KeyboardLayoutNames(translate: { azertyKeys[$0] })
        XCTAssertEqual(azerty.label(for: 12), "A")
        XCTAssertEqual(azerty.label(for: 0), "Q")
        XCTAssertEqual(azerty.label(for: 43), ";")
        XCTAssertEqual(azerty.label(for: 123), "←")
        let leftStop = KeyboardShortcutMap.entry(for: .crossfaderLeftStop)
        XCTAssertEqual(leftStop.map { azerty.label(for: $0) }, "⇧←")
        let unknown = KeyboardLayoutNames(translate: { _ in nil })
        XCTAssertEqual(unknown.label(for: 12), "Q", "reference QWERTY name when the layout gives nothing")
    }

    // AC1 — D-09, 6.10 « Butées au clavier avec le hamster (Mac) » : butées physiques.
    func testShiftArrowsAreLeftCentreRight_WithHamster_D09() async {
        let model = makeModel()
        model.mixer.setHamster(true)
        engine.clearSentCommands()
        var dispatcher = KeyboardDispatcher()
        press(123, .shift, with: &dispatcher, on: model)
        XCTAssertEqual(engine.sentCommands, [.crossfader(0)], "left stop = position 0, always on the left")
        // The engine inverts the position with the hamster (1.4): only channel B is heard at the left stop.
        let left = CrossfaderCurve.gains(position: 1 - 0, curve: 1)
        XCTAssertEqual(left.a, 0, accuracy: 1e-12)
        XCTAssertEqual(left.b, 1, accuracy: 1e-12)
        press(124, .shift, with: &dispatcher, on: model)
        let right = CrossfaderCurve.gains(position: 1 - 1, curve: 1)
        XCTAssertEqual(engine.sentCommands.last, .crossfader(1))
        XCTAssertEqual(right.a, 1, accuracy: 1e-12)
        XCTAssertEqual(right.b, 0, accuracy: 1e-12)
        press(125, .shift, with: &dispatcher, on: model)
        XCTAssertEqual(engine.sentCommands.last, .crossfader(0.5))
    }

    // AC1 — 6.14 « Déplacer le crossfader au clavier ».
    func testThreeRightArrowsFromLeftStopGive15Percent_6_14() async {
        let model = makeModel()
        var dispatcher = KeyboardDispatcher()
        press(123, .shift, with: &dispatcher, on: model)
        for _ in 0..<3 { press(124, with: &dispatcher, on: model) }
        XCTAssertEqual(model.mixer.crossfader, 0.15, accuracy: 1e-12)
    }

    // AC2 — D-06, 6.14 « Couper le son au clavier pendant un scratch à la souris ».
    func testMomentaryCutOpensOnDownClosesOnUpAndOnFocusLoss_6_14() async {
        var dispatcher = KeyboardDispatcher()
        let open = dispatcher.keyDown(keyCode: 3, modifiers: [], isRepeat: false, isActive: true)
        XCTAssertEqual(open.effects, [.momentaryCut(.a, open: true)])
        XCTAssertTrue(open.consumed)
        XCTAssertEqual(dispatcher.keyDown(keyCode: 3, modifiers: [], isRepeat: true, isActive: true).effects, [],
                       "auto-repeat does not reopen")
        XCTAssertEqual(dispatcher.keyDown(keyCode: 38, modifiers: [], isRepeat: false, isActive: true).effects,
                       [.momentaryCut(.b, open: true)], "F and J held together")
        XCTAssertEqual(dispatcher.keyUp(keyCode: 3).effects, [.momentaryCut(.a, open: false)])
        XCTAssertEqual(dispatcher.releaseAll(), [.momentaryCut(.b, open: false)], "focus loss closes the channel")
        XCTAssertFalse(dispatcher.keyUp(keyCode: 38).consumed)

        let model = makeModel()
        KeyboardRouter.apply(.momentaryCut(.a, open: true), to: model)
        model.deckA.touchBegan(angle: 0, time: 1)
        KeyboardRouter.apply(.momentaryCut(.a, open: false), to: model)
        XCTAssertEqual(engine.sentCommands, [.momentaryCut(.a, open: true), .touchBegan(.a, angle: 0, time: 1),
                                             .momentaryCut(.a, open: false)], "the disc stays held")
    }

    // AC3 — D-25 : répétition acceptée pour le pitch et ←/→, ignorée ailleurs.
    func testAutoRepeatRules_D25() async {
        for entry in KeyboardShortcutMap.entries {
            var dispatcher = KeyboardDispatcher()
            if case .momentaryCut = entry.action {
                _ = dispatcher.keyDown(keyCode: entry.keyCode, modifiers: [], isRepeat: false, isActive: true)
            }
            let modifiers: KeyModifiers = entry.shift ? .shift : []
            let result = dispatcher.keyDown(keyCode: entry.keyCode, modifiers: modifiers, isRepeat: true, isActive: true)
            XCTAssertTrue(result.consumed, entry.title)
            XCTAssertEqual(!result.effects.isEmpty, entry.action.allowsRepeat, entry.title)
        }
        XCTAssertTrue(KeyboardAction.pitchUp(.b).allowsRepeat)
        XCTAssertFalse(KeyboardAction.crossfaderLeftStop.allowsRepeat)
        XCTAssertFalse(KeyboardAction.toggleMotor(.a).allowsRepeat)
    }

    // AC4 — 6.14 « Raccourcis inactifs pendant la saisie de texte » ; modificateurs.
    func testModifiersAndTextFocusDisableShortcuts_6_14() async {
        XCTAssertNil(KeyboardShortcutMap.action(keyCode: 12, modifiers: .command), "⌘Q quits, it is not START")
        XCTAssertNil(KeyboardShortcutMap.action(keyCode: 6, modifiers: .option))
        XCTAssertNil(KeyboardShortcutMap.action(keyCode: 124, modifiers: .control))
        XCTAssertNil(KeyboardShortcutMap.action(keyCode: 12, modifiers: .shift), "⇧ only with the arrows")
        var dispatcher = KeyboardDispatcher()
        let typing = dispatcher.keyDown(keyCode: 12, modifiers: [], isRepeat: false, isActive: false)
        XCTAssertEqual(typing.effects, [])
        XCTAssertFalse(typing.consumed, "the key goes to the text field")
        _ = dispatcher.keyDown(keyCode: 3, modifiers: [], isRepeat: false, isActive: true)
        XCTAssertEqual(dispatcher.keyUp(keyCode: 3).effects, [.momentaryCut(.a, open: false)],
                       "an open channel always closes on key up")
    }
}
