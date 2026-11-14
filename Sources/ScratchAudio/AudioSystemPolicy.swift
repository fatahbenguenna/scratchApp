import ScratchCore

/// Avis publié par l'hôte audio pour le bandeau de l'interface (story 2.3 CA 8 ; UX §8.5).
public enum AudioHostNotice: Equatable, Sendable {
    /// Interruption système (appel, Siri, alarme) : platines arrêtées (SF-18).
    case interrupted
    /// La sortie utilisée a disparu (casque, interface USB) : platines arrêtées (6.5, D-04).
    case outputDisconnected
    /// Aucune sortie, ou démarrage impossible : nouvel essai automatique (SF-82).
    case outputUnavailable
    /// Une sortie est de nouveau disponible après une indisponibilité (SF-82).
    case outputAvailable(name: String)

    /// Texte du bandeau (UX §8.5).
    public var message: String {
        switch self {
        case .interrupted: return "Lecture interrompue par le système. Appuyez sur START pour reprendre."
        case .outputDisconnected: return "Sortie audio déconnectée : les platines sont arrêtées."
        case .outputUnavailable: return "Sortie audio indisponible. ScratchApp réessaiera automatiquement."
        case let .outputAvailable(name): return "Sortie audio disponible : \(name)."
        }
    }
}

/// Plateforme de l'hôte. La politique est une seule fonction pure, testée sur macOS pour les deux.
public enum AudioPlatform: Equatable, Sendable {
    case iOS
    case macOS
}

/// État de l'hôte au moment d'un événement, nécessaire à la décision.
public struct AudioHostContext: Equatable, Sendable {
    public var platform: AudioPlatform
    /// La sortie est indisponible : l'horloge de secours rend le moteur et l'hôte réessaie (SF-82).
    public var isOutputUnavailable: Bool
    /// L'hôte est suspendu (arrière-plan iOS, SF-81) : aucune sortie ne redémarre avant `resume()`.
    public var isSuspended: Bool
    /// macOS, `configurationChanged` : le périphérique utilisé est toujours connecté (D-04).
    public var usedDeviceStillPresent: Bool

    public init(platform: AudioPlatform, isOutputUnavailable: Bool = false, isSuspended: Bool = false,
                usedDeviceStillPresent: Bool = true) {
        self.platform = platform
        self.isOutputUnavailable = isOutputUnavailable
        self.isSuspended = isSuspended
        self.usedDeviceStillPresent = usedDeviceStillPresent
    }
}

/// Action de l'hôte. `AudioSystemPolicy` les renvoie dans l'ordre d'exécution.
public enum AudioHostAction: Equatable, Sendable {
    /// `engine.send(.stopAllMotors)` (RM-56).
    case stopAllMotors
    /// `engine.pump()` : applique tout de suite les commandes en attente. N'apparaît que lorsque
    /// aucun fil ne rend (sortie arrêtée, horloge de secours à l'arrêt) : un seul fil de rendu.
    case applyPendingCommands
    /// Arrête la sortie matérielle.
    case stopOutput
    /// Démarre l'horloge de secours : disques vivants, silence (SF-82).
    case startFallbackClock
    /// iOS : reconfigure et réactive la session (services média réinitialisés).
    case resetSession
    /// Reconstruit le graphe sur la sortie courante du système et envoie `outputSampleRate`.
    case rebuildGraph
    /// Démarre la sortie, horloge de secours arrêtée d'abord ; l'issue est passée à
    /// `AudioSystemPolicy.actionsAfterStart`.
    case startOutput
    /// Republie le nom de la sortie (CA 7).
    case refreshOutputName
    /// Publie un avis pour l'interface (CA 8).
    case notify(AudioHostNotice)
}

