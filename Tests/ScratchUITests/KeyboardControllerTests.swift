#if os(macOS)
import AppKit
import Foundation
import ScratchAudio
import ScratchCore
import ScratchLibrary
import SwiftUI
import XCTest
@testable import ScratchUI

/// Contrôleur clavier et menus Mac (story 5.1) : événements AppKit, consommation, menus et aide.
@MainActor
final class KeyboardControllerTests: XCTestCase {
    private struct EmptyLibrary: LibraryStoring {
        var entries: [LibraryEntry] { get async { [] } }
        func reconcile() async -> [LibraryEntry] { [] }
        func importFile(at url: URL) async throws -> ImportResult { throw LibraryError.unsupportedFormat }
        func delete(id: UUID) async throws { throw LibraryError.notFound }
        func url(for id: UUID) async throws -> URL { throw LibraryError.notFound }
    }

    private let engine = RecordingEngine()

    private func makeController() -> KeyboardController {
        let model = AppModel(engine: engine, host: nil, library: EmptyLibrary(),
                             preferences: InMemoryPreferencesStore(), decoder: AudioFileDecoder())
        return KeyboardController(model: model, names: KeyboardLayoutNames(translate: { _ in nil }))
    }

    private func event(_ type: NSEvent.EventType, keyCode: UInt16, flags: NSEvent.ModifierFlags = [],
                       repeat isRepeat: Bool = false) -> NSEvent? {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: isRepeat,
                         keyCode: keyCode)
    }

    // AC1, AC4 — 6.14 : une frappe de raccourci est consommée ; hors contexte, elle passe.
    func testShortcutsAreConsumedOnlyInTheActiveContext_6_14() async throws {
        let controller = makeController()
        controller.activeOverride = true
        let start = try XCTUnwrap(event(.keyDown, keyCode: 12))
        XCTAssertNil(controller.handle(start), "consumed: a menu key equivalent never sees it")
        XCTAssertEqual(engine.sentCommands, [.motor(.a, on: true)])
        let quit = try XCTUnwrap(event(.keyDown, keyCode: 12, flags: .command))
        XCTAssertNotNil(controller.handle(quit), "⌘Q is left to the menu")
        controller.activeOverride = false
        XCTAssertNotNil(controller.handle(start), "typing in a text field or a dialog")
        XCTAssertEqual(engine.sentCommands.count, 1)
        XCTAssertFalse(controller.context.isActive, "single-key menu items are disabled")
    }

    // AC2 — D-06 : F ouvre la voie A tant qu'elle est maintenue ; la perte du focus la referme.
    func testMomentaryCutThroughTheControllerAndFocusLoss_6_14() async throws {
        let controller = makeController()
        controller.activeOverride = true
        XCTAssertNil(controller.handle(try XCTUnwrap(event(.keyDown, keyCode: 3))))
        XCTAssertNil(controller.handle(try XCTUnwrap(event(.keyDown, keyCode: 3, repeat: true))))
        XCTAssertNil(controller.handle(try XCTUnwrap(event(.keyUp, keyCode: 3))))
        XCTAssertNil(controller.handle(try XCTUnwrap(event(.keyDown, keyCode: 38))))
        controller.releaseAll()
        XCTAssertEqual(engine.sentCommands, [.momentaryCut(.a, open: true), .momentaryCut(.a, open: false),
                                             .momentaryCut(.b, open: true), .momentaryCut(.b, open: false)])
    }

    // AC4 — modificateurs : verrouillage majuscule et drapeaux des flèches ignorés.
    func testModifierFlagsIgnoreCapsLock() async {
        XCTAssertEqual(KeyboardController.modifiers([.capsLock, .shift, .function, .numericPad]), .shift)
        XCTAssertEqual(KeyboardController.modifiers([.command, .option, .control]), [.command, .option, .control])
        XCTAssertFalse(KeyboardController.isShortcutContextActive(app: nil, window: nil))
    }

    // AC5, AC6 — D-08, D-34 : menus et aide affichent le caractère de la disposition active.
    func testHelpAndMenusShowActiveLayoutCharacters_D08() async {
        let azertyKeys: [UInt16: String] = [12: "a", 0: "q", 3: "f", 38: "j"]
        let azerty = KeyboardLayoutNames(translate: { azertyKeys[$0] })
        let start = ScratchCommands.keyEquivalent(for: .toggleMotor(.a), names: azerty)
        XCTAssertEqual(start?.key, KeyEquivalent("a"))
        XCTAssertEqual(start?.modifiers, [])
        let leftStop = ScratchCommands.keyEquivalent(for: .crossfaderLeftStop, names: azerty)
        XCTAssertEqual(leftStop?.key, .leftArrow)
        XCTAssertEqual(leftStop?.modifiers, .shift)
        XCTAssertEqual(KeyboardHelpView.entries(in: .deckA).map(\.title).first, "START / STOP")
        XCTAssertEqual(KeyboardHelpView.entries(in: .global).count, 5)
        XCTAssertTrue(KeyboardHelpView.footer(names: azerty).hasPrefix("Maintenez F ou J pour ouvrir la voie A ou B"))
    }
}
#endif
