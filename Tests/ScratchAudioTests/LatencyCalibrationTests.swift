import Foundation
import ScratchCore
import XCTest
@testable import ScratchAudio

/// Calibrage de la latence geste→son (#91 ; SF-78 ; D-15, D-54, D-56). Premier levier : le tampon de
/// 128 trames, 256 en repli. Mesures par la sonde de #114 (moyenne sur 8 phases, régime appris), hors
/// latence du périphérique, qui s'y ajoute en recette (6.3, #44).
final class LatencyCalibrationTests: XCTestCase {
    /// D-54 : 128 trames d'abord ; un tampon accordé jusqu'à 256 trames est gardé ; sinon 256 trames
    /// sont demandées, et le tampon effectif est publié tel quel.
    func testBufferNegotiation_D54() {
        var requests: [Int] = []
        XCTAssertEqual(OutputBufferPolicy.negotiate { requests.append($0); return $0 }, 128)
        XCTAssertEqual(requests, [128], "128 frames granted")

        requests = []
        XCTAssertEqual(OutputBufferPolicy.negotiate { requests.append($0); return max($0, 192) }, 192)
        XCTAssertEqual(requests, [128], "a device minimum below 256 frames is kept")

        requests = []
        XCTAssertEqual(OutputBufferPolicy.negotiate { requests.append($0); return $0 == 128 ? nil : $0 }, 256)
        XCTAssertEqual(requests, [128, 256], "refused: fallback to 256 frames")

        requests = []
        XCTAssertEqual(OutputBufferPolicy.negotiate { requests.append($0); return max($0, 1_024) }, 1_024)
        XCTAssertEqual(requests, [128, 256], "beyond SF-78 (Bluetooth): fallback asked, effective buffer reported")

        XCTAssertNil(OutputBufferPolicy.negotiate { _ in nil })
        XCTAssertEqual(OutputBufferPolicy.fallbackFrames, TurntableConstants.preferredBufferFrames)
    }

    /// #91 — D-56 : latence de référence = moyenne sur 8 phases touches/affichage (sonde de #114), régime
    /// appris, premier échantillon, un tampon compris, sans la latence du périphérique ; rejeu ancré sur
    /// l'horloge estimée (#123). Valeurs sous Linux en rendu direct (identique au graphe en rendu
    /// manuel), à 48 kHz, moyenne (pire phase) :
    /// - 120 Hz : 22,30 (23,98) ms à 256 trames → 17,03 (18,73) ms à 128 trames, objectif 20 ms ;
    /// - 60 Hz : 30,15 (31,48) ms → 24,98 (26,50) ms, objectif 30 ms.
    /// Il reste ainsi 3,0 ms (120 Hz) et 5,0 ms (60 Hz) pour la latence annoncée du périphérique. Le pire
    /// cas reste sous l'objectif plus une image (seuil d'issue de D-56), y compris au repli de 256 trames.
    func testLearnedLatencyWith128Frames_D15() throws {
        let cases = [(display: 120.0, before: 0.02230, after: 0.01703, objective: 0.020),
                     (display: 60.0, before: 0.03015, after: 0.02498, objective: 0.030)]
        for (display, before, after, objective) in cases {
            let reference = try GestureLatencyProbe.measure(sampleRate: 48_000, bufferFrames: 256, displayRate: display)
            let calibrated = try GestureLatencyProbe.measure(sampleRate: 48_000, bufferFrames: OutputBufferPolicy.preferredFrames,
                                                             displayRate: display)
            XCTAssertEqual(calibrated.learned.values.count, GestureLatencyProbe.defaultPhaseCount)
            XCTAssertEqual(reference.total, before, accuracy: 0.0003, "\(display) Hz, 256 frames: D-56 mean")
            XCTAssertEqual(calibrated.total, after, accuracy: 0.0003, "\(display) Hz, 128 frames: D-56 mean")
            XCTAssertLessThan(calibrated.total, objective - 0.002, "\(display) Hz: room left for the device latency")
            XCTAssertLessThan(calibrated.engineDelay, reference.engineDelay, "the replay delay shrinks with the buffer")
            for measurement in [reference, calibrated] {
                XCTAssertLessThan(measurement.worstTotal, objective + 1 / display, "D-56: worst phase below objective + one frame")
            }
        }
        // A 44.1 kHz output: 128 frames last 2.9 ms (17.74 ms at 120 Hz, 25.93 ms at 60 Hz).
        XCTAssertLessThan(try GestureLatencyProbe.measure(sampleRate: 44_100, bufferFrames: 128, displayRate: 120).total, 0.0185)
        XCTAssertLessThan(try GestureLatencyProbe.measure(sampleRate: 44_100, bufferFrames: 128, displayRate: 60).total, 0.0265)
    }
}
