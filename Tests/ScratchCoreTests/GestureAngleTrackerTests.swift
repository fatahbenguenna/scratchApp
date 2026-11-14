import Foundation
import XCTest
@testable import ScratchCore

/// Suivi d'angle d'un disque (story 1.2) : disque de centre (100, 100), R = 80, saisie à 86.
final class GestureAngleTrackerTests: XCTestCase {
    private let degree = Double.pi / 180

    private func tracker() -> GestureAngleTracker {
        GestureAngleTracker(centerX: 100, centerY: 100, radius: 80, grabRadius: 86)
    }

    /// Point à `radius` du centre, à l'angle `angle` depuis midi, sens horaire (y vers le bas).
    private func point(_ angle: Double, radius: Double = 80, centerX: Double = 100,
                       centerY: Double = 100) -> (x: Double, y: Double) {
        (centerX + radius * sin(angle), centerY - radius * cos(angle))
    }

    // AC1 — RM-04 (scénario « Dépliement sur trois tours »)
    func testUnwrapsThreeTurns_RM04() {
        var tracker = tracker()
        XCTAssertTrue(tracker.begin(x: 180, y: 100))
        let start = tracker.angle
        XCTAssertEqual(start, .pi / 2, accuracy: 1e-12, "3 o'clock is a quarter turn clockwise from noon")
        var previous = start
        for step in 1...108 {
            let p = point(.pi / 2 + Double(step) * 10 * degree)
            let angle = tracker.move(x: p.x, y: p.y)
            XCTAssertEqual(angle - previous, 10 * degree, accuracy: 1e-9, "no jump at ±π (step \(step))")
            previous = angle
        }
        XCTAssertEqual(tracker.angle - start, 6 * .pi, accuracy: 1e-6, "three clockwise turns = +6π, gain 1:1")
        for step in 1...36 {
            let p = point(.pi / 2 - Double(step) * 10 * degree)
            tracker.move(x: p.x, y: p.y)
        }
        XCTAssertEqual(tracker.angle - start, 4 * .pi, accuracy: 1e-6, "counterclockwise is negative")
    }

    // AC2 — RM-60, UX §5.1 : saisie seulement au départ, dans `min(R + 6, P / 2)`.
    func testGrabOnlyWhenStartingInsideGrabRadius_RM60() {
        var outside = tracker()
        XCTAssertFalse(outside.begin(x: 190, y: 100), "90 pt from the center: outside the grab radius")
        XCTAssertFalse(outside.isTracking)
        XCTAssertEqual(outside.move(x: 150, y: 100), 0, "a contact sliding in does not grab")
        var rim = tracker()
        XCTAssertTrue(rim.begin(x: 185, y: 100), "between R and R + 6: grabbed")
        XCTAssertTrue(rim.contains(x: 186, y: 100))
    }

    // AC5 — RM-61 : zone centrale (rayon < 0,12 R = 9,6 pt).
    func testCenterDeadZoneFreezesAndResumesWithoutJump_RM61() {
        var tracker = tracker()
        XCTAssertTrue(tracker.begin(x: 100, y: 95), "a contact in the center zone holds the disc")
        let frozen = tracker.angle
        tracker.move(x: 104, y: 103)
        tracker.move(x: 96, y: 104)
        XCTAssertEqual(tracker.angle, frozen, "no rotation inside the zone")
        let exit = point(.pi / 2, radius: 40)
        tracker.move(x: exit.x, y: exit.y)
        XCTAssertEqual(tracker.angle, frozen, "leaving the zone resumes from the current angle, no jump")
        let turned = point(.pi / 2 + 30 * degree, radius: 40)
        tracker.move(x: turned.x, y: turned.y)
        XCTAssertEqual(tracker.angle - frozen, 30 * degree, accuracy: 1e-9)

        // Entering mid-gesture freezes too; crossing the center between two samples adds no half turn.
        tracker.move(x: 103, y: 100)
        let entered = tracker.angle
        tracker.move(x: 60, y: 100)
        XCTAssertEqual(tracker.angle, entered)
        tracker.move(x: 140, y: 100)
        XCTAssertEqual(tracker.angle, entered, "segment through the center: frozen, no ±π")
    }

    // AC8 — 6.14 : centre déplacé de 50 pt et rayon × 1,5 pendant le geste.
    func testGeometryChangeDuringGestureHasNoJump_6_14() {
        var tracker = tracker()
        _ = tracker.begin(x: 180, y: 100)
        let p = point(.pi / 2 + 20 * degree)
        tracker.move(x: p.x, y: p.y)
        let before = tracker.angle
        // The window grows: the disc moves and the last point now sits elsewhere around the new center.
        tracker.updateGeometry(centerX: 150, centerY: 100, radius: 120, grabRadius: 126)
        XCTAssertEqual(tracker.angle, before, "the cumulative angle does not change")
        let lastRaw = atan2(p.x - 150, 100 - p.y)
        let next = point(lastRaw + 5 * degree, radius: 120, centerX: 150)
        tracker.move(x: next.x, y: next.y)
        XCTAssertEqual(tracker.angle - before, 5 * degree, accuracy: 1e-9, "tracking resumes without a jump")
    }

    // AC6 — SF-78 : une prédiction ne modifie pas l'état.
    func testPredictedAngleHasNoSideEffect_SF78() {
        var tracker = tracker()
        _ = tracker.begin(x: 180, y: 100)
        let ahead = point(.pi / 2 + 40 * degree)
        XCTAssertEqual(tracker.predictedAngle(x: ahead.x, y: ahead.y) - .pi / 2, 40 * degree, accuracy: 1e-9)
        XCTAssertEqual(tracker.angle, .pi / 2, accuracy: 1e-12)
        let real = point(.pi / 2 + 10 * degree)
        XCTAssertEqual(tracker.move(x: real.x, y: real.y) - .pi / 2, 10 * degree, accuracy: 1e-9)
    }
}
