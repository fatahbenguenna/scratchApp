import ScratchCore

/// Effet d'une frappe ou d'un élément de menu sur les modèles.
public enum KeyboardEffect: Equatable, Sendable {
    case perform(KeyboardAction)
    case momentaryCut(DeckID, open: Bool)
}

/// Appui et relâchement des touches (spec 3.5 ; D-06, D-07, D-25) : logique pure, sans AppKit.
///
/// - Hors contexte actif (saisie de texte, dialogue, fenêtre principale inactive), aucune frappe
///   n'agit ni n'est consommée : elle va au champ de texte ou au dialogue.
/// - La répétition automatique est consommée sans effet pour START/STOP, SET CUE, CUE, les coupures
///   et les butées ; elle agit pour le pitch et `←` / `→`.
/// - Une coupure s'ouvre à l'appui et se referme au relâchement de sa touche (avec ou sans
///   modificateur), ou par `releaseAll` (perte du focus, arrière-plan, feuille).
struct KeyboardDispatcher {
    private(set) var openCuts: Set<DeckID> = []

    /// Appui : effets à appliquer et consommation de l'événement.
    mutating func keyDown(keyCode: UInt16, modifiers: KeyModifiers, isRepeat: Bool,
                          isActive: Bool) -> (effects: [KeyboardEffect], consumed: Bool) {
        guard isActive, let action = KeyboardShortcutMap.action(keyCode: keyCode, modifiers: modifiers) else {
            return ([], false)
        }
        if case let .momentaryCut(deck) = action {
            guard !isRepeat, !openCuts.contains(deck) else { return ([], true) }
            openCuts.insert(deck)
            return ([.momentaryCut(deck, open: true)], true)
        }
        guard !isRepeat || action.allowsRepeat else { return ([], true) }
        return ([.perform(action)], true)
    }

    /// Relâchement : referme la coupure de la touche si elle est ouverte.
    mutating func keyUp(keyCode: UInt16) -> (effects: [KeyboardEffect], consumed: Bool) {
        guard let deck = KeyboardShortcutMap.momentaryCutDeck(keyCode: keyCode), openCuts.contains(deck) else {
            return ([], false)
        }
        openCuts.remove(deck)
        return ([.momentaryCut(deck, open: false)], true)
    }

    /// Referme toutes les coupures ouvertes (sécurité de l'UX §6.3).
    mutating func releaseAll() -> [KeyboardEffect] {
        let effects = openCuts.sorted { $0.rawValue < $1.rawValue }.map { KeyboardEffect.momentaryCut($0, open: false) }
        openCuts.removeAll()
        return effects
    }
}

/// Routage d'un effet vers les modèles de présentation : un seul chemin pour le clavier et les menus.
enum KeyboardRouter {
    @MainActor
    static func apply(_ effect: KeyboardEffect, to model: AppModel) {
        switch effect {
        case let .momentaryCut(deck, open):
            model.mixer.setMomentaryCut(deck, open: open)
        case let .perform(action):
            switch action {
            case let .toggleMotor(deck): model.deck(deck).toggleMotor()
            case let .setCue(deck): model.deck(deck).setCue()
            case let .recallCue(deck): model.deck(deck).recallCue()
            case let .momentaryCut(deck): model.mixer.setMomentaryCut(deck, open: true)
            case let .pitchDown(deck): model.deck(deck).nudgePitch(steps: -1)
            case let .pitchUp(deck): model.deck(deck).nudgePitch(steps: 1)
            case .crossfaderStepLeft: model.mixer.nudgeCrossfader(steps: -1)
            case .crossfaderStepRight: model.mixer.nudgeCrossfader(steps: 1)
            // Physical stops (D-09): position 0 is always on the left of the screen; with the
            // hamster, the engine inverts it, so the left stop opens channel B.
            case .crossfaderLeftStop: model.mixer.setCrossfader(0)
            case .crossfaderCenter: model.mixer.setCrossfader(0.5)
            case .crossfaderRightStop: model.mixer.setCrossfader(1)
            }
        }
    }
}
