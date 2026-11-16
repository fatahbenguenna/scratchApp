import ScratchCore
import XCTest
@testable import ScratchUI

/// Mini-graphique de la courbe et repères de cut-in tirés du cœur (#75 ; UX §5.12, §5.13).
@MainActor
final class CurveGraphTests: XCTestCase {
    func testGraphDrawsTheRenderGains() async {
        let hardCut = CurveGraphModel.samples(curve: 1, hamster: false, count: 100)
        XCTAssertEqual(hardCut.count, 101)
        XCTAssertEqual(hardCut.first, .init(x: 0, gainA: 1, gainB: 0))
        XCTAssertEqual(hardCut.last, .init(x: 1, gainA: 0, gainB: 1))
        XCTAssertEqual(hardCut[3].gainB, 1, accuracy: 1e-9, "full level after 3 % of travel")
        XCTAssertEqual(hardCut[50].gainA, 1, accuracy: 1e-9)
        let soft = CurveGraphModel.samples(curve: 0, hamster: false, count: 100)
        XCTAssertEqual(soft[50].gainA, 0.5.squareRoot(), accuracy: 1e-9, "−3 dB at the center")
        for curve in [0, 0.4, 1.0] {
            let samples = CurveGraphModel.samples(curve: curve, hamster: false, count: 44)
            for (previous, next) in zip(samples, samples.dropFirst()) {
                XCTAssertGreaterThanOrEqual(previous.gainA, next.gainA, "A falls towards the right")
                XCTAssertLessThanOrEqual(previous.gainB, next.gainB, "B rises towards the right")
            }
        }
        let hamster = CurveGraphModel.samples(curve: 1, hamster: true, count: 10)
        XCTAssertEqual(hamster.first?.gainB, 1, "hamster: B is full on the left, like the letters")
        XCTAssertEqual(hamster.first?.gainA, 0)
    }

    func testCutInMarksUseTheCoreWidth() async {
        let mixer = MixerViewModel(engine: RecordingEngine())
        for curve in [1.0, 0.9, 0.85] {
            mixer.setCrossfaderCurve(curve)
            XCTAssertEqual(mixer.cutInWidth, CrossfaderCurve.cutInWidth(curve: curve))
        }
        mixer.setCrossfaderCurve(0.5)
        XCTAssertNil(mixer.cutInWidth, "w > 0.2: no marks")
    }
}
