import AVFoundation
import Foundation
import ScratchCore
import XCTest
@testable import ScratchAudio

/// Hôte audio (story 2.1). L'exécuteur de CI n'a pas de périphérique audio : la sortie matérielle
/// est remplacée par un double, et le graphe est vérifié en rendu manuel hors ligne.
@MainActor
final class AudioEngineHostTests: XCTestCase {
    private func makeHost(engine: ScratchEngine = ScratchEngine(), failing: Bool) -> (AudioEngineHost, FakeOutput) {
        FakeOutput.makeHost(engine: engine, failing: failing)
    }

    private static func sine(frequency: Double, seconds: Double, sampleRate: Double = 48_000) -> AudioClip {
        AudioClip(title: "sine", sampleRate: sampleRate, frameCount: Int(seconds * sampleRate)) { left, right in
            for index in 0 ..< left.count {
                let value = Float(0.8 * sin(2 * Double.pi * frequency * Double(index) / sampleRate))
                left[index] = value
                right[index] = value
            }
        }
    }

    // MARK: - CA 6, 8 (SF-82, SF-81, RM-56, RM-10)

    /// CA 6 — SF-82, D-35, scénario « Aucune sortie » : `.unavailable`, l'horloge de secours fait
    /// tourner le moteur en temps réel, et les commandes s'appliquent sans `pump()`. CA 8 :
    /// `suspend()` arrête les moteurs et tout rendu ; `resume()` ne relance aucun moteur.
    func testUnavailableOutputKeepsTheEngineRunningOnTheFallbackClock_SF82() async throws {
        let engine = ScratchEngine()
        let (host, output) = makeHost(engine: engine, failing: true)
        host.start()
        XCTAssertTrue(host.isRenderingAudio)
        XCTAssertTrue(host.isFallbackRunning)
        XCTAssertEqual(host.status, .unavailable(reason: "Aucune sortie audio disponible."))
        engine.send(.motor(.a, on: true))
        try await Task.sleep(nanoseconds: 200_000_000)
        let snapshot = engine.latestSnapshot()
        XCTAssertGreaterThan(snapshot.sampleTime, 0, "the fallback clock renders")
        XCTAssertEqual(snapshot.outputSampleRate, 48_000)
        XCTAssertTrue(snapshot[.a].motorOn, "commands are applied without pump()")

        host.suspend()
        XCTAssertFalse(host.isRenderingAudio)
        XCTAssertFalse(host.isFallbackRunning)
        XCTAssertEqual(output.deactivateCount, 1)
        XCTAssertFalse(engine.latestSnapshot()[.a].motorOn, "suspend() stops every motor at once (RM-56, D-54)")
        let frozen = engine.latestSnapshot().sampleTime
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(engine.latestSnapshot().sampleTime, frozen, "no render while suspended")
        host.start()
        XCTAssertFalse(host.isRenderingAudio, "start() is ignored while suspended")

        host.resume()
        XCTAssertTrue(host.isRenderingAudio)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(engine.latestSnapshot()[.a].motorOn, "resume() never restarts a motor (RM-10)")
        host.stop()
        XCTAssertEqual(host.status, .stopped)
        XCTAssertFalse(host.isFallbackRunning)
    }

    /// CA 2, CA 5 — SF-01, RM-10 : une sortie qui démarre publie son nom, sa fréquence, son tampon
    /// et sa latence. Le moteur reçoit la fréquence matérielle, et ni moteur ni son n'est lancé.
    func testStartNeverStartsMotors_RM10() {
        let engine = ScratchEngine()
        let (host, output) = makeHost(engine: engine, failing: false)
        host.start()
        XCTAssertEqual(host.status, .running(output.info))
        XCTAssertTrue(host.isRenderingAudio)
        XCTAssertFalse(host.isFallbackRunning)
        engine.pump() // the fake output renders nothing: apply the commands sent by the host
        let snapshot = engine.latestSnapshot()
        XCTAssertEqual(snapshot.outputSampleRate, 44_100, "outputSampleRate is sent before starting")
        for deck in DeckID.allCases {
            XCTAssertFalse(snapshot[deck].motorOn)
            XCTAssertFalse(snapshot[deck].isLoaded)
        }
        host.start()
        XCTAssertEqual(output.fallbackRunningAtStart.count, 1, "start() is idempotent")
    }

