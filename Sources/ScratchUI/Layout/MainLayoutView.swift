import ScratchCore
import SwiftUI

/// Disposition côte à côte A | table de mixage | B (spec 3.4 ; UX §4.5 iPad paysage, §4.6 Mac ;
/// D-38, D-39). Les dispositions iPhone et iPad portrait arrivent en 4.4.
///
/// La table de mixage est un emplacement réservé jusqu'à la story 4.2.
public struct MainLayoutView: View {
    let model: AppModel
    let intents: any DeckIntents

    public init(model: AppModel, intents: any DeckIntents) {
        self.model = model
        self.intents = intents
    }

    public var body: some View {
        GeometryReader { proxy in
            let metrics = MainLayoutMetrics(width: proxy.size.width, height: proxy.size.height, idiom: Self.idiom)
            HStack(spacing: metrics.gap) {
                column(DeckView(model: model.deckA, intents: intents, metrics: metrics))
                column(MixerPlaceholder()).frame(width: metrics.mixerWidth)
                column(DeckView(model: model.deckB, intents: intents, metrics: metrics))
            }
            .padding(metrics.gutter)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Theme.bgApp)
        #if os(macOS)
        .frame(minWidth: MainLayoutMetrics.macMinimumSize.width, minHeight: MainLayoutMetrics.macMinimumSize.height)
        #endif
        .preferredColorScheme(.dark)
    }

    /// Zone de platine ou de table : fond `bg.surface`, rayon 12, centrée verticalement (UX §4.6, §9.5).
    /// Le fond déborde de 6 pt dans les gouttières pour aérer le contenu sans réduire P.
    private func column(_ content: some View) -> some View {
        content
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.panelRadius)
                    .fill(Theme.bgSurface)
                    .padding(-6)
            )
    }

    private static var idiom: MainLayoutMetrics.Idiom {
        #if os(macOS)
        return .mac
        #else
        return .tablet
        #endif
    }
}

/// Emplacement de la table de mixage (story 4.2).
private struct MixerPlaceholder: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Table de mixage").font(Theme.caption.weight(.bold)).textCase(.uppercase)
            Text("A ↔ B").font(Theme.caption)
        }
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Mac 1200 × 760, démo en lecture") {
    let environment = PreviewEnvironment(scenario: .playing)
    return RootView(model: environment.model, intents: environment.intents)
        .frame(width: 1200, height: 760)
}
#endif
