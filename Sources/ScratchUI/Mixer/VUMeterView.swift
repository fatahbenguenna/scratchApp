import SwiftUI

/// VU-mètre d'une voie : 12 segments, couleurs de l'UX §5.15 et crête maintenue. Seule vue de la
/// table, avec SAT, qui suit chaque image (ADR-12).
struct VUMeterView: View {
    let deck: DeckViewModel

    var body: some View {
        let meter = deck.channelMeter
        let lit = meter.litSegments
        let peak = meter.peakSegment
        VStack(spacing: 2) {
            ForEach((0..<12).reversed(), id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index < lit || index == peak ? Self.color(of: index) : Theme.vuOff)
            }
        }
        .frame(width: 8)
        .accessibilityElement()
        .accessibilityLabel("Niveau de la voie \(deck.deck.rawValue)")
        .accessibilityValue(meter.accessibilityValue)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityIdentifier("mixer.vu.\(deck.deck.rawValue.lowercased())")
    }

    /// Segments 1 à 7 `vu.low`, 8 à 10 `vu.mid`, 11 et 12 `vu.high`.
    static func color(of index: Int) -> Color {
        index < 7 ? Theme.vuLow : (index < 10 ? Theme.vuMid : Theme.vuHigh)
    }
}
