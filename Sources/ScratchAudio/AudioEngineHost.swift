import Foundation
import Observation
import ScratchCore

/// Hôte AVAudioEngine du moteur de ScratchApp (SF-16, SF-18, SF-78, SF-81, SF-82 ; PRD 2.1, 2.3 ;
/// architecture §3, §5.1, §7.3).
///
/// **Squelette (stories 2.1 et 2.3, James).** Aucune sortie matérielle n'est encore ouverte :
/// `start()` publie `.unavailable` et fait tourner le moteur sur l'horloge de secours
/// (`FallbackRenderClock`), en silence. À implémenter :
/// - `AVAudioEngine` + `AVAudioSourceNode` au format Float32 stéréo désentrelacé à la fréquence
///   matérielle ; le bloc de rendu, créé une seule fois, extrait les deux pointeurs de
///   l'`AudioBufferList` et appelle `engine.render(frameCount:left:right:)`, rien d'autre ;
/// - tampon préféré de 256 trames ; tampon effectif, fréquence, latence et nom de la sortie publiés ;
/// - `send(.outputSampleRate(_))` avant chaque démarrage ; **un seul fil de rendu** : arrêter
///   l'horloge de secours avant `AVAudioEngine.start()`, la relancer après `stop()` si la sortie
///   reste indisponible ;
/// - `AVAudioEngineConfigurationChange`, veille, session iOS (`AudioSessionController`) : politique
///   de §7.3 (arbitrage IC-04) ; nouvel essai périodique tant que la sortie est indisponible.
@MainActor
@Observable
public final class AudioEngineHost: AudioOutputHosting {
    public private(set) var status: AudioOutputStatus = .stopped
    public private(set) var isRenderingAudio = false

    /// Moteur rendu par l'hôte. Les commandes passent par `engine.send` depuis le fil principal.
    public let engine: ScratchEngine
    private let fallbackClock: FallbackRenderClock
    private var isSuspended = false

    public init(engine: ScratchEngine) {
        self.engine = engine
        self.fallbackClock = FallbackRenderClock(engine: engine, sampleRate: 48_000)
    }

    public func start() {
        guard !isSuspended else { return }
        engine.send(.outputSampleRate(fallbackClock.sampleRate))
        isRenderingAudio = true
        fallbackClock.start()
        status = .unavailable(reason: "AudioEngineHost n'ouvre pas encore de sortie matérielle (story 2.1)")
    }

    public func stop() {
        fallbackClock.stop()
        isRenderingAudio = false
        status = .stopped
    }

    public func suspend() {
        engine.send(.stopAllMotors)
        isSuspended = true
        stop()
    }

    public func resume() {
        isSuspended = false
        start()
    }
}