    /// CA 9 — architecture §3.3 : l'horloge de secours est arrêtée avant chaque démarrage de la
    /// sortie, et relancée seulement si la sortie ne démarre pas. Il n'y a jamais deux fils de rendu.
    func testSingleRenderThreadDuringSwitch() {
        let (host, output) = makeHost(failing: true)
        host.start()
        XCTAssertTrue(host.isFallbackRunning)

        output.failure = nil
        output.onSystemEvent?(.configurationChanged) // e.g. a device appears or the default output changes
        XCTAssertEqual(output.fallbackRunningAtStart, [false, false], "the clock stops before the output starts")
        XCTAssertFalse(host.isFallbackRunning)
        XCTAssertTrue(host.status.isRunning)

        output.failure = AudioOutputError.noOutput
        output.onSystemEvent?(.configurationChanged)
        XCTAssertTrue(host.isFallbackRunning, "the clock takes over when the output cannot restart")
        XCTAssertTrue(host.isRenderingAudio)
        if case .unavailable = host.status {} else { XCTFail("expected .unavailable, got \(host.status)") }

        host.stop()
        XCTAssertFalse(host.isFallbackRunning)
        output.onSystemEvent?(.configurationChanged)
        XCTAssertEqual(output.fallbackRunningAtStart.count, 3, "no restart once stopped")
    }

