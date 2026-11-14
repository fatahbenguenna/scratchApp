import ScratchCore
import SwiftUI

/// Voie de la table : libellé « VOIE A », VU-mètre à l'extérieur, fader vertical et valeur
/// (SF-65 ; UX §5.11). Le fader se saisit par son bouton, déplacement relatif ; VoiceOver l'ajuste
/// par pas de 5 %.
struct ChannelFader: View {
    let mixer: MixerViewModel
    let deck: DeckViewModel
    /// Horizontal : iPhone portrait (piste 197) et iPad portrait (piste 140), VU-mètre en option.
    var horizontal = false
    var showsMeter = true

    var body: some View {
        if horizontal {
            HStack(spacing: 8) {
                label
                if showsMeter, deck.deck == .a { VUMeterView(deck: deck, horizontal: true).frame(width: 80) }
                fader.frame(maxWidth: .infinity)
                value.frame(width: 44)
                if showsMeter, deck.deck == .b { VUMeterView(deck: deck, horizontal: true).frame(width: 80) }
            }
        } else {
            VStack(spacing: 8) {
                label
                HStack(spacing: 4) {
                    if deck.deck == .a { VUMeterView(deck: deck) }
                    fader.frame(width: 44)
                    if deck.deck == .b { VUMeterView(deck: deck) }
                }
                .frame(maxHeight: .infinity)
                value
            }
        }
    }

    private var label: some View {
        Text(verbatim: "VOIE \(deck.deck.rawValue)")
            .font(Theme.sectionLabel)
            .foregroundStyle(Theme.deckColor(deck.deck))
    }

    private var value: some View {
        Text(verbatim: mixer.lineFaderText(deck.deck))
            .font(Theme.valueReadout)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityHidden(true)
    }

    private var fader: some View {
        let id = deck.deck
        return KnobFader(orientation: horizontal ? .horizontal : .vertical, value: mixer.lineFaders[id],
                         knobLength: 20, knobThickness: 36) { mixer.setLineFader(id, $0) }
            .accessibilityElement()
            .accessibilityLabel("Fader de voie \(id.rawValue)")
            .accessibilityValue(mixer.lineFaderText(id))
            .accessibilityAdjustableAction { direction in
                mixer.setLineFader(id, mixer.lineFaders[id] + (direction == .increment ? 0.05 : -0.05))
            }
            .accessibilityIdentifier("mixer.channelFader.\(id.rawValue.lowercased())")
    }
}
