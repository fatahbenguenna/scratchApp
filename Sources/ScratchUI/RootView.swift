import ScratchCore
import SwiftUI

/// Vue racine de ScratchApp : platine A, table de mixage, platine B (spec 3.4), animée par l'horloge
/// d'affichage qui appelle `AppModel.tick()` une fois par image (UX §10.1).
///
/// `RootView()` affiche l'environnement d'aperçu (faux moteur, `PreviewDeckIntents`) tant que la
/// story 6.1 n'injecte pas le vrai modèle par `init(model:intents:)`. Pour que la boucle se suspende
/// au repos, l'`AppModel` reçoit un `DisplayWakingEngine` à la place du moteur.
public struct RootView: View {
    @State private var session: RootSession

    /// Environnement d'aperçu (faux moteur), en attendant la story 6.1.
    public init() {
        let environment = PreviewEnvironment()
        self.init(model: environment.model, intents: environment.intents)
    }

    public init(model: AppModel, intents: any DeckIntents) {
        _session = State(initialValue: RootSession(model: model, intents: intents))
    }

    public var body: some View {
        MainLayoutView(model: session.model, intents: session.intents)
            .background(DisplayLinkHost(driver: session.driver).accessibilityHidden(true))
    }
}

/// Modèle, intentions et horloge d'une fenêtre, gardés ensemble par `@State`.
@MainActor
final class RootSession {
    let model: AppModel
    let intents: any DeckIntents
    let driver: DisplayLinkDriver

    init(model: AppModel, intents: any DeckIntents) {
        self.model = model
        self.intents = intents
        let driver = DisplayLinkDriver { [weak model] in
            guard let model else { return true }
            model.tick()
            let frames = EngineSnapshot(decks: DeckPair(a: model.deckA.frame, b: model.deckB.frame),
                                        mixer: model.mixer.frame)
            return frames.isIdle
        }
        self.driver = driver
        if let waking = model.engine as? DisplayWakingEngine {
            waking.onCommand = { [weak driver] in MainActor.assumeIsolated { driver?.wake() } }
            driver.allowsSuspension = true
        }
    }
}

#if DEBUG
#Preview("Premier lancement") {
    RootView().frame(width: 960, height: 600)
}
#endif
