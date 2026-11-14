import Foundation
import XCTest
@testable import ScratchCore

/// Charge du rendu (story 1.5 CA 11 ; NFR3, indicatif) : deux platines à 16× avec anti-repliement,
/// tampons de 256 trames à 48 kHz. La mesure est journalisée (`RenderMetricsLog`) ; elle n'a de sens
/// qu'en build optimisé (`swift test -c release -Xswiftc -enable-testing --filter RenderLoadTests`),
/// où elle doit rester sous 30 % de la durée du tampon. En débogage (CI), elle est seulement publiée.
final class RenderLoadTests: XCTestCase {
    func testRenderLoadAt16x_NFR3() {
        let engine = ScratchEngine()
        engine.send(.load(.a, TestClips.noise(frames: 48_000 * 60)))
        engine.send(.load(.b, TestClips.noise(frames: 48_000 * 60)))
        engine.send(.seek(.a, seconds: 5))
        engine.send(.seek(.b, seconds: 55))
        let speed = 16 * TurntableConstants.referenceAngularVelocity * 1.05 // saturates at 16×
        let left = UnsafeMutablePointer<Float>.allocate(capacity: 256)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: 256)
        defer {
            left.deallocate()
            right.deallocate()
        }
        var buffer = 0
        func renderBuffer() {
            let time = Double(buffer) * 256 / 48_000
            if buffer == 0 {
                engine.send(.touchBegan(.a, angle: 0, time: 0))
                engine.send(.touchBegan(.b, angle: 0, time: 0))
            } else {
                engine.send(.touchMoved(.a, angle: speed * time, time: time))
                engine.send(.touchMoved(.b, angle: -speed * time, time: time))
            }
            engine.render(frameCount: 256, left: left, right: right)
            buffer += 1
        }
        for _ in 0..<100 { renderBuffer() } // warm-up and spin-up to 16×
        let snapshot = engine.latestSnapshot()
        XCTAssertEqual(snapshot[.a].playbackRate, 16, accuracy: 0.01, "deck A at 16×")
        XCTAssertEqual(snapshot[.b].playbackRate, -16, accuracy: 0.01, "deck B at −16×")

        let buffers = 400
        let clock = ContinuousClock()
        let elapsed = clock.measure { for _ in 0..<buffers { renderBuffer() } }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        let perBuffer = seconds / Double(buffers)
        let load = perBuffer / (256 / 48_000) * 100
        XCTAssertEqual(abs(engine.latestSnapshot()[.a].playbackRate), 16, accuracy: 0.01)
        #if os(macOS)
        let system = "macOS"
        #else
        let system = "Linux"
        #endif
        RenderMetricsLog.write(String(format: "NFR3 — 2 platines à 16× : %.1f µs par tampon de 256 trames = %.1f %% (build %@, %@)",
                                      perBuffer * 1e6, load, RenderMetricsLog.configuration, system))
        XCTAssertTrue(load.isFinite)
        if !RenderMetricsLog.isDebugBuild {
            XCTAssertLessThanOrEqual(load, 30, "NFR3: at most 30 % of the buffer duration")
        }
    }
}
