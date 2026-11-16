import AVFoundation
#if os(macOS)
import CoreAudio
#endif
import Foundation
import Observation
import ScratchCore

/// Hôte AVAudioEngine du moteur de ScratchApp (SF-01, SF-16, SF-18, SF-78, SF-81, SF-82 ; PRD 2.1,
/// 2.3 ; architecture §3, §5.1, §7.3 ; ADR-02, ADR-13 ; D-04, D-35).
///
/// - **Sortie matérielle** : `ScratchAudioGraph` à la fréquence matérielle, un tampon préféré de 128
///   trames, 256 en repli (`OutputBufferPolicy`, #91), et `send(.outputSampleRate(_))` avant chaque
///   démarrage. L'état `.running(AudioOutputInfo)` publie le nom de la sortie, la fréquence, le
///   tampon effectif et la latence annoncée ; il est republié à chaque changement de route ou de
///   périphérique (2.3 CA 7).
/// - **Sortie indisponible** (SF-82, D-35) : `.unavailable(reason:)`, et l'horloge de secours fait
///   tourner le moteur en silence. Disques, plateaux et VU-mètres restent vivants. Nouvel essai toutes
///   les 2 s et à chaque changement de route ou de configuration ; aucun moteur ne démarre.
/// - **Un seul fil de rendu** (§3.3) : l'horloge de secours est arrêtée, de façon synchrone, avant
///   chaque démarrage de la sortie, et relancée seulement si la sortie ne démarre pas.
/// - **Événements du système** (2.3) : interruptions, changements de route et réinitialisation des
///   services média (iOS), changements de périphérique et veille (macOS), changement de configuration
///   (les deux). `AudioSystemPolicy` décide des actions, que l'hôte exécute dans l'ordre : un choix
///   volontaire de sortie garde l'état des moteurs, une perte de sortie, une interruption ou la veille
///   les mettent à STOP.
/// - **Avis** (2.3 CA 8) : `notice` publie chaque transition qui demande un bandeau (UX §8.5).
/// - **Aucune lecture** : l'hôte n'envoie jamais `motor(on: true)` ni `load` (SF-01, RM-10).
///
/// Fil principal uniquement. Les clips rendus par le moteur sont libérés par
/// `ScratchEngine.drainReleasedClips()`, que l'`AppModel` appelle à chaque image (jamais sur le fil
/// audio).
@MainActor
@Observable
public final class AudioEngineHost: AudioOutputHosting, AudioNoticePosting {
    public private(set) var status: AudioOutputStatus = .stopped
    public private(set) var isRenderingAudio = false
    /// Dernier avis pour le bandeau (UX §8.5), lu par l'`AppModel` (story 6.2).
    public private(set) var notice: PostedAudioNotice?

    /// Moteur rendu par l'hôte. Les commandes passent par `engine.send` depuis le fil principal.
    public let engine: ScratchEngine
    private let fallbackClock: FallbackRenderClock
    private let output: any AudioHardwareOutput
    private let platform: AudioPlatform
    private let retryInterval: Double
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isSuspended = false
    /// La sortie matérielle tourne (rendu sur le fil audio du système).
    @ObservationIgnored private var isOutputRunning = false
    /// Le dernier démarrage a échoué : horloge de secours et nouvel essai (SF-82).
    @ObservationIgnored private var isOutputUnavailable = false
    /// iOS, entre `interruptionBegan` et `interruptionEnded` (#96).
    @ObservationIgnored private var isInterrupted = false
    @ObservationIgnored private var unavailableReason = AudioOutputError.noOutput.reason
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var noticeCount = 0

    public convenience init(engine: ScratchEngine) {
        self.init(engine: engine, output: AVAudioEngineOutput())
    }

    /// Hôte dont la sortie matérielle, la plateforme et l'intervalle du nouvel essai sont injectés
    /// (tests).
    init(engine: ScratchEngine, output: any AudioHardwareOutput, platform: AudioPlatform = .current,
         retryInterval: Double = AudioSystemPolicy.retryInterval) {
        self.engine = engine
        self.output = output
        self.platform = platform
        self.retryInterval = retryInterval
        self.fallbackClock = FallbackRenderClock(engine: engine, sampleRate: 48_000)
        output.onSystemEvent = { [weak self] event in self?.handle(event) }
    }

