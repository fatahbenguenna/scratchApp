import Foundation
import XCTest
@testable import ScratchCore

/// Règles temps réel du rendu (story 1.5 CA 9 ; NFR2 ; architecture §6.1) : aucune allocation et
/// aucun comptage de références des clips sur le fil de rendu.
final class RealTimeAllocationTests: XCTestCase {
    private final class Probe { var value = 1 }
    /// Garde l'objet vivant hors de la mesure : l'optimiseur ne peut pas le placer sur la pile.
    private static var sink: Probe?

    /// Le compteur voit une allocation d'objet Swift faite par le fil mesuré (contrôle de l'outil).
    func testAllocationCounterSeesAllocations() throws {
        try XCTSkipUnless(AllocationCounter.isAvailable, "Swift runtime hooks unavailable")
        let counts = AllocationCounter.measure { Self.sink = Probe() }
        XCTAssertEqual(Self.sink?.value, 1)
        XCTAssertGreaterThanOrEqual(counts.allocations, 1)
        let none = AllocationCounter.measure { _ = 1 + 1 }
        XCTAssertEqual(none.allocations, 0)
    }

    /// CA9 — NFR2 (scénario « Aucune allocation ») : 10 000 rendus de 256 trames, deux platines
    /// chargées, A scratchée jusqu'à ±16× (touches réelles et prédites, reprises de geste), B à 45 tours
    /// avec pitch, CUE, needle drop, START/STOP et chargements, table de mixage en mouvement continu :
    /// aucune allocation et aucun comptage de références d'un clip sur le fil de rendu.
    func testNoAllocationOnRenderThread_NFR2() throws {
        try XCTSkipUnless(AllocationCounter.isAvailable, "Swift runtime hooks unavailable")
        let clipA = TestClips.sine(frequency: 700, seconds: 60)
        let clipB = TestClips.noise(frames: 48_000 * 30)
        let spares = [TestClips.sine(frequency: 300, seconds: 30), TestClips.noise(frames: 48_000 * 20)]
        let watched: [AnyObject] = [clipA, clipB] + spares
        let engine = ScratchEngine()
        engine.send(.load(.a, clipA))
        engine.send(.load(.b, clipB))
        engine.send(.seek(.a, seconds: 30))
        engine.send(.speed(.b, .rpm45))
        engine.send(.motor(.a, on: true))
        engine.send(.motor(.b, on: true))
        let left = UnsafeMutablePointer<Float>.allocate(capacity: 256)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: 256)
        defer {
            left.deallocate()
            right.deallocate()
        }
        for _ in 0..<20 { engine.render(frameCount: 256, left: left, right: right) }

        var total = AllocationCounter.Counts()
        var largestRate = 0.0
        var held = false
        for buffer in 0..<10_000 {
            let time = Double(buffer) * 256 / 48_000
            // Deck A: continuous scratch beyond 16× (the disc speed saturates), with predicted
            // touches, a release and a new contact every 500 buffers (some resumed mid-release).
            let angle = 8 * sin(2 * Double.pi * 1.5 * time)
            if buffer % 500 == 0 {
                engine.send(.touchBegan(.a, angle: angle, time: time))
                held = true
            } else if held {
                engine.send(.touchMoved(.a, angle: angle, time: time))
                engine.send(.touchMoved(.a, angle: angle + 0.01, time: time + 0.004, predicted: true))
            }
            if buffer % 500 == 400 {
                engine.send(.touchEnded(.a, time: time))
                held = false
            }
            // Deck B: pitch, CUE, needle drop, motor, loads.
            engine.send(.pitch(.b, 0.08 * sin(time)))
            if buffer % 300 == 0 { engine.send(.setCue(.b)) }
            if buffer % 300 == 150 { engine.send(.seek(.b, seconds: Double(buffer % 7) + 1)) }
            if buffer % 300 == 250 { engine.send(.recallCue(.b)) }
            if buffer % 1_000 == 900 { engine.send(.motor(.b, on: false)) }
            if buffer % 1_000 == 950 { engine.send(.motor(.b, on: true)) }
            if buffer % 2_500 == 2_000 { engine.send(.load(.b, spares[(buffer / 2_500) % 2])) }
            if buffer == 9_000 { engine.send(.stopAllMotors) }
            if buffer == 9_100 { engine.send(.motor(.a, on: true)) }
            // Mixer in constant motion.
            engine.send(.crossfader(0.5 + 0.5 * sin(time * 7)))
            engine.send(.lineFader(.a, 0.7 + 0.3 * sin(time * 3)))
            if buffer % 100 == 0 { engine.send(.hamster(buffer % 200 == 0)) }
            if buffer % 120 == 0 { engine.send(.crossfaderCurve(Double(buffer % 600) / 600)) }
            if buffer % 37 == 0 { engine.send(.momentaryCut(.b, open: buffer % 74 == 0)) }

            let counts = AllocationCounter.measure(watching: watched) {
                engine.render(frameCount: 256, left: left, right: right)
            }
            total.allocations += counts.allocations
            total.retains += counts.retains
            total.releases += counts.releases
            total.watchedRetains += counts.watchedRetains
            largestRate = max(largestRate, abs(engine.latestSnapshot()[.a].playbackRate))
            engine.drainReleasedClips()
        }
        XCTAssertEqual(largestRate, 16, accuracy: 1e-9, "deck A reached the ±16× bound")
        XCTAssertEqual(total.allocations, 0, "no Swift heap allocation on the render thread")
        XCTAssertEqual(total.watchedRetains, 0, "clips are never reference-counted on the render thread")
        if !RenderMetricsLog.isDebugBuild {
            XCTAssertEqual(total.retains, 0, "optimized build: no reference counting at all")
        }
        RenderMetricsLog.write("NFR2 — 10 000 rendus : \(total.allocations) allocation, \(total.watchedRetains) retenue de clip, "
            + "\(total.retains) retenues au total (build \(RenderMetricsLog.configuration))")
    }
}

/// Journal des mesures du rendu : sortie standard, et `ci-output/render-metrics.log` quand ce dossier
/// existe (CI : le rapport de la PR reprend la fin des `ci-output/*.log`).
enum RenderMetricsLog {
    /// Build de débogage (évalué à l'exécution).
    static let isDebugBuild: Bool = { _isDebugAssertConfiguration() }()
    static var configuration: String { isDebugBuild ? "debug" : "release" }

    static func write(_ line: String) {
        print(line)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("ci-output")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        let file = directory.appendingPathComponent("render-metrics.log")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
    }
}
