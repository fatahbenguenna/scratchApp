import XCTest
@testable import ScratchCore

final class TurntableConstantsTests: XCTestCase {
    func testOneRevolutionIsOnePointEightSeconds() {
        XCTAssertEqual(TurntableConstants.secondsPerRevolution, 1.8, accuracy: 1e-12)
    }

    func testFortyFiveIsOnePointThirtyFiveTimesFaster() {
        XCTAssertEqual(TurntableSpeed.rpm45.rpm / TurntableSpeed.rpm33.rpm, 1.35, accuracy: 1e-12)
    }

    func testPitchExamplesFromSpec() {
        // Spec v2.0 — 6.6 : 33⅓ à −8 % = 30,67 RPM ; 45 à +8 % = 48,60 RPM.
        XCTAssertEqual(TurntableSpeed.rpm33.rpm * (1 - 0.08), 30.67, accuracy: 0.005)
        XCTAssertEqual(TurntableSpeed.rpm45.rpm * (1 + 0.08), 48.60, accuracy: 0.005)
    }
}