    public func start() {
        guard !isSuspended, !isStarted else { return }
        isStarted = true
        output.startMonitoring()
        startOutput()
        updateRetryTimer()
    }

    public func stop() {
        retryTask?.cancel()
        retryTask = nil
        output.stopMonitoring()
        output.stop()
        fallbackClock.stop()
        isOutputRunning = false
        isOutputUnavailable = false
        isInterrupted = false
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
    /// Une interruption dont la fin n'a pas été notifiée est close : la session est réactivée.
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
    public func measureGestureLatency(displayRate: Double = 120,
                                      phases: Int = GestureLatencyProbe.defaultPhaseCount) throws -> GestureLatencyProbe.Measurement {
        let info = status.outputInfo
        return try GestureLatencyProbe.measure(sampleRate: info?.sampleRate ?? 48_000,
                                               bufferFrames: info?.bufferFrames ?? TurntableConstants.preferredBufferFrames,
                                               displayRate: displayRate,
                                               outputLatency: info?.outputLatency ?? 0,
                                               phases: phases)
    }

    /// Rapport de latence de la recette (6.3 CA 3) sur la sortie courante : tampon demandé et
    /// effectif, latence annoncée, fréquence réelle et dérive (#129), et mesure à chaque cadence
    /// d'affichage. À appeler sortie démarrée : la fréquence réelle est lue après les mesures, quand le
    /// système a eu le temps de l'estimer.
    public func latencyReport(displayRates: [Double] = [120, 60],
                              phases: Int = GestureLatencyProbe.defaultPhaseCount) throws -> LatencyReport {
        let measurements = try displayRates.map { rate in
            (displayRate: rate, measurement: try measureGestureLatency(displayRate: rate, phases: phases))
        }
        return LatencyReport(status: status, requestedBufferFrames: OutputBufferPolicy.preferredFrames,
                             unavailableBufferFrames: TurntableConstants.preferredBufferFrames,
                             actualSampleRate: status.isRunning ? output.actualSampleRate : nil,
                             measurements: measurements)
    }

    // MARK: - Internals

    /// L'horloge de secours rend le moteur (diagnostic, tests).
    var isFallbackRunning: Bool { fallbackClock.isRunning }

    /// Le nouvel essai périodique est armé (tests).
    var isRetrying: Bool { retryTask != nil }

    /// Événement du système audio, reçu sur le fil principal (story 2.3) : actions de
    /// `AudioSystemPolicy`, exécutées dans l'ordre. Ignoré tant que l'hôte n'est pas démarré.
    func handle(_ event: AudioSystemEvent) {
        guard isStarted else { return }
        let actions = AudioSystemPolicy.actions(for: event, context: context)
        switch event {
        case .interruptionBegan: isInterrupted = true
        // iOS does not guarantee the end of an interruption: a media services reset also closes it.
        case .interruptionEnded, .mediaServicesReset: isInterrupted = false
        default: break
        }
        perform(actions)
        updateRetryTimer()
    }

    private var context: AudioHostContext {
        AudioHostContext(platform: platform, isOutputUnavailable: isOutputUnavailable, isSuspended: isSuspended,
                         usedDeviceStillPresent: output.isUsedDeviceStillPresent, isInterrupted: isInterrupted)
    }

    private func perform(_ actions: [AudioHostAction]) {
        for action in actions {
            switch action {
            case .stopAllMotors:
                engine.send(.stopAllMotors)
            case .applyPendingCommands:
                // The policy asks for it only when nothing renders; a rendering thread applies them anyway.
                if !isOutputRunning, !fallbackClock.isRunning { engine.pump() }
            case .stopOutput, .rebuildGraph:
                // The output builds a new graph, on the current system output, at each start.
                output.stop()
                if isOutputRunning { status = .stopped }
                isOutputRunning = false
            case .startFallbackClock:
                engine.send(.outputSampleRate(fallbackClock.sampleRate))
                fallbackClock.start()
                status = .unavailable(reason: isInterrupted ? Self.interruptedReason : unavailableReason)
            case .resetSession:
                output.resetSession()
            case .startOutput:
                startOutput()
            case .refreshOutputName:
                if status.isRunning, let info = output.currentInfo() { status = .running(info) }
            case let .notify(value):
                noticeCount += 1
                notice = PostedAudioNotice(id: noticeCount, notice: value)
            }
        }
        isRenderingAudio = isOutputRunning || fallbackClock.isRunning
    }

    /// Démarre la sortie matérielle, sinon l'horloge de secours ; jamais les deux à la fois (§3.3).
    private func startOutput() {
        let before = context
        status = .starting
        fallbackClock.stop() // synchronous: no render on this clock after this line
        do {
            let info = try output.start(rendering: engine)
            isOutputRunning = true
            isOutputUnavailable = false
            status = .running(info)
            perform(AudioSystemPolicy.actionsAfterStart(succeeded: true, outputName: info.name, context: before))
        } catch {
            output.stop()
            isOutputRunning = false
            isOutputUnavailable = true
            unavailableReason = (error as? AudioOutputError)?.reason
                ?? "Le moteur audio n'a pas pu démarrer (\(error.localizedDescription))."
            perform(AudioSystemPolicy.actionsAfterStart(succeeded: false, outputName: "", context: before))
        }
        isRenderingAudio = isOutputRunning || fallbackClock.isRunning
    }

    /// Nouvel essai toutes les `retryInterval` secondes tant que la sortie est indisponible, hors
    /// interruption et arrière-plan (SF-82, D-35).
    private func updateRetryTimer() {
        guard isStarted, isOutputUnavailable, !isSuspended, !isInterrupted else {
            retryTask?.cancel()
            retryTask = nil
            return
        }
        guard retryTask == nil else { return }
        let interval = UInt64(retryInterval * 1_000_000_000)
        retryTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled, let self else { return }
                self.perform(AudioSystemPolicy.actionsOnRetryTick(context: self.context))
                self.updateRetryTimer()
            }
        }
    }

    /// Motif de `.unavailable` pendant une interruption (diagnostic).
    static let interruptedReason = "Lecture interrompue par le système."
}

