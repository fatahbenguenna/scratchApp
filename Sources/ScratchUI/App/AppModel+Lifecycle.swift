import Foundation
import Observation
import ScratchAudio
import ScratchCore

// MARK: - Cycle de vie (story 6.2)

extension AppModel {
    /// Démarre l'hôte audio, à la fin du lancement : après la bibliothèque, et après les préférences
    /// (3.4). L'hôte ne démarre jamais un moteur (RM-10). Si aucune sortie n'est disponible, il passe
    /// à « Sortie audio indisponible » et son horloge de secours garde les platines vivantes (D-35).
    func startHost() {
        guard let host else { return }
        host.start()
        hostStatusDidChange()
        hostNoticeDidChange()
    }

    /// iPhone et iPad, passage en arrière-plan (SF-81, RM-56 ; 6.5 « Passer en arrière-plan ») :
    /// les réglages en attente sont enregistrés tout de suite (3.4), puis l'hôte arrête tous les
    /// moteurs et coupe la sortie. Les sons chargés et leurs positions sont conservés ; `tick()`
    /// reprend l'application des commandes (`pump()`).
    public func enterBackground() {
        guard !isInBackground else { return }
        isInBackground = true
        savePreferencesNow()
        host?.suspend()
        if keepsScreenAwake { keepsScreenAwake = false }
    }

    /// Retour au premier plan : la sortie, ou l'horloge de secours, repart ; aucun moteur ne
    /// redémarre (RM-10).
    public func enterForeground() {
        guard isInBackground else { return }
        isInBackground = false
        host?.resume()
        wakeDisplay()
    }

    /// Mac : l'app se termine (⌘Q, fermeture de la fenêtre principale, Dock). Un réglage changé
    /// moins de 0,5 s avant n'est pas encore écrit : il l'est tout de suite (#97).
    public func willTerminate() {
        savePreferencesNow()
    }

    /// Règle du verrouillage automatique (D-37) : désactivé tant qu'un moteur tourne ou qu'un disque
    /// est tenu, sur l'une ou l'autre platine.
    static func keepsScreenAwake(_ snapshot: EngineSnapshot) -> Bool {
        DeckID.allCases.contains { snapshot[$0].motorOn || snapshot[$0].isHeld }
    }

    /// L'état de l'hôte a changé (démarrage, sortie perdue ou retrouvée, interruption) : badge à jour
    /// tout de suite (SF-16, SF-82), boucle d'affichage réveillée, puis nouvel abonnement. Ces
    /// changements ne passent pas par une commande : sans ce réveil, une boucle suspendue au repos
    /// garderait l'ancien état.
    func hostStatusDidChange() {
        guard let host else { return }
        if outputStatus != host.status { outputStatus = host.status }
        wakeDisplay()
        withObservationTracking {
            _ = host.status
        } onChange: { [weak self] in
            // Called before the new value is stored: read it on the next main-actor turn.
            Task { @MainActor in self?.hostStatusDidChange() }
        }
    }

    /// Avis de l'hôte audio (story 2.3 CA 8 ; UX §8.5) : interruption, sortie déconnectée, indisponible
    /// ou retrouvée. Chaque nouvel avis devient un bandeau, une seule fois ; puis nouvel abonnement.
    /// Seul un hôte qui publie des avis (`AudioNoticePosting`, comme `AudioEngineHost`) en donne.
    func hostNoticeDidChange() {
        guard let poster = host as? any AudioNoticePosting else { return }
        if let posted = poster.notice, posted.id != shownHostNoticeID {
            shownHostNoticeID = posted.id
            toasts.show(posted.notice.message)
        }
        withObservationTracking {
            _ = poster.notice
        } onChange: { [weak self] in
            // Called before the new value is stored: read it on the next main-actor turn.
            Task { @MainActor in self?.hostNoticeDidChange() }
        }
    }

    /// Réveille la boucle d'affichage si elle est suspendue au repos. `RootView` relie le
    /// `DisplayWakingEngine` du modèle à son horloge ; sans lui, la boucle ne se suspend jamais.
    func wakeDisplay() {
        (engine as? DisplayWakingEngine)?.onCommand?()
    }

    /// Scène de la CI (`--demo-scene`) : la démo sur A et sur B, puis le moteur de B (RM-57 : un
    /// seul clip partagé). Le moteur applique les commandes dans l'ordre : B est chargée avant de
    /// tourner. Jamais appelée sans l'argument (RM-01).
    func playDemoScene() async {
        await loadDemoAndWait(on: .a)
        await loadDemoAndWait(on: .b)
        engine.send(.motor(.b, on: true))
    }
}
