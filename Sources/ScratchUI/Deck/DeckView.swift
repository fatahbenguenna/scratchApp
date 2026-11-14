import ScratchCore
import SwiftUI

/// Platine en arrangement « colonne » (UX §4.1) : en-tête, forme d'onde zoomée et aperçu (4.6),
/// [plateau P | pitch], transport (START/STOP, 33⅓ / 45, SET CUE, CUE), résistance. Conteneur
/// d'accessibilité « Platine A ». Le diamètre du plateau suit les règles de taille de l'UX (§4.5, §4.6).
struct DeckView: View {
    let model: DeckViewModel
    let intents: any DeckIntents
    let metrics: MainLayoutMetrics

    var body: some View {
        let spacings = metrics.rowSpacings
        VStack(alignment: .leading, spacing: 0) {
            DeckHeaderView(model: model, intents: intents, width: metrics.columnWidth, height: metrics.headerHeight)
                .accessibilitySortPriority(DeckReadingOrder.header)
            ZoomedWaveformView(model: model, width: metrics.columnWidth, height: metrics.waveformHeight)
                .padding(.top, spacings[0])
            WaveformOverviewView(model: model, width: metrics.columnWidth, height: metrics.overviewVisualHeight)
                .frame(height: metrics.overviewHeight)
                .padding(.top, spacings[1])
                .accessibilitySortPriority(DeckReadingOrder.overview)
            HStack(spacing: metrics.platterSpacing) {
                TurntableView(model: model, intents: intents, platter: metrics.platter)
                    .accessibilitySortPriority(DeckReadingOrder.disc)
                PitchFader(model: model, height: metrics.platter, showsLabel: metrics.idiom != .phoneLandscape)
                    .accessibilitySortPriority(DeckReadingOrder.pitch)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, spacings[2])
            TransportControls(model: model, metrics: metrics).padding(.top, spacings[3])
                .accessibilitySortPriority(DeckReadingOrder.transport)
            ResistanceSlider(model: model, isCompact: metrics.idiom == .phoneLandscape).padding(.top, spacings[4])
                .accessibilitySortPriority(DeckReadingOrder.resistance)
        }
        .frame(width: metrics.columnWidth)
        .macFocusSection()  // Tab: deck A, then the mixer, then deck B (UX §6.4)
        .deckDropZone(model: model, intents: intents)  // 5.2 (Hugo): drop target over the whole deck
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Platine \(model.deck.rawValue)")
    }
}

#if DEBUG
#Preview("Platine A chargée") {
    let environment = PreviewEnvironment(scenario: .playing)
    return DeckView(model: environment.model.deckA, intents: environment.intents,
                    metrics: MainLayoutMetrics(width: 1200, height: 760, idiom: .mac))
        .padding()
        .background(Theme.bgSurface)
        .preferredColorScheme(.dark)
}
#endif