extension AudioPlatform {
    /// Plateforme de compilation.
    static var current: AudioPlatform {
        #if os(macOS)
        return .macOS
        #else
        return .iOS
        #endif
    }
}

// MARK: - Sortie matérielle

/// Sortie audio matérielle, injectable pour les tests (l'exécuteur de CI n'a pas de périphérique).
@MainActor
protocol AudioHardwareOutput: AnyObject {
    /// Appelé sur le fil principal pour chaque événement du système audio, entre `startMonitoring()`
    /// et `stopMonitoring()` (story 2.3).
    var onSystemEvent: ((AudioSystemEvent) -> Void)? { get set }
    /// macOS : le périphérique de la dernière sortie démarrée est toujours connecté (D-04). Vrai sur
    /// iOS, où la disparition passe par `routeChanged(previousDeviceUnavailable: true)`.
    var isUsedDeviceStillPresent: Bool { get }
    /// Commence à écouter le système (session iOS, périphériques et veille macOS).
    func startMonitoring()
    /// Cesse d'écouter le système.
    func stopMonitoring()
    /// Démarre la sortie : arrête l'éventuelle sortie précédente, construit un graphe neuf sur la
    /// sortie courante du système, envoie `outputSampleRate` au moteur, puis rend le moteur sur le fil
    /// audio du système. Lève une erreur si aucune sortie ne peut démarrer.
    func start(rendering engine: ScratchEngine) throws -> AudioOutputInfo
    /// Arrête la sortie et abandonne son graphe (synchrone : plus aucun rendu après le retour).
    func stop()
    /// Description à jour de la sortie qui tourne (nom de la route, tampon, latence), ou `nil`.
    func currentInfo() -> AudioOutputInfo?
    /// iOS : services média réinitialisés. Le graphe est abandonné ; la session est reconfigurée au
    /// démarrage suivant.
    func resetSession()
    /// iOS : désactive la session audio (arrière-plan).
    func deactivate()
    /// Fréquence réelle de la sortie en cours, mesurée par le système (macOS), ou `nil` si elle est
    /// inconnue (iOS, sortie arrêtée).
    var actualSampleRate: Double? { get }
}

