import SwiftUI

/// Indicateur SAT (SF-65, D-13 ; UX §5.16) : témoin de 10 pt et « SAT » ; éteint, `warning`
/// (limiteur actif), `danger` (écrêtage), maintien 1 s porté par `SaturationState`.
struct SaturationIndicator: View {
    let mixer: MixerViewModel

    var body: some View {
        let state = mixer.saturation
        HStack(spacing: 4) {
            Text(verbatim: "SAT").font(Theme.sectionLabel).foregroundStyle(Theme.textSecondary)
            Circle().fill(Self.color(state.level)).frame(width: 10, height: 10)
        }
        .accessibilityElement()
        .accessibilityLabel("Saturation de la sortie")
        .accessibilityValue(state.accessibilityValue)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("mixer.saturation")
    }

    static func color(_ level: SaturationState.Level) -> Color {
        switch level {
        case .none: return Theme.vuOff
        case .limiting: return Theme.warning
        case .clipping: return Theme.danger
        }
    }
}
