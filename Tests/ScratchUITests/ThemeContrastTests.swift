import XCTest
@testable import ScratchUI

/// Contraste des jetons de couleur (story 5.3 CA 4 ; WCAG 2.x AA ; UX §9.2).
final class ThemeContrastTests: XCTestCase {
    private func assertContrast(_ foreground: UInt32, on background: UInt32, atLeast minimum: Double,
                                _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let ratio = Palette.contrastRatio(foreground, background)
        XCTAssertGreaterThanOrEqual(ratio, minimum, "\(name): \(ratio)", file: file, line: line)
    }

    func testThemeContrastRatios_WCAG_AA() {
        XCTAssertEqual(Palette.contrastRatio(0xFFFFFF, 0x000000), 21, accuracy: 1e-9)
        XCTAssertEqual(Palette.contrastRatio(Palette.textPrimary, Palette.bgSurface), 15.8, accuracy: 0.1)
        // Labels: 4.5:1 on the surfaces they sit on.
        for background in [Palette.bgSurface, Palette.bgRaised] {
            for (name, color) in [("text.primary", Palette.textPrimary), ("text.secondary", Palette.textSecondary),
                                  ("deck.a", Palette.deckA), ("deck.b", Palette.deckB), ("cue", Palette.cue),
                                  ("state.on", Palette.stateOn), ("danger", Palette.danger),
                                  ("warning", Palette.warning)] {
                assertContrast(color, on: background, atLeast: 4.5, name)
            }
        }
        for (name, accent) in [("deck.a", Palette.deckA), ("deck.b", Palette.deckB), ("cue", Palette.cue)] {
            assertContrast(Palette.textOnAccent, on: accent, atLeast: 4.5, "text.onAccent on \(name)")
        }
        assertContrast(Palette.textPrimary, on: Palette.dangerDeep, atLeast: 4.5, "badge text")
        assertContrast(Palette.playhead, on: Palette.bgInset, atLeast: 4.5, "playhead")
        // Control outlines and fader tracks: 3:1 (WCAG 1.4.11).
        assertContrast(Palette.strokeStrong, on: Palette.bgSurface, atLeast: 3, "stroke.strong")
        assertContrast(Palette.strokeStrong, on: Palette.bgRaised, atLeast: 3, "stroke.strong on raised")
        assertContrast(Palette.knob, on: Palette.bgRaised, atLeast: 3, "knob")
        // Increased contrast variants are stronger than the defaults.
        XCTAssertGreaterThan(Palette.contrastRatio(Palette.textSecondaryIncreased, Palette.bgSurface),
                             Palette.contrastRatio(Palette.textSecondary, Palette.bgSurface))
        XCTAssertGreaterThan(Palette.contrastRatio(Palette.strokeStrongIncreased, Palette.bgRaised),
                             Palette.contrastRatio(Palette.strokeStrong, Palette.bgRaised))
        XCTAssertGreaterThan(Palette.contrastRatio(Palette.strokeSubtleIncreased, Palette.bgInset),
                             Palette.contrastRatio(Palette.strokeSubtle, Palette.bgInset))
    }
}
