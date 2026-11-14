import SwiftUI

/// Bouton « Table » et son panneau (iPhone, D-30 ; UX §5.23) : courbe et hamster dans un popover de
/// 280 pt, conservé en popover. Fourni ici, placé par la story 4.4.
struct MixerSettingsPopover: View {
    let mixer: MixerViewModel
    @State private var isPresented = false

    var body: some View {
        Button { isPresented = true } label: {
            Label("Table", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(RaisedButtonStyle())
        .accessibilityLabel("Réglages de la table de mixage")
        .accessibilityIdentifier("mixer.settingsButton")
        .popover(isPresented: $isPresented) {
            VStack(spacing: 12) {
                CrossfaderCurveControl(mixer: mixer)
                HamsterToggle(mixer: mixer)
            }
            .padding(16)
            .frame(width: 280)
            .presentationCompactAdaptation(.popover)
            .preferredColorScheme(.dark)
        }
    }
}
