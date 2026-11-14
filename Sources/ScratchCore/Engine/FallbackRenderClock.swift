import Dispatch

/// Horloge de secours du rendu (décision Q14 ; SF-82 ; architecture §3.3, ADR-13).
///
/// Quand aucune sortie audio ne tourne (périphérique absent, démarrage impossible), elle appelle
/// `ScratchEngine.render` au rythme du temps réel, dans un tampon jetable : la physique avance, les
/// disques et l'interface restent vivants, en silence. `AudioEngineHost` la démarre quand la sortie
/// est indisponible et l'arrête **avant** de démarrer l'`AVAudioEngine` : un seul fil de rendu à la
/// fois.
///
/// Le nombre de trames de chaque appel est calculé d'après le temps écoulé sur l'horloge monotone
/// (pas d'accumulation de dérive) et plafonné à `maximumFramesPerTick` (un retard, par exemple
/// après une mise en veille, est abandonné plutôt que rattrapé).
///
/// `start`, `stop` et `isRunning` : fil de contrôle (fil principal) uniquement.
public final class FallbackRenderClock: @unchecked Sendable {
    /// Moteur rendu par l'horloge.
    public let engine: ScratchEngine
    /// Fréquence simulée, en Hz : celle que l'hôte a envoyée au moteur (`outputSampleRate`).
    public let sampleRate: Double
    /// Période visée : 256 trames à 48 kHz ≈ 5,33 ms.
    public let framesPerTick: Int
    /// Plafond de trames par appel.
    public let maximumFramesPerTick: Int

    private let queue = DispatchQueue(label: "app.scratchapp.fallback-render-clock", qos: .userInteractive)
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>
    private var timer: DispatchSourceTimer?
    // Owned by `queue`.
    private var lastTick: UInt64 = 0
    private var fractionalFrames: Double = 0

    public init(engine: ScratchEngine, sampleRate: Double = 48_000,
                framesPerTick: Int = TurntableConstants.preferredBufferFrames) {
        self.engine = engine
        self.sampleRate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 48_000
        self.framesPerTick = max(1, framesPerTick)
        self.maximumFramesPerTick = max(1, framesPerTick) * 8
        left = .allocate(capacity: maximumFramesPerTick)
        left.initialize(repeating: 0, count: maximumFramesPerTick)
        right = .allocate(capacity: maximumFramesPerTick)
        right.initialize(repeating: 0, count: maximumFramesPerTick)
    }

    deinit {
        // No tick can be running here: a running tick holds a strong reference to `self`.
        timer?.cancel()
        left.deallocate()
        right.deallocate()
    }

    /// L'horloge rend le moteur.
    public var isRunning: Bool { timer != nil }

    /// Démarre l'horloge. Sans effet si elle tourne déjà.
    public func start() {
        guard timer == nil else { return }
        let period = Double(framesPerTick) / sampleRate
        let source = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        source.schedule(deadline: .now() + period,
                        repeating: .nanoseconds(Int(period * 1_000_000_000)),
                        leeway: .microseconds(500))
        queue.sync {
            lastTick = DispatchTime.now().uptimeNanoseconds
            fractionalFrames = 0
        }
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
    }

    /// Arrête l'horloge et attend la fin d'un rendu en cours : plus aucun appel à `render` après le retour.
    public func stop() {
        guard let source = timer else { return }
        timer = nil
        source.cancel()
        queue.sync {}
    }

    private func tick() {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = Double(now &- lastTick) / 1_000_000_000
        lastTick = now
        let wanted = elapsed * sampleRate + fractionalFrames
        let frames = min(maximumFramesPerTick, Int(wanted))
        fractionalFrames = frames == maximumFramesPerTick ? 0 : wanted - Double(frames)
        guard frames > 0 else { return }
        engine.render(frameCount: frames, left: left, right: right)
    }
}
