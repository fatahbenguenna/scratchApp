import ScratchCore

/// Action du clavier Mac (spec 3.5 ; UX §6.3).
public enum KeyboardAction: Hashable, Sendable {
    case toggleMotor(DeckID)
    case setCue(DeckID)
    case recallCue(DeckID)
    /// Coupure momentanée : voie ouverte tant que la touche est enfoncée (D-06).
    case momentaryCut(DeckID)
    case pitchDown(DeckID)
    case pitchUp(DeckID)
    /// Crossfader d'un pas de 5 % vers la gauche ou la droite physiques.
    case crossfaderStepLeft
    case crossfaderStepRight
    /// Butées gauche et droite **physiques** et centre, quel que soit le hamster (D-09).
    case crossfaderLeftStop
    case crossfaderCenter
    case crossfaderRightStop

    /// La répétition automatique est acceptée pour le pitch et `←` / `→`, ignorée ailleurs (D-25).
    public var allowsRepeat: Bool {
        switch self {
        case .pitchDown, .pitchUp, .crossfaderStepLeft, .crossfaderStepRight: return true
        default: return false
        }
    }
}

/// Modificateurs qui comptent pour un raccourci ; le verrouillage majuscule n'en fait pas partie.
public struct KeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let command = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let control = KeyModifiers(rawValue: 1 << 3)
}

/// Carte unique des raccourcis (spec 3.5 ; D-08, D-09, D-25) : elle alimente le contrôleur clavier,
/// les menus et l'aide. Les touches sont lues par **position physique** (code de touche de la
/// disposition QWERTY de référence, `kVK_ANSI_*`) : sur AZERTY, START/STOP A est la touche « A ».
/// Logique pure.
public enum KeyboardShortcutMap {
    /// Groupe de l'aide (UX §5.22).
    public enum Group: String, CaseIterable, Sendable {
        case deckA = "Platine A"
        case deckB = "Platine B"
        case global = "Global"
    }

    public struct Entry: Hashable, Sendable {
        public let keyCode: UInt16
        /// ⇧ requis (seulement avec les flèches).
        public let shift: Bool
        public let action: KeyboardAction
        public let group: Group
        /// Libellé de l'aide.
        public let title: String
    }

    /// Codes de touche (`kVK_*`).
    enum KeyCode {
        static let a: UInt16 = 0, s: UInt16 = 1, f: UInt16 = 3, z: UInt16 = 6, x: UInt16 = 7
        static let q: UInt16 = 12, p: UInt16 = 35, l: UInt16 = 37, j: UInt16 = 38, k: UInt16 = 40
        static let comma: UInt16 = 43, period: UInt16 = 47, escape: UInt16 = 53
        static let leftArrow: UInt16 = 123, rightArrow: UInt16 = 124, downArrow: UInt16 = 125
    }

    public static let entries: [Entry] = [
        Entry(keyCode: KeyCode.q, shift: false, action: .toggleMotor(.a), group: .deckA, title: "START / STOP"),
        Entry(keyCode: KeyCode.a, shift: false, action: .setCue(.a), group: .deckA, title: "SET CUE"),
        Entry(keyCode: KeyCode.s, shift: false, action: .recallCue(.a), group: .deckA, title: "CUE"),
        Entry(keyCode: KeyCode.f, shift: false, action: .momentaryCut(.a), group: .deckA,
              title: "Coupure momentanée (maintenir)"),
        Entry(keyCode: KeyCode.z, shift: false, action: .pitchDown(.a), group: .deckA, title: "Pitch \u{2212}0,1\u{00A0}%"),
        Entry(keyCode: KeyCode.x, shift: false, action: .pitchUp(.a), group: .deckA, title: "Pitch +0,1\u{00A0}%"),
        Entry(keyCode: KeyCode.p, shift: false, action: .toggleMotor(.b), group: .deckB, title: "START / STOP"),
        Entry(keyCode: KeyCode.l, shift: false, action: .setCue(.b), group: .deckB, title: "SET CUE"),
        Entry(keyCode: KeyCode.k, shift: false, action: .recallCue(.b), group: .deckB, title: "CUE"),
        Entry(keyCode: KeyCode.j, shift: false, action: .momentaryCut(.b), group: .deckB,
              title: "Coupure momentanée (maintenir)"),
        Entry(keyCode: KeyCode.comma, shift: false, action: .pitchDown(.b), group: .deckB,
              title: "Pitch \u{2212}0,1\u{00A0}%"),
        Entry(keyCode: KeyCode.period, shift: false, action: .pitchUp(.b), group: .deckB, title: "Pitch +0,1\u{00A0}%"),
        Entry(keyCode: KeyCode.leftArrow, shift: false, action: .crossfaderStepLeft, group: .global,
              title: "Crossfader : 5\u{00A0}% vers la gauche"),
        Entry(keyCode: KeyCode.rightArrow, shift: false, action: .crossfaderStepRight, group: .global,
              title: "Crossfader : 5\u{00A0}% vers la droite"),
        Entry(keyCode: KeyCode.leftArrow, shift: true, action: .crossfaderLeftStop, group: .global,
              title: "Crossfader en butée gauche"),
        Entry(keyCode: KeyCode.downArrow, shift: true, action: .crossfaderCenter, group: .global,
              title: "Crossfader au centre"),
        Entry(keyCode: KeyCode.rightArrow, shift: true, action: .crossfaderRightStop, group: .global,
              title: "Crossfader en butée droite"),
    ]

    /// Action d'une frappe. Les raccourcis n'agissent que sans ⌘, ⌥ ni ⌃ ; ⇧ seulement avec les
    /// flèches (une lettre avec ⇧ n'est pas un raccourci).
    public static func action(keyCode: UInt16, modifiers: KeyModifiers) -> KeyboardAction? {
        guard modifiers.isDisjoint(with: [.command, .option, .control]) else { return nil }
        let shift = modifiers.contains(.shift)
        return entries.first { $0.keyCode == keyCode && $0.shift == shift }?.action
    }

    /// Raccourci d'une action (menus, aide).
    public static func entry(for action: KeyboardAction) -> Entry? {
        entries.first { $0.action == action }
    }

    /// Voie de la touche de coupure momentanée (`F` → A, `J` → B), quel que soit le hamster (D-06).
    static func momentaryCutDeck(keyCode: UInt16) -> DeckID? {
        switch keyCode {
        case KeyCode.f: return .a
        case KeyCode.j: return .b
        default: return nil
        }
    }
}
