import XCTest
@testable import ScratchAudio

final class SelfTestTests: XCTestCase {
    func testOfflineRenderProducesAudibleSignal() throws {
        let report = try SelfTest.run(seconds: 0.25)
        XCTAssertTrue(report.passed, "Rapport : \(report)")
    }
}
