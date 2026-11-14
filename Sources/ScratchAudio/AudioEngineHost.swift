import AVFoundation
import Foundation
import Observation
import ScratchCore

/// Hôte AVAudioEngine du moteur de ScratchApp (SF-01, SF-16, SF-78, SF-81, SF-82 ; PRD 2.1 ;
/// architecture §3, §5.1, §7.3 ; ADR-02, ADR-13).
///
/// - **Sortie matérielle** : `ScratchAudioGraph` à la fréquence matérielle, un tampon préféré de 256
///   trames, et `send(.outputSampleRate(_))` avant chaque démarrage. L'état
///   `.running(AudioOutputInfo)` publie le nom de la sortie, la fréquence, le tampon effectif et la
///   latence annoncée.
/// - **Sortie indisponible** (SF-82, D-35) : `.unavailable(reason:)`, et l'horloge de secours fait
///   tourner le moteur en silence. Disques, plateaux et VU-mètres restent vivants.
/// - **Un seul fil de rendu** (§3.3) : l'horloge de secours est arrêtée, de façon synchrone, avant
///   chaque démarrage de la sortie, et relancée seulement si la sortie ne démarre pas.
/// - **Changement de configuration** (`AVAudioEngineConfigurationChange` : périphérique par défaut,
///   fréquence) : la sortie redémarre sur la nouvelle configuration, sans toucher aux moteurs. La
///   politique d'un périphérique disparu (STOP) et le nouvel essai périodique relèvent de la 2.3.
/// - **Aucune lecture** : l'hôte n'envoie jamais `motor(on: true)` ni `load` (SF-01, RM-10).
///
/// Fil principal uniquement. Les clips rendus par le moteur sont libérés par
/// `ScratchEngine.drainReleasedClips()`, que l'`AppModel` appelle à chaque image (jamais sur le fil
/// audio).
@MainActor
@Observable
public final class AudioEngineHost: AudioOutputHosting {
    public private(set) var status: AudioOutputStatus = .stopped
    public private(set) var isRenderingAudio = false

    /// Moteur rendu par l'hôte. Les commandes passent par `engine.send` depuis le fil principal.
    public let engine: ScratchEngine
    private let fallbackClock: FallbackRenderClock
    private let output: any AudioHardwareOutput
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isSuspended = false

    public convenience init(engine: ScratchEngine) {
        self.init(engine: engine, output: AVAudioEngineOutput())
    }

    /// Hôte dont la sortie matérielle est injectée (tests).
    init(engine: ScratchEngine, output: any AudioHardwareOutput) {
        self.engine = engine
        self.output = output
        self.fallbackClock = FallbackRenderClock(engine: engine, sampleRate: 48_000)
        output.onConfigurationChange = { [weak self] in self?.handleConfigurationChange() }
    }

    public func start() {
        guard !isSuspended, !isStarted else { return }
        isStarted = true
        startOutput()
    }

    public func stop() {
        output.stop()
        fallbackClock.stop()
        isRenderingAudio = false
        isStarted = false
        status = .stopped
    }

    /// Arrière-plan iOS (SF-81, RM-56) : tous les moteurs s'arrêtent, puis plus aucun rendu. Le STOP
    /// est appliqué tout de suite, sur le fil principal, une fois le rendu arrêté (D-54) : l'instantané
    /// le montre dès le retour, sans attendre une image ni la reprise.
    public func suspend() {
        engine.send(.stopAllMotors)
        isSuspended = true
        stop()
        output.deactivate()
        engine.pump()
    }

    /// Retour au premier plan : la sortie (ou l'horloge de secours) repart, jamais les moteurs (RM-10).
    public func resume() {
        isSuspended = false
        start()
    }

    /// Mesure de diagnostic de la latence geste→son (D-15, story 2.1 CA 11) à la fréquence et au
    /// tampon de la sortie courante (48 kHz et 256 trames sans sortie). La partie moteur est mesurée
    /// hors ligne par le graphe en rendu manuel ; la latence de sortie annoncée y est ajoutée.
    /// `total` est la mesure de référence de D-54 et D-56 : régime appris (second geste), moyenne sur
    /// 8 phases touches/affichage. Le pire cas (`worstTotal`) et le premier geste
    /// (`firstGestureTotal`) sont publiés à côté.
    public func measureGestureLatency(displayRate: Double = 120) throws -> GestureLatencyProbe.Measurement {
        let info = status.outputInfo
        return try GestureLatencyProbe.measure(sampleRate: info?.sampleRate ?? 48_000,
                                               bufferFrames: info?.bufferFrames ?? TurntableConstants.preferredBufferFrames,
                                               displayRate: displayRate,
                                               outputLatency: info?.outputLatency ?? 0)
    }

