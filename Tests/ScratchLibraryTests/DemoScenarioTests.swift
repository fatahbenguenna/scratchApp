import Foundation
import XCTest
import ScratchCore
@testable import ScratchLibrary

/// Le scénario hors ligne de la story 1.5 passe avec le son de démonstration (SF-76), qui sera son
/// entrée dans le self-test de la CI (story 2.4).
final class DemoScenarioTests: XCTestCase {
    func testScenarioPassesWithDemoSound_SF76() {
        let scenario = ScratchScenario(clipA: DemoSound.makeClip(), clipB: DemoSound.makeClip())
        let run = scenario.run(on: ScratchEngine())
        for name in ScratchScenario.checkNames {
            XCTAssertEqual(run.report.checks[name], true, "\(name) — \(run.report.details)")
        }
        XCTAssertTrue(run.report.passed)
    }
}
