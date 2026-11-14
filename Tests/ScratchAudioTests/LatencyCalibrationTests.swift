import Foundation
import ScratchCore
import XCTest
@testable import ScratchAudio

/// Calibrage de la latence geste→son (#91 ; SF-78 ; D-15, D-54). Premier levier : le tampon de 128
/// trames, 256 en repli. Mesures par la sonde en régime appris (#92), hors latence du périphérique,
/// qui s'y ajoute en recette (6.3, #44).
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

    /// #91 — régime appris, partie moteur et un tampon, à 48 kHz. Valeurs sous Linux en rendu direct
    /// (identique au graphe en rendu manuel) :
    /// - 120 Hz : 19,0 ms à 256 trames → 15,2 ms à 128 trames (objectif 20 ms) ;
    /// - 60 Hz : 27,3 ms → 23,1 ms (objectif 30 ms).
    /// Le tampon de 128 trames laisse ainsi 4,8 ms (120 Hz) et 6,9 ms (60 Hz) à la latence annoncée du
    /// périphérique. Les seuils du test gardent 0,5 ms de marge sur les mesures.
    func testLearnedLatencyWith128Frames_D15() throws {
        for (display, before, after, objective) in [(120.0, 0.0190, 0.0152, 0.020), (60.0, 0.0273, 0.0231, 0.030)] {
            let reference = try GestureLatencyProbe.measure(sampleRate: 48_000, bufferFrames: 256, displayRate: display)
            let calibrated = try GestureLatencyProbe.measure(sampleRate: 48_000, bufferFrames: OutputBufferPolicy.preferredFrames,
                                                             displayRate: display)
            XCTAssertEqual(reference.total, before, accuracy: 0.0005, "\(display) Hz, 256 frames")
            XCTAssertEqual(calibrated.total, after, accuracy: 0.0005, "\(display) Hz, 128 frames")
            XCTAssertLessThan(calibrated.total, objective - 0.004, "\(display) Hz: room left for the device latency")
            XCTAssertLessThan(calibrated.engineDelay, reference.engineDelay, "the replay delay shrinks with the buffer")
            XCTAssertLessThanOrEqual(calibrated.firstGestureTotal, reference.firstGestureTotal + 1e-9)
        }
        // A 44.1 kHz output: 128 frames last 2.9 ms; same gain.
        let cd = try GestureLatencyProbe.measure(sampleRate: 44_100, bufferFrames: 128, displayRate: 120)
        XCTAssertLessThan(cd.total, 0.016)
    }
}
