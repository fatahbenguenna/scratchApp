import Foundation
import ScratchCore
import XCTest
@testable import ScratchAudio

/// Hôte audio (squelette 0.2) : sans sortie matérielle, l'horloge de secours fait tourner le moteur
/// en silence (décision Q14, SF-82) ; `suspend()` arrête les moteurs et tout rendu (RM-56, SF-81).
@MainActor
final class AudioEngineHostTests: XCTestCase {
    func testUnavailableOutputKeepsTheEngineRunningOnTheFallbackClock_SF82() async throws {
        let engine = ScratchEngine()
        let host = AudioEngineHost(engine: engine)
        host.start()
        XCTAssertTrue(host.isRenderingAudio)
        if case .unavailable = host.status {} else { XCTFail("expected .unavailable, got \(host.status)") }
        engine.send(.motor(.a, on: true))
        try await Task.sleep(nanoseconds: 200_000_000)
        let snapshot = engine.latestSnapshot()
        XCTAssertGreaterThan(snapshot.sampleTime, 0, "the fallback clock renders")
        XCTAssertTrue(snapshot[.a].motorOn, "commands are applied without pump()")

        host.suspend()
        XCTAssertFalse(host.isRenderingAudio)
        engine.pump()
        XCTAssertFalse(engine.latestSnapshot()[.a].motorOn, "suspend() stops every motor (RM-56)")
        let frozen = engine.latestSnapshot().sampleTime
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(engine.latestSnapshot().sampleTime, frozen, "no render while suspended")

        host.resume()
        XCTAssertTrue(host.isRenderingAudio)
        XCTAssertFalse(engine.latestSnapshot()[.a].motorOn, "resume() never restarts a motor (RM-10)")
        host.stop()
        XCTAssertEqual(host.status, .stopped)
    }
}
