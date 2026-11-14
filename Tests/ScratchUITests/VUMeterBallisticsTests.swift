import ScratchCore
import XCTest
@testable import ScratchUI

/// Balistique des VU-mètres de voie (story 4.2 CA 3 ; SF-65, D-26 ; UX §5.15).
@MainActor
final class VUMeterBallisticsTests: XCTestCase {
    private func dB(_ value: Double) -> Double { pow(10, value / 20) }

    // AC3 — montée instantanée, descente de 20 dB/s, maintien de crête 1 s, 12 segments.
    func testVUMeterBallistics_SF65() async {
        var meter = VUMeterBallistics()
        meter.update(peak: 0, at: 0)
        XCTAssertEqual(meter.litSegments, 0)
        XCTAssertEqual(meter.accessibilityValue, "silence")
        meter.update(peak: dB(-6), at: 0.01)
        XCTAssertEqual(meter.level, -6, accuracy: 1e-9, "instant rise")
        XCTAssertEqual(meter.litSegments, 9, "-48 … -6 dBFS lit")
        XCTAssertEqual(meter.accessibilityValue, "\u{2212}6\u{00A0}dB")
        meter.update(peak: dB(-40), at: 0.51)
        XCTAssertEqual(meter.level, -16, accuracy: 1e-9, "falls 20 dB/s")
        XCTAssertEqual(meter.peakSegment, 8, "peak held on the -6 dB segment")
        meter.update(peak: dB(-40), at: 1.0)
        XCTAssertEqual(meter.peakSegment, 8, "still held before 1 s")
        meter.update(peak: dB(-40), at: 1.02)
        XCTAssertEqual(meter.level, -26.2, accuracy: 1e-9)
        XCTAssertEqual(meter.peakSegment, 3, "hold released after 1 s: follows the level (-30 dB segment)")
        meter.update(peak: 1, at: 1.03)
        XCTAssertEqual(meter.litSegments, 12)
        XCTAssertEqual(meter.accessibilityValue, "0\u{00A0}dB")
    }

    // AC3 — la voie suit `DeckSnapshot.peakLevel` à chaque image (niveau après le fader de voie).
    func testDeckChannelMeterFollowsTheSnapshotPeak() async {
        var now = 0.0
        let deck = DeckViewModel(deck: .b, engine: RecordingEngine())
        deck.clock = { now }
        var snapshot = DeckSnapshot.initial
        snapshot.peakLevel = dB(-12)
        deck.apply(snapshot)
        XCTAssertEqual(deck.channelMeter.level, -12, accuracy: 1e-9)
        now = 0.25
        snapshot.peakLevel = 0
        deck.apply(snapshot)
        XCTAssertEqual(deck.channelMeter.level, -17, accuracy: 1e-9)
    }
}
