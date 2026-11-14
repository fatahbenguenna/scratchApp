import Foundation
import XCTest
@testable import ScratchCore

/// Courbe du crossfader (story 1.4 CA 2 ; spec 5.2, SF-66, D-02 ; Gherkin 6.4, 6.10).
final class CrossfaderCurveTests: XCTestCase {
    /// CA2 — 6.10 « Gain des voies selon la courbe » : sept lignes du tableau, à ±0,05.
    func testCurveTable_6_10() {
        let rows: [(curve: Double, x: Double, a: Double, b: Double)] = [
            (1, 0, 1.00, 0.00), (1, 0.03, 1.00, 1.00), (1, 0.5, 1.00, 1.00), (1, 1, 0.00, 1.00),
            (0, 0, 1.00, 0.00), (0, 0.5, 0.71, 0.71), (0, 1, 0.00, 1.00),
        ]
        for row in rows {
            let gains = CrossfaderCurve.gains(position: row.x, curve: row.curve)
            XCTAssertEqual(gains.a, row.a, accuracy: 0.05, "curve \(row.curve), x \(row.x)")
            XCTAssertEqual(gains.b, row.b, accuracy: 0.05, "curve \(row.curve), x \(row.x)")
        }
    }

    /// CA2 — SF-66, 6.4 « Crossfader en position intermédiaire avec courbe douce » : −3 dB ± 0,5 dB
    /// au centre ; puissance constante sur toute la course.
    func testSoftCurveIsMinus3dBAtCenter_SF66() {
        let center = CrossfaderCurve.gains(position: 0.5, curve: 0)
        XCTAssertEqual(20 * log10(center.a), -3, accuracy: 0.5)
        XCTAssertEqual(20 * log10(center.b), -3, accuracy: 0.5)
        for x in stride(from: 0.0, through: 1, by: 0.01) {
            let gains = CrossfaderCurve.gains(position: x, curve: 0)
            XCTAssertEqual(gains.a * gains.a + gains.b * gains.b, 1, accuracy: 1e-12, "constant power at \(x)")
        }
    }

    /// CA2 — SF-66, 6.4 « Ouvrir la voie avec un déplacement minimal (cut-in) » : en coupure franche,
    /// plein niveau à 3 % de course depuis la butée opposée, silence en butée.
    func testHardCutReachesFullLevelWithin3Percent_SF66() {
        XCTAssertEqual(CrossfaderCurve.gains(position: 0.03, curve: 1).b, 1)
        XCTAssertLessThan(CrossfaderCurve.gains(position: 0.029, curve: 1).b, 1)
        XCTAssertEqual(CrossfaderCurve.gains(position: 0.97, curve: 1).a, 1, accuracy: 1e-12)
        XCTAssertLessThan(CrossfaderCurve.gains(position: 0.971, curve: 1).a, 1)
        XCTAssertEqual(CrossfaderCurve.gains(position: 0, curve: 1).b, 0)
        XCTAssertEqual(CrossfaderCurve.gains(position: 1, curve: 1).a, 0, "a closed channel is exactly silent")
        XCTAssertEqual(CrossfaderCurve.gains(position: 0.015, curve: 1).b, 0.5, accuracy: 1e-12, "linear cut-in")
    }

    /// CA2 — 5.2 : pour toute courbe, gains monotones en x ; à x fixé, gains croissants avec la
    /// courbe (changement monotone et perceptible) ; `w = lerp(1 ; 0,03 ; c)` décroît avec c et la
    /// voie atteint le plein niveau à `w` de course.
    func testIntermediateCurvesAreMonotonic_5_2() {
        var previousWidth = Double.infinity
        var previousCurve: [(a: Double, b: Double)]?
        for step in 0...40 {
            let curve = Double(step) / 40
            let width = CrossfaderCurve.cutInWidth(curve: curve)
            XCTAssertLessThan(width, previousWidth)
            previousWidth = width
            let gains = (0...1_000).map { CrossfaderCurve.gains(position: Double($0) / 1_000, curve: curve) }
            for (next, current) in zip(gains.dropFirst(), gains) {
                XCTAssertGreaterThanOrEqual(next.b, current.b, "B rises with x, curve \(curve)")
                XCTAssertLessThanOrEqual(next.a, current.a, "A falls with x, curve \(curve)")
            }
            XCTAssertEqual(CrossfaderCurve.gains(position: width, curve: curve).b, 1, accuracy: 1e-12)
            XCTAssertEqual(CrossfaderCurve.gains(position: 1 - width, curve: curve).a, 1, accuracy: 1e-12)
            if let previousCurve {
                for (current, previous) in zip(gains, previousCurve) {
                    XCTAssertGreaterThanOrEqual(current.a, previous.a - 1e-15)
                    XCTAssertGreaterThanOrEqual(current.b, previous.b - 1e-15)
                }
            }
            previousCurve = gains
        }
        // Perceptible: halfway, the centre gain is well between the soft and hard values.
        let halfway = CrossfaderCurve.gains(position: 0.5, curve: 0.5)
        XCTAssertGreaterThan(halfway.a, 0.8)
        XCTAssertLessThan(CrossfaderCurve.gains(position: 0.2, curve: 0.5).b, 0.9)
    }

    func testOutOfRangeInputsAreClamped() {
        XCTAssertTrue(CrossfaderCurve.gains(position: -1, curve: 1) == CrossfaderCurve.gains(position: 0, curve: 1))
        XCTAssertTrue(CrossfaderCurve.gains(position: 2, curve: 3) == CrossfaderCurve.gains(position: 1, curve: 1))
        let fallback = CrossfaderCurve.gains(position: .nan, curve: .nan)
        XCTAssertTrue(fallback == CrossfaderCurve.gains(position: 0.5, curve: 1))
    }
}
