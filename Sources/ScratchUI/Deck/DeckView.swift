import ScratchCore
import SwiftUI

/// Platine en arrangement « colonne » (UX §4.1) : en-tête, forme d'onde et aperçu (4.6),
/// [plateau P | pitch], transport (START/STOP, 33⅓ / 45, SET CUE, CUE), résistance. Conteneur
/// d'accessibilité « Platine A ».
///
/// Les emplacements des stories suivantes sont réservés dès maintenant : le diamètre du plateau suit
/// déjà les règles de taille de l'UX (§4.5, §4.6).
struct DeckView: View {
    let model: DeckViewModel
    let intents: any DeckIntents
    let metrics: MainLayoutMetrics

    var body: some View {
        let spacings = metrics.rowSpacings
        VStack(alignment: .leading, spacing: 0) {
            DeckHeaderView(model: model, intents: intents, width: metrics.columnWidth, height: metrics.headerHeight)
            reserved(height: metrics.waveformHeight).padding(.top, spacings[0])     // waveform (4.6)
            reserved(height: metrics.overviewHeight).padding(.top, spacings[1])     // overview (4.6)
            HStack(spacing: metrics.platterSpacing) {
                TurntableView(model: model, intents: intents, platter: metrics.platter)
                PitchFader(model: model, height: metrics.platter, showsLabel: metrics.idiom != .phoneLandscape)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, spacings[2])
            TransportControls(model: model, metrics: metrics).padding(.top, spacings[3])
            ResistanceSlider(model: model, isCompact: metrics.idiom == .phoneLandscape).padding(.top, spacings[4])
        }
        .frame(width: metrics.columnWidth)
        .deckDropZone(model: model, intents: intents)  // 5.2 (Hugo): drop target over the whole deck
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Platine \(model.deck.rawValue)")
    }

    private func reserved(height: CGFloat) -> some View {
        Color.clear.frame(height: height).accessibilityHidden(true)
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