    // MARK: - Internals

    /// L'horloge de secours rend le moteur (diagnostic, tests).
    var isFallbackRunning: Bool { fallbackClock.isRunning }

    /// Démarre la sortie matérielle, sinon l'horloge de secours ; jamais les deux à la fois (§3.3).
    private func startOutput() {
        status = .starting
        fallbackClock.stop() // synchronous: no render on this clock after this line
        do {
            let info = try output.start(rendering: engine)
            isRenderingAudio = true
            status = .running(info)
        } catch {
            output.stop()
            engine.send(.outputSampleRate(fallbackClock.sampleRate))
            fallbackClock.start()
            isRenderingAudio = true
            status = .unavailable(reason: (error as? AudioOutputError)?.reason
                ?? "Le moteur audio n'a pas pu démarrer (\(error.localizedDescription)).")
        }
    }

    /// Nouvelle configuration de la sortie : arrêt, puis redémarrage sur la configuration courante.
    func handleConfigurationChange() {
        guard isStarted, !isSuspended else { return }
        output.stop()
        startOutput()
    }
}

// MARK: - Sortie matérielle

/// Sortie audio matérielle, injectable pour les tests (l'exécuteur de CI n'a pas de périphérique).
@MainActor
protocol AudioHardwareOutput: AnyObject {
    /// Appelé sur le fil principal quand la configuration de la sortie change.
    var onConfigurationChange: (() -> Void)? { get set }
    /// Démarre la sortie : envoie `outputSampleRate` au moteur, puis rend le moteur sur le fil audio
    /// du système. Lève une erreur si aucune sortie ne peut démarrer.
    func start(rendering engine: ScratchEngine) throws -> AudioOutputInfo
    /// Arrête la sortie (synchrone : plus aucun rendu après le retour).
    func stop()
    /// iOS : désactive la session audio (arrière-plan).
    func deactivate()
}

/// Sortie par `AVAudioEngine`, sur le périphérique par défaut (macOS) ou la route de la session
/// (iOS).
@MainActor
final class AVAudioEngineOutput: AudioHardwareOutput {
    var onConfigurationChange: (() -> Void)?
    private var graph: ScratchAudioGraph?
    private var observer: (any NSObjectProtocol)?
    #if os(iOS)
    private let session = AudioSessionController()
    #endif

    func start(rendering engine: ScratchEngine) throws -> AudioOutputInfo {
        stop()
        #if os(iOS)
        try session.activate()
        #endif
        let avEngine = AVAudioEngine()
        #if os(macOS)
        let device = OutputDevice.defaultOutput()
        device?.requestBufferFrameSize(UInt32(TurntableConstants.preferredBufferFrames))
        #endif
        let hardware = avEngine.outputNode.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0 else { throw AudioOutputError.noOutput }
        let sampleRate = hardware.sampleRate
        engine.send(.outputSampleRate(sampleRate))
        let graph = try ScratchAudioGraph(engine: engine, sampleRate: sampleRate, avEngine: avEngine)
        avEngine.prepare()
        try avEngine.start()
        self.graph = graph
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: avEngine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onConfigurationChange?() }
        }
        #if os(macOS)
        return AudioOutputInfo(name: device?.displayName ?? "Sortie audio", sampleRate: sampleRate,
                               bufferFrames: Int(device?.bufferFrameSize ?? UInt32(TurntableConstants.preferredBufferFrames)),
                               outputLatency: avEngine.outputNode.presentationLatency)
        #else
        return AudioOutputInfo(name: session.currentOutputName, sampleRate: sampleRate,
                               bufferFrames: session.bufferFrames, outputLatency: session.outputLatency)
        #endif
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        graph?.avEngine.stop()
        graph = nil
    }

    func deactivate() {
        #if os(iOS)
        session.deactivate()
        #endif
    }
}
