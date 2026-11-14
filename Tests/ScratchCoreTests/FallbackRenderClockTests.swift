import Foundation
import XCTest
@testable import ScratchCore

/// Horloge de secours (décision Q14, SF-82) : sans sortie audio, le moteur est rendu au rythme du
/// temps réel, en silence ; après `stop()`, plus aucun rendu.
final class FallbackRenderClockTests: XCTestCase {
    func testRendersAtRealTimePaceAndStopsSynchronously_SF82() {
        let engine = ScratchEngine()
        let clock = FallbackRenderClock(engine: engine, sampleRate: 48_000)
        XCTAssertFalse(clock.isRunning)
        engine.send(.motor(.a, on: true))
        clock.start()
        XCTAssertTrue(clock.isRunning)
        let started = Date()
        Thread.sleep(forTimeInterval: 0.3)
        clock.stop()
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertFalse(clock.isRunning)

        let snapshot = engine.latestSnapshot()
        XCTAssertTrue(snapshot[.a].motorOn, "commands are applied by the fallback renders")
        let expected = elapsed * 48_000
        // Generous bounds: CI runners can be slow, but the clock must neither stall nor run ahead.
        XCTAssertGreaterThan(Double(snapshot.sampleTime), expected * 0.3)
        XCTAssertLessThan(Double(snapshot.sampleTime), expected * 1.2)

        let frozen = engine.latestSnapshot().sampleTime
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(engine.latestSnapshot().sampleTime, frozen, "no render after stop()")
        engine.pump() // the control thread may pump again once the clock is stopped
    }

    func testStartAndStopAreIdempotent() {
        let clock = FallbackRenderClock(engine: ScratchEngine())
        clock.stop()
        clock.start()
        clock.start()
        clock.stop()
        clock.stop()
        XCTAssertFalse(clock.isRunning)
    }
}
