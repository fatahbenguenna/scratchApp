import Foundation
import XCTest
@testable import ScratchCore

/// Scénario hors ligne déterministe (story 1.5 CA 10 ; NFR11 ; base du self-test 2.4).
final class ScratchScenarioTests: XCTestCase {
    /// CA10 : le scénario passe sur un clip synthétique (sinusoïde de 440 Hz de 10 s) ; chaque
    /// vérification nommée est présente et vraie.
    func testScenarioPassesWithSyntheticClip() {
        let scenario = ScratchScenario(clipA: TestClips.sine(frequency: 440, seconds: 10, amplitude: 0.8),
                                       clipB: TestClips.sine(frequency: 220, seconds: 10, amplitude: 0.8))
        let run = scenario.run(on: ScratchEngine())
        XCTAssertEqual(Set(run.report.checks.keys), Set(ScratchScenario.checkNames))
        for name in ScratchScenario.checkNames {
            XCTAssertEqual(run.report.checks[name], true, "\(name) — \(run.report.details)")
        }
        XCTAssertTrue(run.report.passed)
        XCTAssertEqual(run.left.count, Int(scenario.totalFrames))
    }

    /// CA10 — NFR11 : un même flux de commandes produit la même sortie à l'échantillon près.
    func testScenarioIsDeterministic_NFR11() {
        let clip = TestClips.sine(frequency: 440, seconds: 10, amplitude: 0.8)
        let first = ScratchScenario(clipA: clip, clipB: nil).run(on: ScratchEngine())
        let second = ScratchScenario(clipA: clip, clipB: nil).run(on: ScratchEngine())
        XCTAssertEqual(first.left, second.left)
        XCTAssertEqual(first.right, second.right)
        XCTAssertEqual(first.report, second.report)
    }

    /// Les vérifications détectent un défaut : un clip trop court (la tête atteint la fin du son)
    /// fait échouer les contrôles qui demandent du son.
    func testScenarioDetectsMissingSound() {
        let run = ScratchScenario(clipA: TestClips.sine(frequency: 440, seconds: 1.2), clipB: nil).run(on: ScratchEngine())
        XCTAssertFalse(run.report.passed)
        XCTAssertEqual(run.report.checks["cutInWithin1ms"], false)
    }

    func testEventsAreSortedAndBlockAligned() {
        let scenario = ScratchScenario(clipA: TestClips.sine(frequency: 440, seconds: 10), clipB: nil)
        XCTAssertTrue(zip(scenario.events.dropFirst(), scenario.events).allSatisfy { $0.frame >= $1.frame })
        var collected = 0
        var frame: Int64 = 0
        while frame < scenario.totalFrames {
            collected += scenario.events(forBlockStartingAt: frame).count
            frame += Int64(scenario.blockFrames)
        }
        XCTAssertEqual(collected, scenario.events.count, "every event is delivered exactly once")
        let report = try? JSONEncoder().encode(ScenarioReport(checks: ["noNaN": true], details: [:]))
        XCTAssertNotNil(report, "the report is encodable (self-test JSON, story 2.4)")
    }
}
