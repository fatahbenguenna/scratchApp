#if os(macOS)
import ScratchCore
import SwiftUI

/// Menus de ScratchApp sur Mac (SF-79, D-34 ; UX §2.4) : Fichier, Platine, Table et Aide. Attachés à la
/// scène par la story 6.2 (`.commands { ScratchCommands(…) }`), avec le même `KeyboardController` que
/// `RootView`.
///
/// Les éléments à touche simple affichent le caractère de la disposition active (D-08) et sont
/// désactivés hors contexte clavier (saisie de texte, dialogue) ; quand ils sont actifs, la frappe est
/// consommée par le contrôleur clavier : ils n'agissent qu'au clic, sans double déclenchement. `F` et
/// `J`, qui se maintiennent, ne figurent que dans l'aide.
public struct ScratchCommands: Commands {
    let model: AppModel
    let intents: any DeckIntents
    let keyboard: KeyboardController
    @Environment(\.openWindow) private var openWindow

    public init(model: AppModel, intents: any DeckIntents, keyboard: KeyboardController) {
        self.model = model
        self.intents = intents
        self.keyboard = keyboard
    }

    public var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Importer sur la platine A\u{2026}") { intents.importFile(on: .a) }
                .keyboardShortcut("o", modifiers: .command)
            Button("Importer sur la platine B\u{2026}") { intents.importFile(on: .b) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Bibliothèque") { intents.openLibrary() }
                .keyboardShortcut("l", modifiers: .command)
            Divider()
            Button("Afficher la bibliothèque dans le Finder") { intents.revealLibraryInFinder() }
        }
        CommandMenu("Platine") {
            deckSection(.a)
            Divider()
            deckSection(.b)
        }
        CommandMenu("Table") {
            shortcutButton("Crossfader vers la gauche", .crossfaderStepLeft)
            shortcutButton("Crossfader vers la droite", .crossfaderStepRight)
            shortcutButton("Butée gauche", .crossfaderLeftStop)
            shortcutButton("Centre", .crossfaderCenter)
            shortcutButton("Butée droite", .crossfaderRightStop)
            Divider()
            Toggle("Hamster", isOn: Binding(get: { model.mixer.hamster }, set: { model.mixer.setHamster($0) }))
        }
        CommandGroup(replacing: .help) {
            Button("Raccourcis clavier de ScratchApp") { openWindow(id: KeyboardHelpWindow.windowID) }
        }
    }

    @ViewBuilder
    private func deckSection(_ id: DeckID) -> some View {
        let deck = model.deck(id)
        Section("Platine \(id.rawValue)") {
            shortcutButton("START / STOP", .toggleMotor(id))
            Toggle("33⅓ tours", isOn: Binding(get: { deck.speed == .rpm33 }, set: { if $0 { deck.setSpeed(.rpm33) } }))
            Toggle("45 tours", isOn: Binding(get: { deck.speed == .rpm45 }, set: { if $0 { deck.setSpeed(.rpm45) } }))
            // Like the buttons, inactive on an empty deck (#94).
            shortcutButton("SET CUE", .setCue(id)).disabled(!deck.isLoaded)
            shortcutButton("CUE", .recallCue(id)).disabled(!deck.isLoaded)
            shortcutButton("Pitch \u{2212}0,1\u{00A0}%", .pitchDown(id))
            shortcutButton("Pitch +0,1\u{00A0}%", .pitchUp(id))
            Button("Pitch à 0\u{00A0}%") { deck.resetPitch() }
        }
    }

    /// Élément à touche simple : touche de la carte, caractère de la disposition active.
    private func shortcutButton(_ title: String, _ action: KeyboardAction) -> some View {
        Button(title) { keyboard.perform(action) }
            .keyboardShortcut(Self.keyEquivalent(for: action, names: keyboard.names))
            .disabled(!keyboard.context.isActive)
    }

    /// Raccourci affiché par le menu pour une action de la carte (D-08).
    @MainActor
    static func keyEquivalent(for action: KeyboardAction, names: KeyboardLayoutNames) -> KeyboardShortcut? {
        guard let entry = KeyboardShortcutMap.entry(for: action) else { return nil }
        let modifiers: EventModifiers = entry.shift ? .shift : []
        switch entry.keyCode {
        case 123: return KeyboardShortcut(.leftArrow, modifiers: modifiers)
        case 124: return KeyboardShortcut(.rightArrow, modifiers: modifiers)
        case 125: return KeyboardShortcut(.downArrow, modifiers: modifiers)
        default:
            guard let character = names.label(for: entry.keyCode).lowercased().first else { return nil }
            return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers)
        }
    }
}
#endif
