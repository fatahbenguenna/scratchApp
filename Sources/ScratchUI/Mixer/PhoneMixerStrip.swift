import ScratchCore
import SwiftUI

/// Table de l'iPhone portrait, en bas sous le pouce (UX §4.2) : SAT et badge de sortie, fader de voie
/// de la platine affichée et bouton « Table » (courbe, hamster, D-30), crossfader pleine largeur entre
/// les VU-mètres des deux voies : la platine masquée reste visible au bout du crossfader.
struct PhoneMixerStrip: View {
    let model: AppModel
    let displayed: DeckID
    let outputStatus: AudioOutputStatus

    var body: some View {
        let mixer = model.mixer
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                SaturationIndicator(mixer: mixer)
                OutputBadge(status: outputStatus)
                Spacer(minLength: 0)
            }
            .frame(height: 24)
            HStack(spacing: 8) {
                ChannelFader(mixer: mixer, deck: model.deck(displayed), horizontal: true, showsMeter: false)
                MixerSettingsPopover(mixer: mixer).labelStyle(.iconOnly)
            }
            .frame(height: 44)
            HStack(spacing: 4) {
                VUMeterView(deck: model.deckA).frame(width: 6, height: 36)
                CrossfaderView(mixer: mixer, height: 56)
                VUMeterView(deck: model.deckB).frame(width: 6, height: 36)
            }
            .frame(height: 56)
        }
    }
}
