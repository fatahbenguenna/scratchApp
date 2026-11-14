import ScratchCore
import SwiftUI

/// Voie de la table : libellé « VOIE A », VU-mètre à l'extérieur, fader vertical et valeur
/// (SF-65 ; UX §5.11). Le fader se saisit par son bouton, déplacement relatif ; VoiceOver l'ajuste
/// par pas de 5 %.
struct ChannelFader: View {
    let mixer: MixerViewModel
    let deck: DeckViewModel

    var body: some View {
        let id = deck.deck
        VStack(spacing: 8) {
            Text(verbatim: "VOIE \(id.rawValue)")
                .font(Theme.sectionLabel)
                .foregroundStyle(Theme.deckColor(id))
            HStack(spacing: 4) {
                if id == .a { VUMeterView(deck: deck) }
                KnobFader(orientation: .vertical, value: mixer.lineFaders[id]) { mixer.setLineFader(id, $0) }
                    .frame(width: 44)
                    .accessibilityElement()
                    .accessibilityLabel("Fader de voie \(id.rawValue)")
                    .accessibilityValue(mixer.lineFaderText(id))
                    .accessibilityAdjustableAction { direction in
                        let step = direction == .increment ? 0.05 : -0.05
                        mixer.setLineFader(id, mixer.lineFaders[id] + step)
                    }
                    .accessibilityIdentifier("mixer.channelFader.\(id.rawValue.lowercased())")
                if id == .b { VUMeterView(deck: deck) }
            }
            .frame(maxHeight: .infinity)
            Text(verbatim: mixer.lineFaderText(id))
                .font(Theme.valueReadout)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
    }
}
