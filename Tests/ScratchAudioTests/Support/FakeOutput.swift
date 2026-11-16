import Foundation
import ScratchCore
@testable import ScratchAudio

/// Double de la sortie matérielle (stories 2.1, 2.3) : succès ou échec scriptés, événements du système
/// simulés par `onSystemEvent`. Il note, à chaque démarrage, si l'horloge de secours tournait encore et
/// si le moteur A tournait (dernier instantané publié).
@MainActor
final class FakeOutput: AudioHardwareOutput {
    var onSystemEvent: ((AudioSystemEvent) -> Void)?
    var failure: Error?
    var info = AudioOutputInfo(name: "MPC Sample (USB)", sampleRate: 44_100, bufferFrames: 256, outputLatency: 0.004)
    /// Fréquence réelle simulée (`nil` : inconnue).
    var actualSampleRate: Double?
    var isUsedDeviceStillPresent = true
    var isFallbackRunning: (() -> Bool)?
    private(set) var isRunning = false
    private(set) var isMonitoring = false
    private(set) var fallbackRunningAtStart: [Bool] = []
    private(set) var motorOnAtStart: [Bool] = []
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var deactivateCount = 0
    private(set) var resetSessionCount = 0

    func startMonitoring() { isMonitoring = true }
    func stopMonitoring() { isMonitoring = false }

    func start(rendering engine: ScratchEngine) throws -> AudioOutputInfo {
        stop()
        startCount += 1
        fallbackRunningAtStart.append(isFallbackRunning?() ?? false)
        motorOnAtStart.append(engine.latestSnapshot()[.a].motorOn)
        if let failure { throw failure }
        engine.send(.outputSampleRate(info.sampleRate))
        isRunning = true
        return info
    }

    func stop() {
        stopCount += 1
        isRunning = false
    }

    func currentInfo() -> AudioOutputInfo? { isRunning ? info : nil }
    func resetSession() { resetSessionCount += 1 }
    func deactivate() { deactivateCount += 1 }

    /// Hôte branché sur un double neuf.
    static func makeHost(engine: ScratchEngine = ScratchEngine(), failing: Bool, platform: AudioPlatform = .macOS,
                         retryInterval: Double = AudioSystemPolicy.retryInterval) -> (AudioEngineHost, FakeOutput) {
        let output = FakeOutput()
        if failing { output.failure = AudioOutputError.noOutput }
        let host = AudioEngineHost(engine: engine, output: output, platform: platform, retryInterval: retryInterval)
        output.isFallbackRunning = { [unowned host] in host.isFallbackRunning }
        return (host, output)
    }
}
