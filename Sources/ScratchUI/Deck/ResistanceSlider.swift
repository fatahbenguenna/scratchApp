import SwiftUI

/// Curseur RÉSISTANCE DU VINYLE (SF-21, SF-23 ; UX §5.5) : ligne de 44, libellé et valeur, piste
/// Léger ↔ Lourd ; 0 à 100 % par pas de 1 % au doigt, 50 % par défaut ; réglable d'un autre doigt
/// pendant le scratch (6.7) ; VoiceOver par pas de 5 %.
struct ResistanceSlider: View {
    let model: DeckViewModel
    /// iPhone paysage : libellé court « Résistance ».
    var isCompact = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: isCompact ? "Résistance" : "Résistance du vinyle")
                Spacer(minLength: 4)
                Text(verbatim: model.resistanceText).font(Theme.valueReadout)
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.textSecondary)
            .frame(height: 14)
            HStack(spacing: 6) {
                if !isCompact { Text(verbatim: "Léger").font(Theme.caption).foregroundStyle(Theme.textSecondary) }
                KnobFader(orientation: .horizontal, value: model.resistance, knobLength: 20, knobThickness: 32) {
                    model.setResistance(($0 * 100).rounded() / 100)
                }
                if !isCompact { Text(verbatim: "Lourd").font(Theme.caption).foregroundStyle(Theme.textSecondary) }
            }
            .frame(height: 30)
        }
        .frame(height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Résistance du vinyle, \(model.deckName)")
        .accessibilityValue(model.resistanceText)
        .accessibilityAdjustableAction { direction in
            model.setResistance(model.resistance + (direction == .increment ? 0.05 : -0.05))
        }
        .accessibilityIdentifier("deck.\(model.deck.rawValue.lowercased()).resistance")
    }
}
