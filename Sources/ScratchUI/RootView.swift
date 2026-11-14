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

    #if os(macOS)
    /// Mac : le contrôleur clavier est partagé avec les menus (`ScratchCommands`, attachés en 6.2).
    public init(model: AppModel, intents: any DeckIntents, keyboard: KeyboardController) {
        _session = State(initialValue: RootSession(model: model, intents: intents, keyboard: keyboard))
    }
    #endif

    public var body: some View {
        MainLayoutView(model: session.model, intents: session.intents)
            .background(DisplayLinkHost(driver: session.driver).accessibilityHidden(true))
            #if os(macOS)
            .background(KeyboardHost(controller: session.keyboard).accessibilityHidden(true))
            #endif
    }
}

/// Modèle, intentions et horloge d'une fenêtre, gardés ensemble par `@State`.
@MainActor
final class RootSession {
    let model: AppModel
    let intents: any DeckIntents
    let driver: DisplayLinkDriver
    #if os(macOS)
    /// Clavier de la fenêtre principale (story 5.1).
    let keyboard: KeyboardController
    #endif

    #if os(macOS)
    init(model: AppModel, intents: any DeckIntents, keyboard: KeyboardController? = nil) {
        self.model = model
        self.intents = intents
        self.keyboard = keyboard ?? KeyboardController(model: model)
        driver = Self.makeDriver(for: model)
    }
    #else
    init(model: AppModel, intents: any DeckIntents) {
        self.model = model
        self.intents = intents
        driver = Self.makeDriver(for: model)
    }
    #endif

    /// Horloge d'affichage : `tick()` à chaque image, suspendue au repos si le moteur la réveille.
    private static func makeDriver(for model: AppModel) -> DisplayLinkDriver {
        let driver = DisplayLinkDriver { [weak model] in
            guard let model else { return true }
            model.tick()
            let frames = EngineSnapshot(decks: DeckPair(a: model.deckA.frame, b: model.deckB.frame),
                                        mixer: model.mixer.frame)
            return frames.isIdle
        }
        if let waking = model.engine as? DisplayWakingEngine {
            waking.onCommand = { [weak driver] in MainActor.assumeIsolated { driver?.wake() } }
            driver.allowsSuspension = true
        }
        return driver
    }
}

#if DEBUG
#Preview("Premier lancement") {
    RootView().frame(width: 960, height: 600)
}
#endif
