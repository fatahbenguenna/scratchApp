import ScratchCore
import SwiftUI

/// iPad portrait : platines empilées en bandes, table entre les deux (spec 3.4, D-29 ; UX §4.4).
/// La bande de B est en miroir : les disques sont en diagonale, un par main.
struct StackedLayout: View {
    let model: AppModel
    let intents: any DeckIntents
    let outputStatus: AudioOutputStatus
    let metrics: MainLayoutMetrics
    let bandHeight: CGFloat

    var body: some View {
        VStack(spacing: 12) {
            DeckBandView(model: model.deckA, intents: intents, metrics: metrics).frame(height: bandHeight)
            StackedMixerView(model: model, intents: intents, outputStatus: outputStatus)
                .frame(height: LayoutMetrics.stackedMixerHeight)
                .background(RoundedRectangle(cornerRadius: Theme.panelRadius).fill(Theme.bgSurface))
            DeckBandView(model: model.deckB, intents: intents, metrics: metrics).frame(height: bandHeight)
        }
        .padding(.horizontal, metrics.gutter)
        .padding(.vertical, 12)
    }
}
