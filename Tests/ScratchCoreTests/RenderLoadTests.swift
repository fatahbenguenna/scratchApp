import Foundation
import XCTest
@testable import ScratchCore

/// Charge du rendu (story 1.5 CA 11 ; NFR3, indicatif) : deux platines à 16× avec anti-repliement,
/// tampons de 256 trames à 48 kHz, et de 128 trames, le tampon visé par le calibrage de la latence
/// (#91, D-54). La mesure est journalisée (`RenderMetricsLog`) ; elle n'a de sens qu'en build optimisé
/// (`swift test -c release -Xswiftc -enable-testing --filter RenderLoadTests`), où elle doit rester sous
/// 30 % de la durée du tampon. En débogage (CI), elle est seulement publiée.
final class RenderLoadTests: XCTestCase {
    func testRenderLoadAt16x_NFR3() {
        measureLoad(bufferFrames: 256)
    }

    /// #91, D-54 : contrôle de NFR3 avec le tampon de 128 trames. Le coût fixe de chaque tampon
    /// (commandes, instantané) pèse deux fois plus, à durée audio égale.
    func testRenderLoadAt16xWith128Frames_NFR3() {
        measureLoad(bufferFrames: 128)
    }

    /// Rend 2,13 s de son à `bufferFrames` trames par tampon, après 0,53 s de montée à 16×.
    private func measureLoad(bufferFrames frames: Int, file: StaticString = #filePath, line: UInt = #line) {
        let engine = ScratchEngine()
        engine.send(.load(.a, TestClips.noise(frames: 48_000 * 60)))
        engine.send(.load(.b, TestClips.noise(frames: 48_000 * 60)))
        engine.send(.seek(.a, seconds: 5))
        engine.send(.seek(.b, seconds: 55))
        let speed = 16 * TurntableConstants.referenceAngularVelocity * 1.05 // saturates at 16×
        let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer {
            left.deallocate()
            right.deallocate()
        }
        var buffer = 0
        func renderBuffer() {
            let time = Double(buffer * frames) / 48_000
            if buffer == 0 {
                engine.send(.touchBegan(.a, angle: 0, time: 0))
                engine.send(.touchBegan(.b, angle: 0, time: 0))
            } else {
                engine.send(.touchMoved(.a, angle: speed * time, time: time))
                engine.send(.touchMoved(.b, angle: -speed * time, time: time))
            }
            engine.render(frameCount: frames, left: left, right: right)
            buffer += 1
        }
        for _ in 0..<(100 * 256 / frames) { renderBuffer() } // warm-up and spin-up to 16×
        let snapshot = engine.latestSnapshot()
        XCTAssertEqual(snapshot[.a].playbackRate, 16, accuracy: 0.01, "deck A at 16×", file: file, line: line)
        XCTAssertEqual(snapshot[.b].playbackRate, -16, accuracy: 0.01, "deck B at −16×", file: file, line: line)

        let buffers = 400 * 256 / frames
        let clock = ContinuousClock()
        let elapsed = clock.measure { for _ in 0..<buffers { renderBuffer() } }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
        let perBuffer = seconds / Double(buffers)
        let load = perBuffer / (Double(frames) / 48_000) * 100
        XCTAssertEqual(abs(engine.latestSnapshot()[.a].playbackRate), 16, accuracy: 0.01, file: file, line: line)
        #if os(macOS)
        let system = "macOS"
        #else
        let system = "Linux"
        #endif
        RenderMetricsLog.write(String(format: "NFR3 — 2 platines à 16× : %.1f µs par tampon de %ld trames = %.1f %% (build %@, %@)",
                                      perBuffer * 1e6, frames, load, RenderMetricsLog.configuration, system))
        XCTAssertTrue(load.isFinite, file: file, line: line)
        if !RenderMetricsLog.isDebugBuild {
            XCTAssertLessThanOrEqual(load, 30, "NFR3: at most 30 % of the buffer duration", file: file, line: line)
        }
    }
}
