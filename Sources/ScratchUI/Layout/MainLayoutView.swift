import ScratchCore
import SwiftUI

/// Écran principal (spec 3.4 ; UX §4.1 à §4.7 ; D-29, D-38, D-39) : la disposition dépend de la taille
/// de la fenêtre, jamais du modèle d'appareil (`LayoutMetrics.kind`). Côte à côte A | table | B (Mac,
/// iPad paysage), côte à côte compacte (iPhone paysage), une platine (iPhone portrait), empilée (iPad
/// portrait).
///
/// Côte à côte, la table a la hauteur des colonnes de platine et son crossfader est aligné sur la
/// rangée de transport. Sur iOS, un changement de taille (rotation, disposition, multitâche) relâche
/// un disque tenu (RM-60) et les gestes système du bord inférieur sont différés.
public struct MainLayoutView: View {
    let model: AppModel
    let intents: any DeckIntents
    /// Statut de sortie affiché par le badge ; `AppModel.outputStatus` par défaut (statut injecté
    /// dans les aperçus jusqu'à la 6.2).
    let outputStatus: AudioOutputStatus?
    /// Platine affichée en disposition « une platine ».
    @State private var selectedDeck = DeckID.a

    public init(model: AppModel, intents: any DeckIntents, outputStatus: AudioOutputStatus? = nil) {
        self.model = model
        self.intents = intents
        self.outputStatus = outputStatus
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let status = outputStatus ?? model.outputStatus
            Group {
                switch LayoutMetrics.kind(width: size.width, height: size.height, isMac: Self.isMac) {
                case .sideBySide:
                    sideBySide(MainLayoutMetrics(width: size.width, height: size.height, idiom: Self.idiom), status)
                case .compactSideBySide:
                    sideBySide(LayoutMetrics.compactSideBySide(width: size.width, height: size.height), status)
                case .singleDeck:
                    SingleDeckLayout(model: model, intents: intents, outputStatus: status,
                                     metrics: LayoutMetrics.singleDeck(width: size.width, height: size.height),
                                     selected: $selectedDeck)
                case .stacked:
                    StackedLayout(model: model, intents: intents, outputStatus: status,
                                  metrics: LayoutMetrics.stacked(width: size.width, height: size.height),
                                  bandHeight: LayoutMetrics.bandHeight(height: size.height))
                }
            }
            .frame(width: size.width, height: size.height)
            #if os(iOS)
            .onChange(of: size) {
                // Rotation or layout change: release held discs, motors unchanged (RM-60).
                model.deckA.discInput.cancelAll()
                model.deckB.discInput.cancelAll()
            }
            #endif
        }
        .background(Theme.bgApp)
        #if os(macOS)
        .frame(minWidth: MainLayoutMetrics.macMinimumSize.width, minHeight: MainLayoutMetrics.macMinimumSize.height)
        #else
        .defersSystemGestures(on: .bottom)
        #endif
        .preferredColorScheme(.dark)
    }

    /// A | table | B (Mac, iPad paysage, iPhone paysage).
    private func sideBySide(_ metrics: MainLayoutMetrics, _ status: AudioOutputStatus) -> some View {
        HStack(spacing: metrics.gap) {
            column(DeckView(model: model.deckA, intents: intents, metrics: metrics), metrics)
            column(
                MixerView(mixer: model.mixer, deckA: model.deckA, deckB: model.deckB, intents: intents,
                          outputStatus: status, metrics: metrics)
                    .padding(.bottom, metrics.crossfaderBottomInset)
                    .frame(height: metrics.columnContentHeight),
                metrics
            )
            .frame(width: metrics.mixerWidth)
            column(DeckView(model: model.deckB, intents: intents, metrics: metrics), metrics)
        }
        .padding(.horizontal, metrics.gutter)
        .padding(.vertical, metrics.idiom == .phoneLandscape ? 0 : metrics.gutter)
    }

    /// Zone de platine ou de table : fond `bg.surface`, rayon 12, centrée verticalement (UX §4.6, §9.5).
    /// Le fond déborde dans les gouttières (6 pt, 2 en iPhone paysage) sans réduire P.
    private func column(_ content: some View, _ metrics: MainLayoutMetrics) -> some View {
        content
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.panelRadius)
                    .fill(Theme.bgSurface)
                    .padding(metrics.gap < 16 ? -2 : -6)
            )
    }

    private static var isMac: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }

    private static var idiom: MainLayoutMetrics.Idiom {
        #if os(macOS)
        return .mac
        #else
        return .tablet
        #endif
    }
}

#if DEBUG
#Preview("Mac 1200 × 760, démo en lecture") {
    let environment = PreviewEnvironment(scenario: .playing)
    return RootView(model: environment.model, intents: environment.intents)
        .frame(width: 1200, height: 760)
}

#if os(iOS)
#Preview("iPhone portrait (une platine)") {
    let environment = PreviewEnvironment(scenario: .playing)
    return RootView(model: environment.model, intents: environment.intents).frame(width: 393, height: 759)
}

#Preview("iPhone paysage (côte à côte compacte)") {
    let environment = PreviewEnvironment(scenario: .playing)
    return RootView(model: environment.model, intents: environment.intents).frame(width: 734, height: 372)
}

#Preview("iPad portrait (empilée)") {
    let environment = PreviewEnvironment(scenario: .playing)
    return RootView(model: environment.model, intents: environment.intents).frame(width: 820, height: 1136)
}

#Preview("iPad paysage (côte à côte)") {
    let environment = PreviewEnvironment(scenario: .playing)
    return RootView(model: environment.model, intents: environment.intents).frame(width: 1180, height: 776)
}
#endif
#endif
