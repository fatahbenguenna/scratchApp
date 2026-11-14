#if os(macOS)
import ScratchCore
import SwiftUI

/// Aide « Raccourcis clavier » (spec 3.3, 3.5 ; D-08 ; UX §5.22) : 560 × 440, groupes Platine A,
/// Platine B et Global, touches dessinées avec le caractère de la disposition active. Intégrée aux
/// réglages en 3.4.
public struct KeyboardHelpView: View {
    let names: KeyboardLayoutNames

    public init(names: KeyboardLayoutNames) {
        self.names = names
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Raccourcis clavier").font(.title2.weight(.semibold))
            HStack(alignment: .top, spacing: 24) {
                group(.deckA)
                group(.deckB)
            }
            group(.global)
            Spacer(minLength: 0)
            Text(verbatim: Self.footer(names: names))
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 560, height: 440, alignment: .topLeading)
        .foregroundStyle(Theme.textPrimary)
        .background(Theme.bgSurface)
        .preferredColorScheme(.dark)
    }

    private func group(_ group: KeyboardShortcutMap.Group) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: group.rawValue).font(.headline)
            ForEach(Self.entries(in: group), id: \.self) { entry in
                HStack(spacing: 8) {
                    Text(verbatim: names.label(for: entry))
                        .font(.system(size: 13, design: .monospaced))
                        .padding(.horizontal, 6)
                        .frame(minWidth: 28, minHeight: 22)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.bgRaised))
                    Text(verbatim: entry.title).font(.callout)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func entries(in group: KeyboardShortcutMap.Group) -> [KeyboardShortcutMap.Entry] {
        KeyboardShortcutMap.entries.filter { $0.group == group }
    }

    /// Pied de l'UX §5.22, avec les caractères réels de `F` et `J`.
    @MainActor
    static func footer(names: KeyboardLayoutNames) -> String {
        let cutA = names.label(for: KeyboardShortcutMap.KeyCode.f)
        let cutB = names.label(for: KeyboardShortcutMap.KeyCode.j)
        return "Maintenez \(cutA) ou \(cutB) pour ouvrir la voie A ou B (coupure momentanée). "
            + "Les raccourcis sont inactifs pendant la saisie de texte et quand une fenêtre de dialogue est ouverte."
    }
}

/// Fenêtre de l'aide, attachée à l'app par la story 6.2 ; ouverte par Aide › Raccourcis clavier de
/// ScratchApp.
public struct KeyboardHelpWindow: Scene {
    public static let windowID = "keyboard-help"
    let names: KeyboardLayoutNames

    public init(names: KeyboardLayoutNames) {
        self.names = names
    }

    public var body: some Scene {
        Window("Raccourcis clavier", id: Self.windowID) {
            KeyboardHelpView(names: names)
        }
        .windowResizability(.contentSize)
    }
}
#endif
