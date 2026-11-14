import XCTest
import ScratchCore
@testable import ScratchAudio

/// Self-test de scratch complet (story 2.4 ; spec §7, P0) : mêmes vérifications que
/// `ScratchApp --selftest`, avec le détail des mesures en cas d'échec (CA 5).
final class SelfTestTests: XCTestCase {
    private func describe(_ report: SelfTest.Report) -> String {
        report.details.sorted { $0.key < $1.key }.map { "\($0.key) = \($0.value)" }.joined(separator: ", ")
    }

    /// CA1 à CA3, CA5 : graphe AVAudioEngine réel en rendu manuel, son de démonstration sur A et B,
    /// toutes les vérifications nommées présentes et vraies.
    func testSelfTestPassesWithDemoSound() throws {
        let report = try SelfTest.run()
        for name in ScratchScenario.checkNames + ["renderedThroughAVAudioEngine"] {
            XCTAssertEqual(report.checks[name], true, "\(name) — \(describe(report))")
        }
        XCTAssertTrue(report.passed, describe(report))
        XCTAssertEqual(report.details["framesRendered"] ?? 0, 7.8 * 48_000, accuracy: 0.5)
        XCTAssertNotNil(try? JSONEncoder().encode(report), "the report is valid JSON (no non-finite value)")
    }

    /// CA3, CA4 : un son muet fait échouer les vérifications qui demandent du son (le test détecte
    /// bien) ; le rapport reste un JSON valide.
    func testSelfTestFailsOnSilentClip() throws {
        let silent = AudioClip(title: "silence", sampleRate: 48_000, frameCount: 48_000 * 8) { _, _ in }
        let report = try SelfTest.run(clip: silent)
        XCTAssertFalse(report.passed)
        XCTAssertEqual(report.checks["cutInWithin1ms"], false)
        XCTAssertEqual(report.checks["noNaN"], true)
        XCTAssertNotNil(try? JSONEncoder().encode(report))
    }

    /// CA4 : exécution en moins de 30 s (build de débogage de la CI compris).
    func testSelfTestDuration() throws {
        let report = try SelfTest.run()
        let duration = report.details["durationSeconds"] ?? .infinity
        XCTAssertLessThan(duration, 30, "self-test duration \(duration) s")
    }
}
