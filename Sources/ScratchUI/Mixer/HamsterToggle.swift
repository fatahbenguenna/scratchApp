import SwiftUI

/// Interrupteur Hamster (SF-67 ; UX §5.14) : inverse le crossfader ; les lettres d'extrémité
/// s'échangent, le bouton ne bouge pas.
struct HamsterToggle: View {
    let mixer: MixerViewModel

    var body: some View {
        Toggle(isOn: Binding(get: { mixer.hamster }, set: { mixer.setHamster($0) })) {
            Text(verbatim: "Hamster").font(Theme.body).foregroundStyle(Theme.textPrimary)
        }
        .toggleStyle(.switch)
        .frame(minHeight: 44)
        .accessibilityLabel("Hamster, inversion du crossfader")
        .accessibilityValue(mixer.hamster ? "activé" : "désactivé")
        .accessibilityIdentifier("mixer.hamster")
    }
}
