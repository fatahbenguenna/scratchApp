import ScratchCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Jetons de style de l'écran principal (UX §9.2 couleurs, §9.3 typographie, §9.5 formes).
///
/// Thème sombre imposé en V1 (D-39) ; les jetons sont nommés pour accueillir un thème clair plus tard.
enum Theme {
    // MARK: Couleurs (UX §9.2)

    static let bgApp = Color(hex: Palette.bgApp)
    static let bgSurface = Color(hex: Palette.bgSurface)
    static let bgRaised = Color(hex: Palette.bgRaised)
    static let bgPressed = Color(hex: Palette.bgPressed)
    static let bgInset = Color(hex: Palette.bgInset)
    /// Variantes « Augmenter le contraste » : `stroke.subtle`, `stroke.strong`, `text.secondary`.
    static let strokeSubtle = Color(hex: Palette.strokeSubtle, increasedContrast: Palette.strokeSubtleIncreased)
    static let strokeStrong = Color(hex: Palette.strokeStrong, increasedContrast: Palette.strokeStrongIncreased)
    static let textPrimary = Color(hex: Palette.textPrimary)
    static let textSecondary = Color(hex: Palette.textSecondary, increasedContrast: Palette.textSecondaryIncreased)
    static let textDisabled = Color(hex: Palette.textDisabled)
    static let textOnAccent = Color(hex: Palette.textOnAccent)
    static let cue = Color(hex: Palette.cue)
    static let stateOn = Color(hex: Palette.stateOn)
    static let danger = Color(hex: Palette.danger)
    static let dangerDeep = Color(hex: Palette.dangerDeep)
    static let warning = Color(hex: Palette.warning)
    static let vuLow = Color(hex: Palette.vuLow)
    static let vuMid = Color(hex: Palette.vuMid)
    static let vuHigh = Color(hex: Palette.vuHigh)
    static let vuOff = Color(hex: Palette.vuOff)
    static let knob = Color(hex: Palette.knob)
    static let vinyl = Color(hex: Palette.vinyl)
    static let groove = Color(hex: Palette.groove)
    static let platter = Color(hex: Palette.platter)
    static let strobe = Color(hex: Palette.strobe)
    static let slipmat = Color(hex: Palette.slipmat)

    /// Couleur de la platine : bleu ciel (A), orange (B). Toujours accompagnée de la lettre.
    static func deckColor(_ deck: DeckID) -> Color {
        deck == .a ? Color(hex: Palette.deckA) : Color(hex: Palette.deckB)
    }

    /// Couleur de l'étiquette du disque.
    static func labelColor(_ deck: DeckID) -> Color {
        deck == .a ? Color(hex: Palette.deckALabel) : Color(hex: Palette.deckBLabel)
    }

    // MARK: Typographie (UX §9.3, tailles iPad et Mac)

    static let deckTitle = Font.system(size: 17, weight: .semibold)
    static let timePosition = Font.system(size: 22, weight: .medium, design: .monospaced)
    static let timeDuration = Font.system(size: 15, weight: .regular, design: .monospaced)
    static let controlLabel = Font.system(size: 13, weight: .bold)
    static let valueReadout = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let sectionLabel = Font.system(size: 11, weight: .bold)
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

    /// Couleur qui passe à `increasedContrast` avec « Augmenter le contraste » (UX §9.2) : couleur
    /// dynamique du système, résolue à chaque dessin sans que les vues aient à lire l'environnement.
    init(hex: UInt32, increasedContrast: UInt32) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let names: [NSAppearance.Name] = [.accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua,
                                              .darkAqua, .aqua]
            let match = appearance.bestMatch(from: names)
            let increased = match == .accessibilityHighContrastDarkAqua || match == .accessibilityHighContrastAqua
            return NSColor(Color(hex: increased ? increasedContrast : hex))
        })
        #else
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.accessibilityContrast == .high ? increasedContrast : hex))
        })
        #endif
    }
}