/// Politique de l'hôte audio face aux événements du système (story 2.3 ; architecture §7.3 ;
/// D-04, D-35). Fonction pure, sans `#if`, testée sur macOS avec des événements simulés.
///
/// Règle unique : un choix volontaire de sortie garde l'état des moteurs ; la perte de la sortie
/// utilisée, une interruption, la réinitialisation des services média ou la veille les mettent à STOP ;
/// la reprise est toujours manuelle (RM-10). Quand la sortie est indisponible, chaque changement de
/// route ou de configuration et chaque tic de la minuterie (2 s) relancent un essai (SF-82).
public enum AudioSystemPolicy {
    /// Intervalle du nouvel essai tant que la sortie est indisponible (SF-82, D-35).
    public static let retryInterval: Double = 2

    /// Actions à exécuter, dans l'ordre, pour `event`.
    public static func actions(for event: AudioSystemEvent, context: AudioHostContext) -> [AudioHostAction] {
        let actions = unsuspendedActions(for: event, context: context)
        // Suspended (iOS background): only the motor safety survives; `resume()` restarts the output.
        return context.isSuspended ? actions.filter { $0 == .stopAllMotors } : actions
    }

    /// Actions après une tentative de démarrage de la sortie.
    public static func actionsAfterStart(succeeded: Bool, outputName: String,
                                         context: AudioHostContext) -> [AudioHostAction] {
        guard !context.isSuspended else { return [] }
        if succeeded {
            return context.isOutputUnavailable
                ? [.refreshOutputName, .notify(.outputAvailable(name: outputName))]
                : [.refreshOutputName]
        }
        // The banner is posted on the transition only, not on every failed retry.
        return context.isOutputUnavailable ? [.startFallbackClock] : [.startFallbackClock, .notify(.outputUnavailable)]
    }

    /// Actions à chaque tic de la minuterie de nouvel essai.
    public static func actionsOnRetryTick(context: AudioHostContext) -> [AudioHostAction] {
        context.isOutputUnavailable && !context.isSuspended ? [.startOutput] : []
    }

    // MARK: Interne

    /// Arrêt des moteurs appliqué avant que la sortie suivante ne rende (CA 2 : aucun son sur le
    /// haut-parleur). Sortie active : on l'arrête, puis on applique STOP avec `pump()`. Sortie
    /// indisponible : l'horloge de secours rend déjà, en silence, et appliquera STOP.
    private static func stopBeforeNextOutput(_ context: AudioHostContext) -> [AudioHostAction] {
        context.isOutputUnavailable
            ? [.stopAllMotors]
            : [.stopOutput, .stopAllMotors, .applyPendingCommands]
    }

    private static func unsuspendedActions(for event: AudioSystemEvent, context: AudioHostContext) -> [AudioHostAction] {
        switch event {
        case .interruptionBegan:
            return [.stopAllMotors, .stopOutput, .startFallbackClock, .notify(.interrupted)]
        case .interruptionEnded:
            return [.startOutput]
        case .routeChanged(previousDeviceUnavailable: true):
            return stopBeforeNextOutput(context) + [.notify(.outputDisconnected), .startOutput]
        case .routeChanged(previousDeviceUnavailable: false):
            return context.isOutputUnavailable ? [.startOutput] : [.refreshOutputName]
        case .configurationChanged:
            if context.isOutputUnavailable { return [.rebuildGraph, .startOutput] }
            if context.platform == .macOS, !context.usedDeviceStillPresent {
                return stopBeforeNextOutput(context) + [.notify(.outputDisconnected), .rebuildGraph, .startOutput]
            }
            // Deliberate change (new default output, other sample rate): motors keep their state.
            return [.rebuildGraph, .startOutput]
        case .mediaServicesReset:
            return stopBeforeNextOutput(context) + [.resetSession, .rebuildGraph, .startOutput]
        case .systemWillSleep:
            return stopBeforeNextOutput(context)
        case .systemDidWake:
            return context.isOutputUnavailable ? [.rebuildGraph, .startOutput] : [.startOutput]
        }
    }
}
