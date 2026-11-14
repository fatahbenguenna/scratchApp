import ScratchCore
import SwiftUI

/// iPhone portrait, fenêtre iPad étroite : une platine plein écran (spec 3.4 ; UX §4.2, §4.7). Barre
/// supérieure avec le sélecteur A | B, Bibliothèque et Réglages ; colonne de la platine affichée ; table
/// en bas (fader de voie de la platine affichée, crossfader), à portée de pouce. La platine masquée
/// continue de tourner et de jouer : seul son affichage change.
struct SingleDeckLayout: View {
    let model: AppModel
    let intents: any DeckIntents
    let outputStatus: AudioOutputStatus
    let metrics: MainLayoutMetrics
    @Binding var selected: DeckID

    var body: some View {
        let compact = metrics.idiom == .phoneCompact
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                DeckSelector(model: model, selected: $selected)
                Spacer(minLength: 8)
                LibraryButton(intents: intents)
                SettingsButton(intents: intents)
            }
            .labelStyle(.iconOnly)
            .frame(height: 44)
            DeckView(model: model.deck(selected), intents: intents, metrics: metrics)
                .id(selected)
                .transition(.opacity)
                .padding(.top, compact ? 6 : 8)
            Rectangle().fill(Theme.strokeSubtle).frame(height: 1).padding(.vertical, compact ? 4 : 6)
            PhoneMixerStrip(model: model, displayed: selected, outputStatus: outputStatus)
            Spacer(minLength: compact ? 2 : 8)
        }
        .padding(.horizontal, metrics.gutter)
    }
}
