import Foundation
import Observation
import ScratchCore

/// Hôte AVAudioEngine du moteur de ScratchApp (SF-16, SF-18, SF-78, SF-81, SF-82 ; architecture
/// §3, §5.3, §7.3).
///
/// **Squelette (story EP2, James) : ne démarre aucune sortie (état `.unavailable`).** À implémenter :
/// - `AVAudioEngine` + `AVAudioSourceNode` au format Float32 stéréo désentrelacé à la fréquence
///   matérielle ; le bloc de rendu, créé une seule fois, extrait les deux pointeurs de
///   l'`AudioBufferList` et appelle `engine.render(frameCount:left:right:)`, rien d'autre ;
/// - tampon préféré de 256 trames (`AVAudioSession.setPreferredIOBufferDuration` sur iOS,
///   `kAudioDevicePropertyBufferFrameSize` sur macOS si nécessaire) ;
/// - `send(.outputSampleRate(_))` avant chaque démarrage ;
/// - `AVAudioEngineConfigurationChange` : arrêt, reconstruction, nouvelle fréquence, redémarrage ;
///   politique de STOP selon §7.3 (arbitrage IC-04) ;
/// - iOS : `AudioSessionController` (catégorie `.playback`, interruptions, routes) ;
/// - SF-82 : nouvelle tentative périodique tant que la sortie est indisponible ;
/// - nom de la sortie active pour l'affichage (3.2).
@MainActor
@Observable
public final class AudioEngineHost: AudioOutputHosting {
    public private(set) var status: AudioOutputStatus = .stopped
    public private(set) var isRenderingAudio = false

    /// Moteur rendu par l'hôte. Les commandes passent par `engine.send` depuis le fil principal.
    public let engine: ScratchEngine

    public init(engine: ScratchEngine) {
        self.engine = engine
    }

    public func start() {
        status = .unavailable(reason: "AudioEngineHost n'est pas encore implémenté")
    }

    public func stop() {
        isRenderingAudio = false
        status = .stopped
    }

    public func suspendForBackground() {
        engine.send(.stopAllMotors)
        stop()
    }

    public func resumeFromBackground() {
        start()
    }
}
