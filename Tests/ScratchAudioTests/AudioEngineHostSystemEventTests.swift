import Foundation
import ScratchCore
import XCTest
@testable import ScratchAudio

/// Hôte audio face aux événements du système (story 2.3). La sortie matérielle est un double
/// (`FakeOutput`) dont les événements sont simulés pour iOS et macOS ; tant que le double « tourne »,
/// aucun fil ne rend, et le test applique les commandes avec `pump()`. Le comportement sur matériel est
/// recetté en 6.3.
@MainActor
final class AudioEngineHostSystemEventTests: XCTestCase {
    private func runMotorA(_ engine: ScratchEngine) {
        engine.send(.motor(.a, on: true))
        engine.pump()
        XCTAssertTrue(engine.latestSnapshot()[.a].motorOn)
    }

    private func waitUntil(timeout: Double = 3, _ condition: () -> Bool, file: StaticString = #filePath,
                           line: UInt = #line) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            guard Date() < deadline else { return XCTFail("condition not met within \(timeout) s", file: file, line: line) }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: - CA 1 (SF-18, RM-10, #96)

    /// CA 1 — scénario « Interruption avec un disque tenu » : STOP et horloge de secours au début, rien
    /// ne relance la sortie pendant l'appel, la sortie seule redémarre à la fin.
    func testInterruptionStopsMotorsAndNeverResumes_SF18_RM10() async throws {
        let engine = ScratchEngine()
        let (host, output) = FakeOutput.makeHost(engine: engine, failing: false, platform: .iOS, retryInterval: 0.05)
        host.start()
        XCTAssertTrue(output.isMonitoring)
        engine.send(.motor(.b, on: true))
        engine.send(.touchBegan(.b, angle: 0, time: 0))
        runMotorA(engine)

        output.onSystemEvent?(.interruptionBegan)
        XCTAssertFalse(output.isRunning, "the output stops")
        XCTAssertTrue(host.isFallbackRunning, "the fallback clock applies STOP and keeps the discs alive")
        XCTAssertTrue(host.isRenderingAudio)
        XCTAssertEqual(host.status, .unavailable(reason: AudioEngineHost.interruptedReason))
        XCTAssertEqual(host.notice?.notice, .interrupted)
        XCTAssertEqual(host.notice?.notice.message, "Lecture interrompue par le système. Appuyez sur START pour reprendre.")
        try await waitUntil { !engine.latestSnapshot()[.a].motorOn }
        XCTAssertFalse(engine.latestSnapshot()[.b].motorOn, "STOP even while the disc is held")

        // #96: nothing restarts the output before the end of the interruption.
        output.onSystemEvent?(.configurationChanged)
        output.onSystemEvent?(.routeChanged(previousDeviceUnavailable: false))
        output.onSystemEvent?(.systemDidWake)
        try await Task.sleep(nanoseconds: 200_000_000) // four retry intervals
        XCTAssertEqual(output.startCount, 1)
        XCTAssertFalse(host.isRetrying)
        XCTAssertTrue(host.isFallbackRunning)

        output.onSystemEvent?(.interruptionEnded)
        XCTAssertEqual(output.startCount, 2)
        XCTAssertEqual(output.fallbackRunningAtStart, [false, false], "the clock stops before the output starts")
        XCTAssertFalse(host.isFallbackRunning)
        XCTAssertEqual(host.status, .running(output.info))
        engine.pump()
        XCTAssertFalse(engine.latestSnapshot()[.a].motorOn, "the end of an interruption never restarts a motor (RM-10)")
        XCTAssertFalse(engine.latestSnapshot()[.b].motorOn)
        XCTAssertEqual(host.notice?.id, 1, "no banner at the end of the interruption")
        host.stop()
        XCTAssertFalse(output.isMonitoring)
    }

    /// CA 1 — gate de la partie 2 (Quinn, D-55) : iOS ne garantit pas la fin d'une interruption. Une
    /// réinitialisation des services média la clôt (session et graphe reconstruits, sortie relancée,
    /// moteurs à STOP), et le retour au premier plan aussi.
    func testInterruptionEndsOnMediaServicesResetOrForeground() {
        let engine = ScratchEngine()
        let (host, output) = FakeOutput.makeHost(engine: engine, failing: false, platform: .iOS, retryInterval: 0.05)
        host.start()
        runMotorA(engine)

        output.onSystemEvent?(.interruptionBegan)
        XCTAssertTrue(host.isFallbackRunning)
        output.onSystemEvent?(.mediaServicesReset)
        XCTAssertEqual(output.resetSessionCount, 1)
        XCTAssertEqual(output.startCount, 2)
        XCTAssertEqual(output.fallbackRunningAtStart, [false, false], "the clock stops before the output starts")
        XCTAssertFalse(host.isFallbackRunning)
        XCTAssertEqual(host.status, .running(output.info))
        output.onSystemEvent?(.configurationChanged)
        XCTAssertEqual(output.startCount, 3, "no longer interrupted: a configuration change restarts the output")
        engine.pump()
        XCTAssertFalse(engine.latestSnapshot()[.a].motorOn)

        // An interruption whose end never comes, then background and foreground.
        output.onSystemEvent?(.interruptionBegan)
        XCTAssertTrue(host.isFallbackRunning)
        host.suspend()
        host.resume()
        XCTAssertEqual(host.status, .running(output.info))
        XCTAssertFalse(host.isFallbackRunning)
        output.onSystemEvent?(.configurationChanged)
        XCTAssertEqual(output.startCount, 5, "the foreground closes the interruption")
        host.stop()
    }

    // MARK: - CA 2, 3 (D-04, RM-56)

    /// CA 2 — 6.5 « Débrancher le casque » : STOP est appliqué avant que la sortie ne reparte sur le
    /// haut-parleur, et le bandeau « Sortie audio déconnectée » est publié.
    func testHeadphonesUnpluggedStopsBeforeSpeaker_D04() {
        let engine = ScratchEngine()
        let (host, output) = FakeOutput.makeHost(engine: engine, failing: false, platform: .iOS)
        output.info.name = "Casque"
        host.start()
        runMotorA(engine)

        output.info.name = "Haut-parleur"
        output.onSystemEvent?(.routeChanged(previousDeviceUnavailable: true))
        XCTAssertEqual(output.motorOnAtStart, [false, false], "motors are stopped before the speaker renders")
        XCTAssertEqual(host.status, .running(output.info))
        XCTAssertEqual(host.notice?.notice, .outputDisconnected)
        XCTAssertEqual(host.notice?.notice.message, "Sortie audio déconnectée : les platines sont arrêtées.")
        XCTAssertFalse(host.isFallbackRunning)
        host.stop()
    }

    /// CA 3 — 6.5 « Perdre le périphérique audio » (macOS) : l'interface utilisée a disparu, la sortie
    /// suit le nouveau périphérique par défaut, les moteurs sont à STOP avant qu'elle ne rende.
    func testUsedDeviceGoneStopsMotors_RM56_D04() {
        let engine = ScratchEngine()
        let (host, output) = FakeOutput.makeHost(engine: engine, failing: false, platform: .macOS)
        host.start()
        runMotorA(engine)

        output.isUsedDeviceStillPresent = false
        output.info = AudioOutputInfo(name: "Haut-parleurs MacBook Pro", sampleRate: 48_000, bufferFrames: 256,
                                      outputLatency: 0.01)
        output.onSystemEvent?(.configurationChanged)
        XCTAssertEqual(output.motorOnAtStart.last, false)
        XCTAssertEqual(host.status, .running(output.info), "the new output is published (CA 7)")
        XCTAssertEqual(host.notice?.notice, .outputDisconnected)
        engine.pump()
        XCTAssertEqual(engine.latestSnapshot().outputSampleRate, 48_000)
        XCTAssertFalse(engine.latestSnapshot()[.a].motorOn, "manual restart only")
        host.stop()
    }

    /// CA 3 — iOS : réinitialisation des services média, reconstruction complète et moteurs à STOP.
    func testMediaServicesResetRebuildsAndStops() {
        let engine = ScratchEngine()
        let (host, output) = FakeOutput.makeHost(engine: engine, failing: false, platform: .iOS)
        host.start()
        runMotorA(engine)

        output.onSystemEvent?(.mediaServicesReset)
        XCTAssertEqual(output.resetSessionCount, 1)
        XCTAssertEqual(output.startCount, 2)
        XCTAssertEqual(output.motorOnAtStart.last, false)
        XCTAssertEqual(host.status, .running(output.info))
        host.stop()
    }

    // MARK: - CA 4, 7 (SF-16, D-04)

    /// CA 4 — 6.5 « Changer de périphérique de sortie sur Mac » : l'ancien périphérique reste connecté,
    /// la sortie redémarre sur le nouveau, à sa fréquence ; moteurs, hauteur et positions inchangés.
    func testVoluntaryOutputChangeKeepsMotors_SF16_D04() {
        let engine = ScratchEngine()
        let (host, output) = FakeOutput.makeHost(engine: engine, failing: false, platform: .macOS)
        host.start()
        engine.send(.pitch(.a, 0.04))
        runMotorA(engine)
        let before = engine.latestSnapshot()[.a]

        output.info = AudioOutputInfo(name: "LG TV (HDMI)", sampleRate: 48_000, bufferFrames: 512, outputLatency: 0.02)
        output.onSystemEvent?(.configurationChanged)
        XCTAssertEqual(output.startCount, 2)
        XCTAssertEqual(output.motorOnAtStart.last, true, "a deliberate change keeps the motors running")
        XCTAssertEqual(host.status, .running(output.info))
        XCTAssertNil(host.notice, "no banner for a deliberate change")
        engine.pump()
        let after = engine.latestSnapshot()
        XCTAssertEqual(after.outputSampleRate, 48_000, "outputSampleRate is updated")
        XCTAssertTrue(after[.a].motorOn)
        XCTAssertEqual(after[.a].positionSeconds, before.positionSeconds)
        XCTAssertEqual(after[.a].pitch, before.pitch)
        host.stop()
    }

    /// CA 4, CA 7 — iOS : un changement de route autre qu'une disparition (casque branché) publie le
    /// nouveau nom, sans redémarrage ni changement des moteurs.
    func testOutputNameUpdatesOnRouteChange_CA7() {
        let engine = ScratchEngine()
        let (host, output) = FakeOutput.makeHost(engine: engine, failing: false, platform: .iOS)
        output.info.name = "Haut-parleur"
        host.start()
        runMotorA(engine)

        output.info.name = "Casque"
        output.onSystemEvent?(.routeChanged(previousDeviceUnavailable: false))
        XCTAssertEqual(host.status.outputInfo?.name, "Casque")
        XCTAssertEqual(output.startCount, 1, "the output follows the route without restarting")
        engine.pump()
        XCTAssertTrue(engine.latestSnapshot()[.a].motorOn)
        XCTAssertNil(host.notice)
        host.stop()
    }

    // MARK: - CA 5 (0.3, RM-56)

    /// CA 5 — 6.5 « Mettre le Mac en veille » : STOP appliqué avant la veille, plus aucun rendu ; au
    /// réveil, la sortie repart, jamais les moteurs.
    func testSleepStopsMotorsWakeDoesNotResume_6_5() {
        let engine = ScratchEngine()
        let (host, output) = FakeOutput.makeHost(engine: engine, failing: false, platform: .macOS)
        host.start()
        runMotorA(engine)

        output.onSystemEvent?(.systemWillSleep)
        XCTAssertFalse(output.isRunning)
        XCTAssertFalse(host.isFallbackRunning)
        XCTAssertFalse(host.isRenderingAudio, "nothing renders while asleep")
        XCTAssertEqual(host.status, .stopped)
        XCTAssertFalse(engine.latestSnapshot()[.a].motorOn, "STOP is applied before sleeping")

        output.onSystemEvent?(.systemDidWake)
        XCTAssertEqual(host.status, .running(output.info))
        XCTAssertTrue(host.isRenderingAudio)
        engine.pump()
        XCTAssertFalse(engine.latestSnapshot()[.a].motorOn, "waking never restarts a motor (RM-10)")
        host.stop()
    }

    // MARK: - CA 6, 8 (SF-82, D-35, UX §8.5)

    /// CA 6 — 6.5 « Aucune sortie audio disponible » : nouvel essai périodique (2 s ; ici 50 ms) et à
    /// chaque changement de route, un seul bandeau tant que la sortie manque, aucun essai en arrière-plan ;
    /// à la réussite, horloge arrêtée, sortie démarrée, bandeau « Sortie audio disponible », plus d'essai.
    /// Aucun moteur ne démarre.
    func testUnavailableRetriesEvery2sWithoutStartingMotors_SF82() async throws {
        XCTAssertEqual(AudioSystemPolicy.retryInterval, 2)
        let engine = ScratchEngine()
        let (host, output) = FakeOutput.makeHost(engine: engine, failing: true, retryInterval: 0.05)
        host.start()
        XCTAssertTrue(host.isRetrying)
        XCTAssertEqual(host.notice, PostedAudioNotice(id: 1, notice: .outputUnavailable))
        XCTAssertEqual(host.notice?.notice.message, "Sortie audio indisponible. ScratchApp réessaiera automatiquement.")

        try await waitUntil { output.startCount >= 4 }
        XCTAssertEqual(host.notice?.id, 1, "a single banner while the output stays unavailable")
        XCTAssertTrue(host.isFallbackRunning)
        XCTAssertFalse(output.fallbackRunningAtStart.contains(true), "never two render threads")

        let beforeRouteChange = output.startCount
        output.onSystemEvent?(.routeChanged(previousDeviceUnavailable: false))
        XCTAssertGreaterThanOrEqual(output.startCount, beforeRouteChange + 1, "a route change retries at once")

        host.suspend()
        XCTAssertFalse(host.isRetrying)
        XCTAssertFalse(output.isMonitoring)
        let suspendedCount = output.startCount
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(output.startCount, suspendedCount, "no retry in the background")

        host.resume()
        XCTAssertTrue(output.isMonitoring)
        XCTAssertTrue(host.isRetrying)
        output.failure = nil
        try await waitUntil { host.status.isRunning }
        XCTAssertFalse(host.isRetrying)
        XCTAssertFalse(host.isFallbackRunning)
        XCTAssertEqual(host.notice?.notice, .outputAvailable(name: "MPC Sample (USB)"))
        XCTAssertEqual(host.notice?.notice.message, "Sortie audio disponible : MPC Sample (USB).")
        let runningCount = output.startCount
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(output.startCount, runningCount, "the retry stops once the output runs")

        engine.pump()
        for deck in DeckID.allCases {
            XCTAssertFalse(engine.latestSnapshot()[deck].motorOn, "no motor starts (SF-82, RM-10)")
        }
        host.stop()
    }

    // MARK: - T2 (iOS)

    /// T2 — traduction des notifications `AVAudioSession` (valeurs brutes du SDK).
    func testSessionNotificationMapping_T2() {
        XCTAssertEqual(AudioSessionEvents.event(interruptionType: 1), .interruptionBegan)
        XCTAssertEqual(AudioSessionEvents.event(interruptionType: 0), .interruptionEnded)
        XCTAssertNil(AudioSessionEvents.event(interruptionType: nil))
        XCTAssertNil(AudioSessionEvents.event(interruptionType: 9))
        XCTAssertEqual(AudioSessionEvents.event(routeChangeReason: 2), .routeChanged(previousDeviceUnavailable: true))
        XCTAssertNil(AudioSessionEvents.event(routeChangeReason: 3), "category changes come from the host itself")
        for reason: UInt in [0, 1, 4, 5, 6, 7, 8] {
            XCTAssertEqual(AudioSessionEvents.event(routeChangeReason: reason),
                           .routeChanged(previousDeviceUnavailable: false), "reason \(reason)")
        }
        XCTAssertEqual(AudioSessionEvents.event(routeChangeReason: nil), .routeChanged(previousDeviceUnavailable: false))
    }

    /// #121 — un début d'interruption « app suspendue » (motif `appWasSuspended` ou `wasSuspended`), envoyé
    /// avec retard et sans fin, est ignoré ; un vrai début d'interruption ne l'est pas.
    func testAppWasSuspendedInterruptionIsIgnored_121() {
        XCTAssertNil(AudioSessionEvents.event(interruptionType: 1, reason: 1), "reason appWasSuspended (iOS 14.5+)")
        XCTAssertNil(AudioSessionEvents.event(interruptionType: 1, wasSuspended: true), "wasSuspended key (before iOS 14.5)")
        XCTAssertNil(AudioSessionEvents.event(interruptionType: 1, reason: 0, wasSuspended: true))
        XCTAssertEqual(AudioSessionEvents.event(interruptionType: 1, reason: 0, wasSuspended: false), .interruptionBegan,
                       "a real interruption (call, alarm)")
        XCTAssertEqual(AudioSessionEvents.event(interruptionType: 1, reason: 2), .interruptionBegan, "built-in mic muted")
        XCTAssertEqual(AudioSessionEvents.event(interruptionType: 1), .interruptionBegan, "no reason")
        XCTAssertEqual(AudioSessionEvents.event(interruptionType: 0, reason: 1), .interruptionEnded)
        XCTAssertEqual(AudioSessionEvents.appWasSuspended, 1)
        XCTAssertEqual(AudioSessionEvents.wasSuspendedKey, "AVAudioSessionInterruptionWasSuspendedKey")
    }

    // MARK: - T3 (macOS, sortie réelle)

    #if os(macOS)
    /// T3 — gate de #88 : un changement de périphérique produit des notifications Core Audio et
    /// `AVAudioEngineConfigurationChange` ; les deux passent par la même fenêtre de regroupement et ne
    /// donnent qu'un `configurationChanged`.
    func testEngineConfigurationChangeSharesTheMonitorWindow() async throws {
        let output = AVAudioEngineOutput()
        var events: [AudioSystemEvent] = []
        output.onSystemEvent = { events.append($0) }
        output.monitor.deviceConfigurationDidChange()
        output.engineConfigurationDidChange()
        output.monitor.deviceConfigurationDidChange()
        try await waitUntil { !events.isEmpty }
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(events, [.configurationChanged])
    }

    /// T3 — gate de #88 : la sortie réelle fixe le périphérique utilisé à chaque démarrage (celui que
    /// voit aussi le moniteur), et l'oublie après un échec. Sans périphérique (CI), le démarrage échoue.
    func testRealOutputTracksTheDeviceInUse() {
        let output = AVAudioEngineOutput()
        let engine = ScratchEngine()
        do {
            let info = try output.start(rendering: engine)
            XCTAssertNotNil(output.deviceInUse)
            XCTAssertEqual(output.deviceInUse, OutputDeviceMonitor.currentDefaultOutputDevice())
            XCTAssertTrue(output.isUsedDeviceStillPresent)
            XCTAssertEqual(output.currentInfo()?.name, info.name)
            output.stop()
            XCTAssertNil(output.currentInfo())
        } catch {
            XCTAssertNil(output.deviceInUse, "no device in use after a failed start")
            XCTAssertTrue(output.isUsedDeviceStillPresent)
            XCTAssertNil(output.currentInfo())
        }
    }
    #endif
}
