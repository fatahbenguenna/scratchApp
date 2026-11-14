import SwiftUI

/// Réglage de courbe du crossfader (SF-66, D-30 ; UX §5.13) : « Douce » ↔ « Franche », valeur
/// « Coupure franche », « Douce » ou « 60 % » ; VoiceOver par pas de 10 %.
struct CrossfaderCurveControl: View {
    let mixer: MixerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(verbatim: "Courbe").font(Theme.sectionLabel).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(verbatim: mixer.curveText).font(Theme.valueReadout).foregroundStyle(Theme.textPrimary)
            }
            HStack(spacing: 6) {
                Text(verbatim: "Douce").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                KnobFader(orientation: .horizontal, value: mixer.crossfaderCurve, knobLength: 20,
                          knobThickness: 28) { mixer.setCrossfaderCurve($0) }
                    .frame(height: 44)
                Text(verbatim: "Franche").font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Courbe du crossfader")
        .accessibilityValue(mixer.curveText.lowercased())
        .accessibilityAdjustableAction { direction in
            mixer.setCrossfaderCurve(mixer.crossfaderCurve + (direction == .increment ? 0.1 : -0.1))
        }
        .accessibilityIdentifier("mixer.curve")
    }
}
