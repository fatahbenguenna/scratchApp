import ScratchCore
import SwiftUI

/// Jetons de style de l'écran principal (UX §9.2 couleurs, §9.3 typographie, §9.5 formes).
///
/// Thème sombre imposé en V1 (D-39) ; les jetons sont nommés pour accueillir un thème clair plus tard.
enum Theme {
    // MARK: Couleurs (UX §9.2)

    static let bgApp = Color(hex: 0x0E0F12)
    static let bgSurface = Color(hex: 0x17191E)
    static let bgRaised = Color(hex: 0x22252C)
    static let bgPressed = Color(hex: 0x2C3038)
    static let strokeSubtle = Color(hex: 0x2E323A)
    static let textPrimary = Color(hex: 0xF2F3F5)
    static let textSecondary = Color(hex: 0xA8AEB9)
    static let textDisabled = Color(hex: 0x6B717C)
    static let textOnAccent = Color(hex: 0x0E0F12)
    static let cue = Color(hex: 0xFFE14D)
    static let stateOn = Color(hex: 0x3DD68C)
    static let vuOff = Color(hex: 0x2A2D33)
    static let knob = Color(hex: 0xD9DCE1)
    static let vinyl = Color(hex: 0x111214)
    static let groove = Color(hex: 0x1C1E22)
    static let platter = Color(hex: 0x2A2D33)
    static let strobe = Color(hex: 0x8A909B)
    static let slipmat = Color(hex: 0x1A1B1F)

    /// Couleur de la platine : bleu ciel (A), orange (B). Toujours accompagnée de la lettre.
    static func deckColor(_ deck: DeckID) -> Color {
        deck == .a ? Color(hex: 0x4FB3F0) : Color(hex: 0xF5A524)
    }

    /// Couleur de l'étiquette du disque.
    static func labelColor(_ deck: DeckID) -> Color {
        deck == .a ? Color(hex: 0x1D6497) : Color(hex: 0x8A5600)
    }

    // MARK: Typographie (UX §9.3, tailles iPad et Mac)

    static let deckTitle = Font.system(size: 17, weight: .semibold)
    static let timePosition = Font.system(size: 22, weight: .medium, design: .monospaced)
    static let timeDuration = Font.system(size: 15, weight: .regular, design: .monospaced)
    static let controlLabel = Font.system(size: 13, weight: .bold)
    static let deckLetter = Font.system(size: 15, weight: .bold, design: .rounded)
    static let caption = Font.system(size: 11)
    static let body = Font.system(size: 13)

    // MARK: Formes (UX §9.5)

    static let buttonRadius: CGFloat = 8
    static let panelRadius: CGFloat = 12
}

extension Color {
    /// Couleur sRGB opaque à partir d'un entier `0xRRGGBB`.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
