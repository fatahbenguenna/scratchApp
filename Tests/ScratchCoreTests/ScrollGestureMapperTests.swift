import Foundation
import XCTest
@testable import ScratchCore

/// Défilement trackpad et molette (story 1.2 CA 7 ; SF-79, D-24, UX §6.3) : disque de centre
/// (100, 100), R = 80, saisie à 86.
final class ScrollGestureMapperTests: XCTestCase {
    private func mapper(_ deck: DeckID = .b) -> ScrollGestureMapper {
        ScrollGestureMapper(deck: deck, centerX: 100, centerY: 100, vinylRadius: 80, grabRadius: 86)
    }

    private func angle(of command: EngineCommand?) -> Double? {
        if case let .touchMoved(_, angle, _, _) = command { return angle }
        return nil
    }

    // AC7 — SF-79 : formule de l'UX §6.3, sens horaire, repli en haut du disque au centre.
    func testScrollFormulaAndCenterFallback_SF79() {
        let disc = mapper()
        XCTAssertEqual(disc.rotation(x: 100, y: 20, deltaX: 8, deltaY: 0), 0.1, accuracy: 1e-12,
                       "fingers moving right at the top of the disc: clockwise, surface follows")
        XCTAssertEqual(disc.rotation(x: 180, y: 100, deltaX: 0, deltaY: 8), 0.1, accuracy: 1e-12,
                       "moving down on the right: clockwise")
        XCTAssertEqual(disc.rotation(x: 20, y: 100, deltaX: 0, deltaY: 8), -0.1, accuracy: 1e-12)
        XCTAssertEqual(disc.rotation(x: 100, y: 80, deltaX: 4, deltaY: 0), 0.1, accuracy: 1e-12,
                       "‖r‖ = 20 < 0.5 R: gain limited by max(‖r‖, 0.5 R)")
        XCTAssertEqual(disc.rotation(x: 102, y: 101, deltaX: 4, deltaY: 0), 0.1, accuracy: 1e-12,
                       "center zone: r taken at the top, 0.5 R")

        var scroll = mapper()
        let began = scroll.scroll(x: 100, y: 20, deltaX: 0, deltaY: 0, phase: .began, time: 10)
        XCTAssertEqual(began, [.touchBegan(.b, angle: 0, time: 10)])
        let moved = scroll.scroll(x: 100, y: 20, deltaX: 8, deltaY: 0, phase: .changed, time: 10.01)
        XCTAssertEqual(moved, [.touchMoved(.b, angle: 0.1, time: 10.01, predicted: false)])
    }

    // AC7 — RM-60 : un défilement commencé hors du disque ne le saisit pas, même s'il passe dessus.
    func testScrollStartedOutsideDoesNotGrab_RM60() {
        var scroll = mapper()
        XCTAssertEqual(scroll.scroll(x: 300, y: 100, deltaX: 0, deltaY: 0, phase: .began, time: 1), [])
        XCTAssertEqual(scroll.scroll(x: 100, y: 20, deltaX: 8, deltaY: 0, phase: .changed, time: 1.01), [])
        XCTAssertFalse(scroll.isHolding)
        XCTAssertNil(scroll.releaseDeadline)
    }

    // AC7 — D-24 : l'inertie ne tourne pas le disque et ne prolonge pas la saisie.
    func testMomentumIsIgnored() {
        var scroll = mapper()
        _ = scroll.scroll(x: 100, y: 20, deltaX: 0, deltaY: 0, phase: .began, time: 1)
        _ = scroll.scroll(x: 100, y: 20, deltaX: 8, deltaY: 0, phase: .ended, time: 1.02)
        XCTAssertEqual(scroll.scroll(x: 100, y: 20, deltaX: 40, deltaY: 0, phase: .momentum, time: 1.05), [])
        let deadline = scroll.releaseDeadline ?? 0
        XCTAssertEqual(deadline, 1.1, accuracy: 1e-12, "ended + 80 ms, not extended")
        XCTAssertEqual(scroll.scroll(x: 100, y: 20, deltaX: 40, deltaY: 0, phase: .momentum, time: 1.2),
                       [.touchEnded(.b, time: deadline)], "only the due release is emitted")
    }

    // AC7 — UX §6.3 : molette sans phases, 15° par cran, relâchement 80 ms après le dernier cran.
    func testWheelNotchIsFifteenDegrees() {
        var scroll = mapper(.a)
        let first = scroll.scroll(x: 150, y: 100, deltaX: 0, deltaY: 1, phase: .none, time: 5)
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first.first, .touchBegan(.a, angle: 0, time: 5 - ScrollGestureMapper.wheelNotchDuration))
        XCTAssertEqual(angle(of: first.last) ?? 0, 15 * Double.pi / 180, accuracy: 1e-12)
        let second = scroll.scroll(x: 150, y: 100, deltaX: 0, deltaY: -2, phase: .none, time: 5.03)
        XCTAssertEqual(angle(of: second.first) ?? 0, -15 * Double.pi / 180, accuracy: 1e-12, "two notches back")
        let due = scroll.releaseDeadline ?? 0
        XCTAssertEqual(due, 5.11, accuracy: 1e-9)
        XCTAssertEqual(scroll.poll(now: 5.11), .touchEnded(.a, time: due))
        XCTAssertEqual(scroll.scroll(x: 300, y: 100, deltaX: 0, deltaY: 1, phase: .none, time: 6), [],
                       "a notch outside the disc does not grab")
    }

    // AC7 — SF-79, 6.14 (scénario « Relâchement du trackpad à 80 ms ») : horloge injectée.
    func testScrollReleaseAfter80msOnInjectedClock_SF79() {
        var scroll = mapper(.b)
        XCTAssertEqual(scroll.scroll(x: 100, y: 20, deltaX: 0, deltaY: 0, phase: .began, time: 10.000).count, 1)
        for (index, time) in [10.05, 10.1, 10.15, 10.2, 10.25].enumerated() {
            let phase: ScrollGestureMapper.Phase = index == 4 ? .ended : .changed
            XCTAssertEqual(scroll.scroll(x: 100, y: 20, deltaX: 2, deltaY: 0, phase: phase, time: time).count, 1)
        }
        XCTAssertNil(scroll.poll(now: 10.329), "an explicit ended phase does not release earlier")
        XCTAssertTrue(scroll.isHolding)
        let release = scroll.poll(now: 10.330)
        guard case let .touchEnded(deck, time) = release else { return XCTFail("\(String(describing: release))") }
        XCTAssertEqual(deck, .b)
        XCTAssertEqual(time, 10.330, accuracy: 1e-9, "stamped last event + 0.080 s, not the poll time")
        XCTAssertNil(scroll.poll(now: 10.5), "emitted once")
    }
}
