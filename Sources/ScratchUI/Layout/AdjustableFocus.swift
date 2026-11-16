import SwiftUI

/// Flèche du clavier.
public enum ArrowKey: Sendable {
    case left, right, up, down
}

/// Commande réglable qui a le focus clavier (Mac, accès clavier complet ; story 5.3 CA 3 ; D-07,
/// UX §6.4).
///
/// - La commande focalisée (pitch, résistance, fader de voie, courbe, crossfader, aperçu) reçoit
///   **toutes** les flèches : ↑ et → montent d'un pas, ↓ et ← descendent ; ⇧ multiplie le pas par
///   dix (le crossfader garde ses butées et son centre).
/// - Sans commande réglable focalisée, les flèches vont au crossfader (5.1). Un seul gestionnaire
///   décide : le moniteur clavier de la 5.1 interroge ce routeur avant les raccourcis.
/// - Échap ou la tabulation vers une commande non réglable retire la commande du routeur.
@MainActor
public final class AdjustableFocus {
    public static let shared = AdjustableFocus()

    struct Target {
        let id: String
        /// Pas signés : +1 (↑, →) ou −1 (↓, ←), ×10 avec ⇧.
        let adjust: @MainActor (_ steps: Int) -> Void
        /// Effet propre de ⇧ + flèche (crossfader : butées physiques et centre, D-09), sinon `nil`.
        let shiftArrow: (@MainActor (ArrowKey) -> Void)?
    }

    private(set) var target: Target?
    /// Identifiant d'accessibilité de la commande focalisée.
    var focusedID: String? { target?.id }

    func focus(_ target: Target) { self.target = target }

    /// Perte du focus de la commande `id` (une autre commande a pu le prendre entre-temps).
    func unfocus(_ id: String) {
        if target?.id == id { target = nil }
    }

    func clear() { target = nil }

    /// Pas d'une flèche : ±1, ±10 avec ⇧.
    static func steps(for arrow: ArrowKey, shift: Bool) -> Int {
        let direction = arrow == .up || arrow == .right ? 1 : -1
        return shift ? 10 * direction : direction
    }

    /// Envoie la flèche à la commande focalisée ; `false` s'il n'y en a pas (crossfader, 5.1).
    func handle(_ arrow: ArrowKey, shift: Bool) -> Bool {
        guard let target else { return false }
        if shift, let shiftArrow = target.shiftArrow {
            shiftArrow(arrow)
        } else {
            target.adjust(Self.steps(for: arrow, shift: shift))
        }
        return true
    }
}

extension View {
    /// Commande réglable au clavier sur Mac : focalisable avec l'accès clavier complet (anneau de
    /// focus du système) ; quand elle a le focus, les flèches lui reviennent (`AdjustableFocus`).
    /// Sans effet sur iOS (actions d'accessibilité seulement).
    func keyboardAdjustable(id: String, adjust: @escaping @MainActor (Int) -> Void,
                            shiftArrow: (@MainActor (ArrowKey) -> Void)? = nil) -> some View {
        modifier(KeyboardAdjustableModifier(id: id, adjust: adjust, shiftArrow: shiftArrow))
    }
}

private struct KeyboardAdjustableModifier: ViewModifier {
    let id: String
    let adjust: @MainActor (Int) -> Void
    let shiftArrow: (@MainActor (ArrowKey) -> Void)?
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .focusable(interactions: .activate)
            .focused($isFocused)
            .onChange(of: isFocused) {
                if isFocused {
                    AdjustableFocus.shared.focus(.init(id: id, adjust: adjust, shiftArrow: shiftArrow))
                } else {
                    AdjustableFocus.shared.unfocus(id)
                }
            }
            .onDisappear { AdjustableFocus.shared.unfocus(id) }
        #else
        content
        #endif
    }
}

extension View {
    /// Bouton de performance (action à l'appui : START/STOP, SET CUE, CUE) activable au clavier sur
    /// Mac : focalisable avec l'accès clavier complet ; Espace ou Retour l'activent (UX §6.4).
    func keyboardActivatable(enabled: Bool = true, action: @escaping @MainActor () -> Void) -> some View {
        #if os(macOS)
        return focusable(enabled, interactions: .activate)
            .onKeyPress(keys: [.space, .return], phases: .down) { _ in
                MainActor.assumeIsolated { action() }
                return .handled
            }
        #else
        return self
        #endif
    }
}

extension View {
    /// Section de focus clavier (Mac) : la tabulation parcourt une platine, puis la table, puis
    /// l'autre platine (UX §6.4). `focusSection()` n'existe pas sur iOS.
    func macFocusSection() -> some View {
        #if os(macOS)
        return focusSection()
        #else
        return self
        #endif
    }
}
