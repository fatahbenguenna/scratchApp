/// Sortie audio active (3.2, SF-16).
public struct AudioOutputInfo: Equatable, Sendable {
    /// Nom affiché de la sortie : « Haut-parleur », « Casque », « MPC Sample (USB) »…
    public var name: String
    /// Fréquence matérielle, en Hz.
    public var sampleRate: Double
    /// Taille de tampon obtenue, en trames (objectif 256, SF-78).
    public var bufferFrames: Int
    /// Latence de sortie annoncée par le système, en secondes (recette SF-78).
    public var outputLatency: Double

    public init(name: String, sampleRate: Double, bufferFrames: Int, outputLatency: Double) {
        self.name = name
        self.sampleRate = sampleRate
        self.bufferFrames = bufferFrames
        self.outputLatency = outputLatency
    }
}

/// État de l'hôte audio, affiché par l'UI (SF-82).
public enum AudioOutputStatus: Equatable, Sendable {
    /// Pas encore démarré, ou arrêté (arrière-plan iOS).
    case stopped
    /// Démarrage en cours.
    case starting
    /// Rendu en cours sur la sortie décrite.
    case running(AudioOutputInfo)
    /// Aucune sortie, ou démarrage impossible : « Sortie audio indisponible ». L'hôte réessaie
    /// automatiquement ; l'interface reste utilisable (SF-82).
    case unavailable(reason: String)

    public var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    public var outputInfo: AudioOutputInfo? {
        if case let .running(info) = self { return info }
        return nil
    }
}
