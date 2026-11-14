import ScratchCore
import SwiftUI

/// Table de l'iPad portrait, entre les deux bandes (UX §4.4) : trois lignes de 780 pt.
/// Ligne 1 : Bibliothèque, SAT, badge de sortie, Réglages. Ligne 2 : voies A et B horizontales avec
/// VU-mètres de 80 × 8. Ligne 3 : courbe, crossfader (course ≈ 312), Hamster.
struct StackedMixerView: View {
    let model: AppModel
    let intents: any DeckIntents
    let outputStatus: AudioOutputStatus

    var body: some View {
        let mixer = model.mixer
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                LibraryButton(intents: intents)
                Spacer(minLength: 8)
                SaturationIndicator(mixer: mixer)
                OutputBadge(status: outputStatus)
                Spacer(minLength: 8)
                SettingsButton(intents: intents)
            }
            .frame(height: 44)
            HStack(spacing: 24) {
                ChannelFader(mixer: mixer, deck: model.deckA, horizontal: true)
                ChannelFader(mixer: mixer, deck: model.deckB, horizontal: true)
            }
            .frame(height: 44)
            HStack(spacing: 16) {
                CrossfaderCurveControl(mixer: mixer, showsGraph: false).frame(width: 200)
                CrossfaderView(mixer: mixer, height: 56).frame(maxWidth: 360)
                HamsterToggle(mixer: mixer).frame(width: 140)
            }
            .frame(height: 56)
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Table de mixage")
    }
}
