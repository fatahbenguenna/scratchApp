import ScratchCore
import SwiftUI

/// Platine en arrangement « bande » (iPad portrait, UX §4.1, §4.4) : [plateau P | 8 | pitch 44] 16
/// [panneau 280 : en-tête, forme d'onde et aperçu (4.6), transport en grille 2 × 2, résistance (4.5)].
/// La platine B est en miroir (panneau à gauche) : les deux disques sont en diagonale, un par main.
struct DeckBandView: View {
    let model: DeckViewModel
    let intents: any DeckIntents
    let metrics: MainLayoutMetrics

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if model.deck == .b { panel }
            HStack(spacing: metrics.platterSpacing) {
                TurntableView(model: model, intents: intents, platter: metrics.platter)
                    .accessibilitySortPriority(DeckReadingOrder.disc)
                PitchFader(model: model, height: metrics.platter)
                    .accessibilitySortPriority(DeckReadingOrder.pitch)
            }
            if model.deck == .a { panel }
        }
        .frame(maxWidth: .infinity)
        .deckDropZone(model: model, intents: intents)  // 5.2: drop target over the whole band (UX §5.9)
        .macFocusSection()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Platine \(model.deck.rawValue)")
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            DeckHeaderView(model: model, intents: intents, width: LayoutMetrics.bandPanelWidth)
                .accessibilitySortPriority(DeckReadingOrder.header)
            ZoomedWaveformView(model: model, width: LayoutMetrics.bandPanelWidth, height: 56)
            WaveformOverviewView(model: model, width: LayoutMetrics.bandPanelWidth, height: 32)
                .accessibilitySortPriority(DeckReadingOrder.overview)
            TransportControls(model: model, metrics: metrics, grid: true)
                .accessibilitySortPriority(DeckReadingOrder.transport)
            ResistanceSlider(model: model)
                .accessibilitySortPriority(DeckReadingOrder.resistance)
        }
        .frame(width: LayoutMetrics.bandPanelWidth)
    }
}