    /// CA 1, 6 : la vraie sortie démarre sur le périphérique par défaut ou, sans périphérique (CI),
    /// bascule proprement sur l'horloge de secours. Dans les deux cas, le moteur est rendu.
    func testRealOutputStartsOrFallsBack_SF82() async throws {
        let engine = ScratchEngine()
        let host = AudioEngineHost(engine: engine)
        host.start()
        XCTAssertTrue(host.isRenderingAudio)
        switch host.status {
        case let .running(info):
            XCTAssertGreaterThan(info.sampleRate, 0)
            XCTAssertGreaterThan(info.bufferFrames, 0)
            XCTAssertFalse(info.name.isEmpty)
        case .unavailable:
            XCTAssertTrue(host.isFallbackRunning)
        default:
            XCTFail("unexpected status \(host.status)")
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertGreaterThan(engine.latestSnapshot().sampleTime, 0)
        host.stop()
        XCTAssertFalse(host.isRenderingAudio)
    }

    // MARK: - CA 7

    /// CA 7 — UX §5.17 : libellés de la sortie.
    func testOutputNameMapping() {
        XCTAssertEqual(OutputNaming.displayName(kind: .builtInSpeaker, systemName: "Speaker"), "Haut-parleur")
        XCTAssertEqual(OutputNaming.displayName(kind: .headphones, systemName: "Headphones"), "Casque")
        XCTAssertEqual(OutputNaming.displayName(kind: .bluetooth, systemName: "AirPods Pro"), "AirPods Pro")
        XCTAssertEqual(OutputNaming.displayName(kind: .usb, systemName: "MPC Sample"), "MPC Sample (USB)")
        XCTAssertEqual(OutputNaming.displayName(kind: .usb, systemName: "MPC Sample (USB)"), "MPC Sample (USB)")
        XCTAssertEqual(OutputNaming.displayName(kind: .hdmi, systemName: "LG TV"), "LG TV (HDMI)")
        XCTAssertEqual(OutputNaming.displayName(kind: .airPlay, systemName: "Salon"), "Salon (AirPlay)")
        XCTAssertEqual(OutputNaming.displayName(kind: .other, systemName: "Haut-parleurs MacBook Pro"),
                       "Haut-parleurs MacBook Pro")
        XCTAssertEqual(OutputNaming.displayName(kind: .other, systemName: "  "), "Sortie audio")
        #if os(macOS)
        XCTAssertEqual(OutputNaming.kind(forTransportType: kAudioDeviceTransportTypeUSB), .usb)
        XCTAssertEqual(OutputNaming.kind(forTransportType: kAudioDeviceTransportTypeBuiltIn), .other)
        XCTAssertEqual(OutputNaming.kind(forTransportType: kAudioDeviceTransportTypeHDMI), .hdmi)
        XCTAssertEqual(OutputNaming.kind(forTransportType: kAudioDeviceTransportTypeBluetooth), .bluetooth)
        #endif
    }

    // MARK: - CA 1, 10, 11

    /// CA 1, CA 10 — scénario « Rendu manuel identique au rendu direct » (base de 2.4) : le graphe
    /// AVAudioEngine en rendu manuel, à 48 kHz et par tranches de 256 trames, rejoue `ScratchScenario`
    /// et produit la même sortie que le rendu direct du moteur, à l'échantillon près.
    func testManualRenderMatchesDirectRender_SampleExact() throws {
        let clipA = Self.sine(frequency: 440, seconds: 10)
        let clipB = Self.sine(frequency: 220, seconds: 10)
        let scenario = ScratchScenario(clipA: clipA, clipB: clipB, sampleRate: 48_000, blockFrames: 256)
        let direct = scenario.run(on: ScratchEngine())

        let engine = ScratchEngine()
        let graph = try ScratchAudioGraph.offline(engine: engine, sampleRate: 48_000, maximumFrameCount: 512)
        try graph.avEngine.start()
        defer { graph.avEngine.stop() }
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: graph.avEngine.manualRenderingFormat, frameCapacity: 256))
        var left: [Float] = [], right: [Float] = []
        left.reserveCapacity(Int(scenario.totalFrames))
        right.reserveCapacity(Int(scenario.totalFrames))
        var frame: Int64 = 0
        while frame < scenario.totalFrames {
            for command in scenario.events(forBlockStartingAt: frame) { engine.send(command) }
            let count = Int(min(256, scenario.totalFrames - frame))
            let status = try graph.avEngine.renderOffline(AVAudioFrameCount(count), to: buffer)
            XCTAssertEqual(status, .success)
            let channels = try XCTUnwrap(buffer.floatChannelData)
            XCTAssertEqual(Int(buffer.frameLength), count)
            left.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: count))
            right.append(contentsOf: UnsafeBufferPointer(start: channels[1], count: count))
            engine.drainReleasedClips()
            frame += Int64(count)
        }

        XCTAssertEqual(left.count, direct.left.count)
        let count = min(left.count, direct.left.count)
        let firstLeft = (0 ..< count).first { left[$0].bitPattern != direct.left[$0].bitPattern }
        let firstRight = (0 ..< count).first { right[$0].bitPattern != direct.right[$0].bitPattern }
        XCTAssertNil(firstLeft, "left differs from frame \(firstLeft ?? -1)")
        XCTAssertNil(firstRight, "right differs from frame \(firstRight ?? -1)")
        XCTAssertGreaterThan(left.reduce(Float(0)) { max($0, abs($1)) }, 0.1, "the scenario is audible")
    }

    /// CA 11 — D-15, D-54, D-56, #92, #114 : la sonde publie le premier geste et le régime appris
    /// (second geste, après un geste d'échauffement), avec la réponse au premier échantillon qui
    /// franchit le seuil et la latence de sortie annoncée, sur 8 phases touches/affichage réparties sur
    /// une image. La référence est la moyenne (D-56) ; le maximum est publié. Le graphe en rendu
    /// manuel et le rendu direct donnent les mêmes valeurs. Le régime appris suit la cadence
    /// d'affichage : plus lent à 60 Hz qu'à 120 Hz.
    /// Valeurs de référence sous Linux, en rendu direct, à 48 kHz et 256 trames, sans la latence du
    /// périphérique (partie moteur, puis avec un tampon), avec le rejeu ancré sur l'horloge estimée
    /// (#123) :
    /// - 120 Hz : régime appris, moyenne 16,97 ms (22,30 ms), maximum 18,65 ms (23,98 ms) ;
    ///   premier geste, moyenne 21,65 ms (26,98 ms) ;
    /// - 60 Hz : régime appris, moyenne 24,81 ms (30,15 ms), maximum 26,15 ms (31,48 ms) ;
    ///   premier geste, moyenne 23,31 ms (28,64 ms).
    /// Avant #123, le régime appris valait 20,24 ms de moyenne et 23,79 ms au pire à 120 Hz, et
    /// 28,87 ms et 35,83 ms à 60 Hz : le délai de livraison du premier toucher s'ajoutait au retard.
    func testGestureLatencyProbe_D15() throws {
        let measurement = try GestureLatencyProbe.measure(sampleRate: 48_000, bufferFrames: 256, displayRate: 120,
                                                          outputLatency: 0.004)
        XCTAssertEqual(measurement.learned.values.count, 8)
        XCTAssertEqual(measurement.firstGesture.values.count, 8)
        XCTAssertEqual(measurement.bufferDuration, 256.0 / 48_000, accuracy: 1e-12)
        XCTAssertEqual(measurement.outputLatency, 0.004)
        XCTAssertEqual(measurement.engineDelay, measurement.learned.mean, accuracy: 1e-12, "D-56: the mean is the reference")
        XCTAssertEqual(measurement.total, measurement.learned.mean + measurement.bufferDuration + 0.004, accuracy: 1e-12)
        XCTAssertEqual(measurement.worstTotal, measurement.learned.maximum + measurement.bufferDuration + 0.004,
                       accuracy: 1e-12)
        XCTAssertEqual(measurement.firstGestureTotal,
                       measurement.firstGesture.mean + measurement.bufferDuration + 0.004, accuracy: 1e-12)
        for spread in [measurement.learned, measurement.firstGesture] {
            XCTAssertGreaterThan(spread.minimum, 0.005)
            XCTAssertLessThan(spread.maximum, 0.06)
            XCTAssertLessThanOrEqual(spread.minimum, spread.mean)
            XCTAssertLessThanOrEqual(spread.mean, spread.maximum)
        }
        // #123: the phase only acts through the age of the newest touch at delivery (at most 1/240 s).
        XCTAssertGreaterThan(measurement.learned.maximum - measurement.learned.minimum, 0.002,
                             "the learned delay depends on the touch/display phase")
        XCTAssertLessThan(measurement.learned.maximum - measurement.learned.minimum, 1 / 240 + 0.000_5,
                          "#123: no longer up to one display frame")

        let direct = Self.directSpread(displayRate: 120, phases: 8)
        XCTAssertEqual(measurement.learned.values.count, direct.learned.values.count)
        for (graph, render) in zip(measurement.learned.values + measurement.firstGesture.values,
                                   direct.learned.values + direct.firstGesture.values) {
            XCTAssertEqual(graph, render, accuracy: 1e-12, "manual-rendering graph = direct render")
        }

        // #114: the aligned phase is the best case; the mean no longer depends on the alignment.
        let aligned = try XCTUnwrap(Self.directEngineDelays(displayRate: 120, splitting: false).delays)
        XCTAssertGreaterThan(measurement.engineDelay, aligned.learned + 0.002, "aligned phase: best case")
        let finer = Self.directSpread(displayRate: 120, phases: 16)
        XCTAssertEqual(finer.learned.mean, measurement.engineDelay, accuracy: 0.000_2, "8 phases are enough for the mean")

        let slow = try GestureLatencyProbe.measure(sampleRate: 48_000, bufferFrames: 256, displayRate: 60)
        XCTAssertGreaterThan(slow.engineDelay, measurement.engineDelay + 0.004, "learned regime: 60 Hz is slower than 120 Hz")
        XCTAssertGreaterThan(slow.engineDelay, slow.firstGestureEngineDelay, "60 Hz: the learned delay exceeds the initial 14 ms")

        let hostMeasurement = try AudioEngineHost(engine: ScratchEngine()).measureGestureLatency()
        XCTAssertEqual(hostMeasurement.learned, measurement.learned, "48 kHz, 256 frames without output")
        XCTAssertEqual(hostMeasurement.firstGesture, measurement.firstGesture)
        XCTAssertEqual(hostMeasurement.outputLatency, 0)
    }

    /// Recette 6.3 CA 3 — SF-78, D-15, D-56, #129 : le rapport de latence donne la sortie réelle (nom,
    /// fréquence, tampon demandé et effectif, latence annoncée, fréquence réelle et dérive en ppm) et,
    /// à 120 puis 60 Hz, la moyenne sur la phase comparée à l'objectif, avec le pire cas, le premier
    /// geste et le seuil d'issue de D-56 (objectif plus une période d'image). Sans sortie, il mesure à
    /// 48 kHz et 256 trames, et le signale.
    func testLatencyReport_6_3() throws {
        let (host, output) = makeHost(failing: false)
        output.info = AudioOutputInfo(name: "Haut-parleurs MacBook Pro", sampleRate: 48_000, bufferFrames: 512,
                                      outputLatency: 0.006)
        output.actualSampleRate = 47_998.8
        host.start()
        let report = try host.latencyReport(displayRates: [120, 60], phases: 2)
        XCTAssertEqual(report.output.name, "Haut-parleurs MacBook Pro")
        XCTAssertTrue(report.output.available)
        XCTAssertEqual(report.output.sampleRate, 48_000)
        XCTAssertEqual(report.output.requestedBufferFrames, 128, "#91: 128 frames requested, 256 as fallback")
        XCTAssertEqual(report.output.effectiveBufferFrames, 512)
        XCTAssertEqual(report.output.outputLatencyMilliseconds, 6, accuracy: 1e-9)
        XCTAssertEqual(report.output.actualSampleRate, 47_998.8)
        XCTAssertEqual(try XCTUnwrap(report.output.driftPartsPerMillion), -25, accuracy: 1e-6, "#129: drift in ppm")
        XCTAssertEqual(report.displays.map(\.displayRate), [120, 60])
        XCTAssertEqual(report.displays.map(\.targetMilliseconds), [20, 30])
        XCTAssertEqual(report.displays[0].issueThresholdMilliseconds, 20 + 1_000.0 / 120, accuracy: 1e-9)
        XCTAssertEqual(report.displays[1].issueThresholdMilliseconds, 30 + 1_000.0 / 60, accuracy: 1e-9)
        XCTAssertEqual(report.displays.map(\.phases), [2, 2])
        let reference = try GestureLatencyProbe.measure(sampleRate: 48_000, bufferFrames: 512, displayRate: 120,
                                                        outputLatency: 0.006, phases: 2)
        let fast = report.displays[0]
        XCTAssertEqual(fast.totalMilliseconds, reference.total * 1_000, accuracy: 1e-9, "D-56 mean, buffer and latency included")
        XCTAssertEqual(fast.worstTotalMilliseconds, reference.worstTotal * 1_000, accuracy: 1e-9)
        XCTAssertEqual(fast.firstGestureTotalMilliseconds, reference.firstGestureTotal * 1_000, accuracy: 1e-9)
        for display in report.displays {
            XCTAssertEqual(display.withinTarget, display.totalMilliseconds <= display.targetMilliseconds)
            XCTAssertEqual(display.worstExceedsIssueThreshold,
                           display.worstTotalMilliseconds > display.issueThresholdMilliseconds, "D-56 issue threshold")
            XCTAssertLessThanOrEqual(display.totalMilliseconds, display.worstTotalMilliseconds)
        }
        XCTAssertEqual(report.withinTargets, report.displays.allSatisfy(\.withinTarget))
        XCTAssertEqual(report.issueRequired, report.displays.contains(where: \.worstExceedsIssueThreshold))
        let json = try JSONEncoder().encode(report)
        XCTAssertEqual(try JSONDecoder().decode(LatencyReport.self, from: json), report)
        XCTAssertTrue(String(decoding: json, as: UTF8.self).contains("\"effectiveBufferFrames\":512"))

        let (unavailable, _) = makeHost(failing: true)
        unavailable.start()
        let fallback = try unavailable.latencyReport(displayRates: [120], phases: 1)
        XCTAssertEqual(fallback.output, LatencyReport.Output(name: nil, available: false, sampleRate: 48_000,
                                                             requestedBufferFrames: 128, effectiveBufferFrames: 256,
                                                             outputLatencyMilliseconds: 0, actualSampleRate: nil,
                                                             driftPartsPerMillion: nil))
        unavailable.stop()
        host.stop()
    }

    /// D-54 : la réponse est lue échantillon par échantillon. C'est valable parce que le moteur rend
    /// exactement la même chose en un appel ou échantillon par échantillon quand aucune commande
    /// n'arrive au milieu d'un tampon : mêmes échantillons, mêmes retards.
    func testSampleBySampleRenderMatchesBufferRender_D54() throws {
        let whole = Self.directEngineDelays(displayRate: 120, splitting: false)
        let split = Self.directEngineDelays(displayRate: 120, splitting: true)
        XCTAssertNotNil(whole.delays)
        XCTAssertEqual(whole.delays, split.delays)
        XCTAssertEqual(whole.output.count, split.output.count)
        XCTAssertTrue(whole.output.elementsEqual(split.output), "bit-exact output")
        XCTAssertGreaterThan(whole.output.map(abs).max() ?? 0, 0.1, "the gestures are audible")
    }

    /// Sonde en rendu direct du moteur, sur `phases` phases réparties sur une image.
    private static func directSpread(displayRate: Double,
                                     phases: Int) -> (learned: GestureLatencyProbe.PhaseSpread,
                                                      firstGesture: GestureLatencyProbe.PhaseSpread) {
        var learned: [Double] = []
        var firstGesture: [Double] = []
        for offset in GestureLatencyProbe.phaseOffsets(count: phases, displayRate: displayRate) {
            guard let delays = directEngineDelays(displayRate: displayRate, splitting: false, phaseOffset: offset).delays
            else { continue }
            learned.append(delays.learned)
            firstGesture.append(delays.firstGesture)
        }
        return (GestureLatencyProbe.PhaseSpread(values: learned), GestureLatencyProbe.PhaseSpread(values: firstGesture))
    }

    /// Sonde en rendu direct du moteur ; `splitting` rend chaque demande échantillon par échantillon.
    private static func directEngineDelays(displayRate: Double, splitting: Bool,
                                           phaseOffset: Double = 0) -> (delays: GestureLatencyProbe.EngineDelays?, output: [Float]) {
        let engine = ScratchEngine()
        let left = UnsafeMutablePointer<Float>.allocate(capacity: 256)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: 256)
        defer {
            left.deallocate()
            right.deallocate()
        }
        var output: [Float] = []
        let delays = GestureLatencyProbe.engineDelays(engine: engine, sampleRate: 48_000, bufferFrames: 256,
                                                      displayRate: displayRate, phaseOffset: phaseOffset) { count in
            if splitting {
                for offset in 0 ..< count { engine.render(frameCount: 1, left: left + offset, right: right + offset) }
            } else {
                engine.render(frameCount: count, left: left, right: right)
            }
            output.append(contentsOf: UnsafeBufferPointer(start: left, count: count))
        }
        return (delays, output)
    }
}