/// Sortie par `AVAudioEngine`, sur le périphérique par défaut (macOS) ou la route de la session
/// (iOS). Les événements viennent de `AudioSessionController` (iOS) ou de `OutputDeviceMonitor`
/// (macOS), et de `AVAudioEngineConfigurationChange` sur le graphe en cours. Sur macOS, celle-ci passe
/// par le regroupement du moniteur : un changement de périphérique donne un seul
/// `configurationChanged`.
@MainActor
final class AVAudioEngineOutput: AudioHardwareOutput {
    var onSystemEvent: ((AudioSystemEvent) -> Void)?
    private var graph: ScratchAudioGraph?
    private var sampleRate: Double = 0
    private var observer: (any NSObjectProtocol)?
    /// Incrémenté à chaque démarrage et arrêt : une notification d'un graphe abandonné est ignorée.
    private var generation = 0
    #if os(iOS)
    private let session = AudioSessionController()
    #else
    let monitor = OutputDeviceMonitor()
    private var device: OutputDevice?
    #endif

    init() {
        #if os(iOS)
        session.onEvent = { [weak self] event in self?.onSystemEvent?(event) }
        #else
        monitor.onEvent = { [weak self] event in self?.onSystemEvent?(event) }
        #endif
    }

    var isUsedDeviceStillPresent: Bool {
        #if os(macOS)
        return monitor.isDeviceInUseStillPresent
        #else
        return true
        #endif
    }

    #if os(macOS)
    /// Périphérique de la dernière sortie démarrée, fixé à chaque démarrage (`nil` après un échec).
    var deviceInUse: AudioObjectID? { monitor.deviceInUse }
    #endif

    func startMonitoring() {
        #if os(iOS)
        session.startObserving()
        #else
        monitor.start()
        #endif
    }

    func stopMonitoring() {
        #if os(iOS)
        session.stopObserving()
        #else
        monitor.stop()
        #endif
    }

    var actualSampleRate: Double? {
        #if os(macOS)
        graph == nil ? nil : device?.actualSampleRate
        #else
        nil
        #endif
    }

    func start(rendering engine: ScratchEngine) throws -> AudioOutputInfo {
        stop()
        #if os(iOS)
        try session.activate()
        #endif
        let avEngine = AVAudioEngine()
        #if os(macOS)
        let device = OutputDevice.defaultOutput()
        self.device = device
        monitor.deviceInUse = nil
        if let device {
            // #91, D-54: 128 frames when the device grants them, 256 otherwise.
            OutputBufferPolicy.negotiate { frames in device.requestBufferFrameSize(UInt32(frames)).map(Int.init) }
        }
        #endif
        let hardware = avEngine.outputNode.outputFormat(forBus: 0)
        guard hardware.sampleRate > 0, hardware.channelCount > 0 else { throw AudioOutputError.noOutput }
        let sampleRate = hardware.sampleRate
        engine.send(.outputSampleRate(sampleRate))
        let graph = try ScratchAudioGraph(engine: engine, sampleRate: sampleRate, avEngine: avEngine)
        avEngine.prepare()
        try avEngine.start()
        self.graph = graph
        self.sampleRate = sampleRate
        #if os(macOS)
        monitor.deviceInUse = device?.id
        #endif
        let current = generation
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                          object: avEngine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == current, self.graph != nil else { return }
                self.engineConfigurationDidChange()
            }
        }
        return currentInfo() ?? AudioOutputInfo(name: "Sortie audio", sampleRate: sampleRate,
                                                bufferFrames: TurntableConstants.preferredBufferFrames,
                                                outputLatency: 0)
    }

    func stop() {
        generation += 1
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        graph?.avEngine.stop()
        graph = nil
    }

    func currentInfo() -> AudioOutputInfo? {
        guard let graph else { return nil }
        #if os(macOS)
        return AudioOutputInfo(name: device?.displayName ?? "Sortie audio", sampleRate: sampleRate,
                               bufferFrames: Int(device?.bufferFrameSize ?? UInt32(TurntableConstants.preferredBufferFrames)),
                               outputLatency: graph.avEngine.outputNode.presentationLatency)
        #else
        return AudioOutputInfo(name: session.currentOutputName, sampleRate: sampleRate,
                               bufferFrames: session.bufferFrames, outputLatency: session.outputLatency)
        #endif
    }

    func resetSession() {
        // The engine of the old media services is unusable; `start` reconfigures the session.
        stop()
    }

    func deactivate() {
        #if os(iOS)
        session.deactivate()
        #endif
    }

    /// `AVAudioEngineConfigurationChange` du graphe en cours (fréquence, périphérique par défaut).
    func engineConfigurationDidChange() {
        #if os(macOS)
        monitor.deviceConfigurationDidChange() // same coalescing window as the Core Audio notifications
        #else
        onSystemEvent?(.configurationChanged)
        #endif
    }
}
