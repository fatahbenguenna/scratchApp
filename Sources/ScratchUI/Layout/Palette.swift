import Foundation

/// Jetons de couleur de l'UX §9.2 en `0xRRGGBB`, et rapport de contraste WCAG 2.x (story 5.3 CA 4).
///
/// Valeurs pures, sans SwiftUI : `Theme` en fait des couleurs, et le test de contraste les vérifie
/// toutes. « Augmenter le contraste » remplace trois jetons par leurs variantes (UX §9.2).
enum Palette {
    static let bgApp: UInt32 = 0x0E0F12
    static let bgSurface: UInt32 = 0x17191E
    static let bgRaised: UInt32 = 0x22252C
    static let bgPressed: UInt32 = 0x2C3038
    static let bgInset: UInt32 = 0x0A0B0D
    static let strokeSubtle: UInt32 = 0x2E323A
    static let strokeStrong: UInt32 = 0x6E7480
    static let textPrimary: UInt32 = 0xF2F3F5
    static let textSecondary: UInt32 = 0xA8AEB9
    static let textDisabled: UInt32 = 0x6B717C
    static let textOnAccent: UInt32 = 0x0E0F12
    static let deckA: UInt32 = 0x4FB3F0
    static let deckB: UInt32 = 0xF5A524
    static let deckALabel: UInt32 = 0x1D6497
    static let deckBLabel: UInt32 = 0x8A5600
    static let cue: UInt32 = 0xFFE14D
    static let stateOn: UInt32 = 0x3DD68C
    static let danger: UInt32 = 0xFF6369
    static let dangerDeep: UInt32 = 0x7A1F24
    static let warning: UInt32 = 0xFFB224
    static let playhead: UInt32 = 0xFFFFFF
    static let knob: UInt32 = 0xD9DCE1
    static let vuLow: UInt32 = 0x30D158
    static let vuMid: UInt32 = 0xFFD60A
    static let vuHigh: UInt32 = 0xFF453A
    static let vuOff: UInt32 = 0x2A2D33
    static let vinyl: UInt32 = 0x111214
    static let groove: UInt32 = 0x1C1E22
    static let platter: UInt32 = 0x2A2D33
    static let strobe: UInt32 = 0x8A909B
    static let slipmat: UInt32 = 0x1A1B1F

    // MARK: Contraste augmenté (UX §9.2)

    static let textSecondaryIncreased: UInt32 = 0xC9CED6
    static let strokeStrongIncreased: UInt32 = 0x8A909B
    static let strokeSubtleIncreased: UInt32 = 0x4A505C

    // MARK: WCAG 2.x

    /// Luminance relative d'une couleur sRGB (composantes linéarisées).
    static func relativeLuminance(_ hex: UInt32) -> Double {
        func linear(_ component: UInt32) -> Double {
            let value = Double(component & 0xFF) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(hex >> 16) + 0.7152 * linear(hex >> 8) + 0.0722 * linear(hex)
    }

    /// Rapport de contraste entre deux couleurs, de 1 à 21.
    static func contrastRatio(_ first: UInt32, _ second: UInt32) -> Double {
        let a = relativeLuminance(first), b = relativeLuminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
