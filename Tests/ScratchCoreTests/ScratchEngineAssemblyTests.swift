import Foundation
import XCTest
@testable import ScratchCore

/// Banc de rendu direct d'un `ScratchEngine` (tampons de 256 trames à 48 kHz).
private final class EngineRig {
    let engine: ScratchEngine
    private var left = [Float](repeating: 0, count: 4_096)
    private var right = [Float](repeating: 0, count: 4_096)
    private(set) var frames = 0

    struct Output {
        var left: [Float] = []
        var right: [Float] = []
        var snapshots: [EngineSnapshot] = []
    }

    init(engine: ScratchEngine = ScratchEngine()) { self.engine = engine }

    var time: Double { Double(frames) / 48_000 }
    var snapshot: EngineSnapshot { engine.latestSnapshot() }

    @discardableResult
    func render(_ count: Int = 256) -> Output {
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                engine.render(frameCount: count, left: l.baseAddress!, right: r.baseAddress!)
            }
        }
        frames += count
        return Output(left: Array(left[..<count]), right: Array(right[..<count]), snapshots: [engine.latestSnapshot()])
    }

    /// Rend `seconds` par tampons de `block`, en envoyant `perBuffer(time)` avant chaque tampon.
    @discardableResult
    func run(seconds: Double, block: Int = 256, perBuffer: ((Double) -> Void)? = nil) -> Output {
        var output = Output()
        let buffers = Int((seconds * 48_000 / Double(block)).rounded())
        for _ in 0..<buffers {
            perBuffer?(time)
            let rendered = render(block)
            output.left += rendered.left
            output.right += rendered.right
            output.snapshots += rendered.snapshots
        }
        return output
    }
}

/// Assemblage du moteur (story 1.5 ; SF-03, SF-06 à SF-10, SF-13, SF-15, SF-64, SF-69, SF-71,
/// RM-01, RM-03, RM-13, RM-51, RM-56, RM-57).
final class ScratchEngineAssemblyTests: XCTestCase {
    private let reference = TurntableConstants.referenceAngularVelocity

    private func wrapped(_ angle: Double) -> Double {
        let value = angle.truncatingRemainder(dividingBy: 2 * .pi)
        let positive = value < 0 ? value + 2 * .pi : value
        return min(positive, 2 * .pi - positive)
    }

    /// CA1 : commandes appliquées au début de l'appel, un instantané par appel ; un tampon de plus de
    /// 512 trames (deux blocs) donne la même sortie que deux tampons de 512, et ses mesures couvrent
    /// les deux blocs.
    func testRenderDrainsCommandsAndPublishesOneSnapshotPerCall() {
        func makeRig() -> EngineRig {
            let rig = EngineRig()
            rig.engine.send(.load(.a, TestClips.sine(frequency: 1_000, seconds: 10, amplitude: 0.5)))
            rig.engine.send(.motor(.a, on: true))
            rig.render(512)
            return rig
        }
        let long = makeRig()
        let short = makeRig()
        XCTAssertTrue(long.snapshot[.a].motorOn, "commands applied by the first render")
        long.engine.send(.lineFader(.a, 0.5))
        short.engine.send(.lineFader(.a, 0.5))
        let one = long.render(1_024)
        let first = short.render(512)
        let second = short.render(512)
        XCTAssertEqual(one.left, first.left + second.left, "a 1 024-frame buffer equals two 512-frame buffers")
        XCTAssertEqual(long.snapshot.sampleTime, 1_536)
        XCTAssertEqual(long.snapshot[.a].positionSeconds, short.snapshot[.a].positionSeconds)
        let firstPeak = first.snapshots[0][.a].peakLevel
        let secondPeak = second.snapshots[0][.a].peakLevel
        XCTAssertEqual(long.snapshot[.a].peakLevel, max(firstPeak, secondPeak), "meters cover both blocks")
        XCTAssertEqual(long.snapshot.mixer.outputPeak, max(first.snapshots[0].mixer.outputPeak, second.snapshots[0].mixer.outputPeak))
        XCTAssertGreaterThan(firstPeak, 0)
    }

    /// CA2 — SF-64, RM-51 (6.8 « Scratcher A pendant que B joue ») : instantané et signal de B
    /// identiques à l'échantillon près, qu'on scratche A ou non (voie A fermée au crossfader).
    func testDeckBIsBitIdenticalWhetherOrNotAIsScratched_RM51() {
        func makeRig() -> EngineRig {
            let rig = EngineRig()
            rig.engine.send(.load(.a, TestClips.sine(frequency: 700, seconds: 20)))
            rig.engine.send(.load(.b, TestClips.sine(frequency: 300, seconds: 20, amplitude: 0.7)))
            rig.engine.send(.motor(.a, on: true))
            rig.engine.send(.motor(.b, on: true))
            rig.engine.send(.crossfader(1)) // only B reaches the output
            return rig
        }
        let quiet = makeRig()
        let scratched = makeRig()
        let a = quiet.run(seconds: 1.5)
        var angle = 0.0
        let b = scratched.run(seconds: 1.5) { time in
            if time == 0 { scratched.engine.send(.touchBegan(.a, angle: 0, time: 0)) }
            angle = 6 * sin(2 * .pi * 3 * time)
            scratched.engine.send(.touchMoved(.a, angle: angle, time: time))
            scratched.engine.send(.setCue(.a))
            scratched.engine.send(.pitch(.a, 0.05))
        }
        XCTAssertEqual(a.left, b.left, "B's signal is bit-identical")
        XCTAssertEqual(a.right, b.right)
        // Each rig loads its own clips: compare everything but the clip identifier.
        func deckB(_ output: EngineRig.Output) -> [DeckSnapshot] {
            output.snapshots.map { snapshot in
                var deck = snapshot[.b]
                deck.clipID = nil
                return deck
            }
        }
        XCTAssertEqual(deckB(a), deckB(b), "B's snapshot is identical")
        XCTAssertNotEqual(a.snapshots.last?[.a], b.snapshots.last?[.a], "A was really scratched")
    }

    /// CA3 — SF-03, SF-13, RM-57 (scénario « Même son sur A et B ») : un même clip sur A et B, sans
    /// copie ; positions, moteurs et CUE propres ; libéré seulement après déchargement des deux
    /// platines et `drainReleasedClips()`.
    func testLoadInitialStateAndSharedClip_SF03_RM57() {
        let rig = EngineRig()
        weak var weakClip: AudioClip?
        do {
            let clip = TestClips.sine(frequency: 440, seconds: 4)
            weakClip = clip
            rig.engine.send(.motor(.a, on: true))
            rig.engine.send(.seek(.a, seconds: 2))
            rig.engine.send(.load(.a, clip))
            rig.engine.send(.load(.b, clip))
        }
        rig.render()
        for deck in DeckID.allCases {
            let state = rig.snapshot[deck]
            XCTAssertEqual(state.positionSeconds, 0)
            XCTAssertFalse(state.motorOn)
            XCTAssertNil(state.cueSeconds)
            XCTAssertEqual(wrapped(state.stickerAngle), 0, accuracy: 1e-12, "sticker aligned")
        }
        XCTAssertEqual(rig.snapshot[.a].clipID, rig.snapshot[.b].clipID)
        rig.engine.send(.motor(.a, on: true))
        rig.run(seconds: 1)
        rig.engine.send(.setCue(.a))
        rig.render()
        XCTAssertGreaterThan(rig.snapshot[.a].positionSeconds, 0.3)
        XCTAssertEqual(rig.snapshot[.b].positionSeconds, 0, "B stays at 0 s")
        XCTAssertNotNil(rig.snapshot[.a].cueSeconds)
        XCTAssertNil(rig.snapshot[.b].cueSeconds, "SET CUE on A creates no CUE on B")
        rig.engine.send(.unload(.a))
        rig.run(seconds: 0.05)
        XCTAssertEqual(rig.engine.drainReleasedClips(), 1)
        XCTAssertNotNil(weakClip, "still loaded on B")
        rig.engine.send(.unload(.b))
        rig.run(seconds: 0.05)
        XCTAssertNotNil(weakClip, "never released by the audio thread")
        XCTAssertEqual(rig.engine.drainReleasedClips(), 1)
        XCTAssertNil(weakClip)
    }

    /// SF-15, note de QA de la 1.3 (#23) : remplacer le son d'une platine en lecture ne coupe pas net ;
    /// l'ancien son s'efface en 5 ms et le clip ne revient au fil de contrôle qu'après ce fondu.
    func testReplacingAPlayingSoundFadesOut_SF15() {
        let rig = EngineRig()
        rig.engine.send(.slipmatCatchUp(0))
        rig.engine.send(.load(.a, TestClips.sine(frequency: 1_000, seconds: 10, amplitude: 0.9)))
        rig.engine.send(.motor(.a, on: true))
        rig.run(seconds: 1.2)
        let before = rig.render(256)
        rig.engine.send(.load(.a, TestClips.sine(frequency: 1_000, seconds: 10)))
        let fading = rig.render(128)
        XCTAssertEqual(rig.engine.drainReleasedClips(), 0, "kept on the audio thread during the fade")
        let faded = rig.render(256)
        XCTAssertEqual(rig.engine.drainReleasedClips(), 1, "returned once faded")
        let signal = before.left + fading.left + faded.left
        let natural = 2 * Double.pi * 1_000 / 48_000 * 0.9
        XCTAssertLessThanOrEqual(SignalAnalysis.maximumStep(signal), natural + 0.9 * .pi / 2 / 240 * 1.05, "no cut")
        XCTAssertGreaterThan(SignalAnalysis.peak(fading.left[..<48]), 0.5, "still audible right after the load")
        XCTAssertTrue(faded.left[(240 - 128)...].allSatisfy { $0 == 0 }, "silent after 5 ms (new deck stopped)")
        XCTAssertFalse(rig.snapshot[.a].motorOn)
    }

    /// CA3 — RM-01 (6.2 « Démarrer sans fichier ») : une platine vide n'émet aucun son, plateau en
    /// rotation.
    func testEmptyDeckIsSilentWithSpinningPlatter_RM01() {
        let rig = EngineRig()
        rig.engine.send(.motor(.a, on: true))
        rig.engine.send(.motor(.b, on: true))
        let output = rig.run(seconds: 1)
        XCTAssertTrue(output.left.allSatisfy { $0 == 0 } && output.right.allSatisfy { $0 == 0 })
        XCTAssertGreaterThan(rig.snapshot[.a].platterAngle, 1)
        XCTAssertTrue(rig.snapshot[.a].motorOn)
    }

    /// CA4 — SF-06 à SF-10, RM-03, RM-60 : le toucher retient le disque malgré le moteur, un second
    /// `touchBegan` est ignoré, le relâchement rattrape le plateau.
    func testTouchHasPriorityOverMotor_RM03() {
        let rig = EngineRig()
        rig.engine.send(.load(.a, TestClips.sine(frequency: 440, seconds: 20)))
        rig.engine.send(.motor(.a, on: true))
        rig.run(seconds: 1.2)
        XCTAssertEqual(rig.snapshot[.a].playbackRate, 1, accuracy: 1e-6)
        let start = rig.time
        rig.engine.send(.touchBegan(.a, angle: 0, time: start))
        rig.run(seconds: 0.5) { time in rig.engine.send(.touchMoved(.a, angle: 0, time: time)) }
        XCTAssertTrue(rig.snapshot[.a].isHeld)
        XCTAssertTrue(rig.snapshot[.a].motorOn, "the touch never stops the motor")
        XCTAssertEqual(rig.snapshot[.a].playbackRate, 0, accuracy: 1e-3, "the disc is held still")
        let held = rig.snapshot[.a].positionSeconds
        rig.engine.send(.touchBegan(.a, angle: 5, time: rig.time)) // second finger: ignored
        rig.run(seconds: 0.2) { time in rig.engine.send(.touchMoved(.a, angle: 0, time: time)) }
        XCTAssertEqual(rig.snapshot[.a].positionSeconds, held, accuracy: 1e-6)
        rig.engine.send(.touchEnded(.a, time: rig.time))
        rig.run(seconds: 0.3)
        XCTAssertFalse(rig.snapshot[.a].isHeld)
        XCTAssertEqual(rig.snapshot[.a].playbackRate, 1, accuracy: 1e-3, "caught up with the platter")
    }

    /// CA5 — SF-13 (scénario « Rappel du CUE disque tenu », 6.6) : CUE à 12 s, disque tenu à 20 s,
    /// rappel : 12 s avec fondu ≤ 5 ms, disque toujours tenu ; un quart de tour → 12,45 s ± 10 ms. SET
    /// CUE disque tenu mémorise la position courante.
    func testCueWhileHeldReanchorsGesture_SF13() {
        let rig = EngineRig()
        rig.engine.send(.load(.a, TestClips.sine(frequency: 440, seconds: 30)))
        rig.engine.send(.seek(.a, seconds: 12))
        rig.engine.send(.setCue(.a))
        rig.engine.send(.seek(.a, seconds: 20))
        rig.render()
        let start = rig.time
        rig.engine.send(.touchBegan(.a, angle: 0, time: start))
        rig.run(seconds: 0.2) { time in rig.engine.send(.touchMoved(.a, angle: 0, time: time)) }
        XCTAssertEqual(rig.snapshot[.a].positionSeconds, 20, accuracy: 1e-9)
        rig.engine.send(.recallCue(.a))
        rig.render()
        XCTAssertEqual(rig.snapshot[.a].positionSeconds, 12, accuracy: 1e-9)
        XCTAssertTrue(rig.snapshot[.a].isHeld, "the disc stays held")
        let moveStart = rig.time
        rig.run(seconds: 1) { time in
            let angle = Double.pi / 2 * min(1, max(0, time - moveStart) / 0.3)
            rig.engine.send(.touchMoved(.a, angle: angle, time: time))
        }
        XCTAssertEqual(rig.snapshot[.a].positionSeconds, 12.45, accuracy: 0.010, "the gesture continues from the CUE")
        rig.engine.send(.setCue(.a))
        rig.render()
        XCTAssertEqual(rig.snapshot[.a].cueSeconds ?? 0, rig.snapshot[.a].positionSeconds, accuracy: 1e-6,
                       "SET CUE while held stores the current position")
        XCTAssertTrue(rig.snapshot[.a].isHeld)
    }

    /// CA6 — SF-71 (6.11 « Needle drop ignoré pendant que je retiens le disque », « Positionner la
    /// tête ») : ignoré disque tenu ; sinon fondu ≤ 5 ms, état du moteur inchangé, aucun clic.
    func testSeekIgnoredWhileHeldAndSmoothed_SF71() {
        let rig = EngineRig()
        rig.engine.send(.slipmatCatchUp(0))
        rig.engine.send(.load(.a, TestClips.sine(frequency: 1_000, seconds: 30, amplitude: 0.8)))
        rig.engine.send(.motor(.a, on: true))
        rig.run(seconds: 1.2)
        let before = rig.render()
        rig.engine.send(.seek(.a, seconds: 10.000_5)) // half a period away: phase opposition
        let after = rig.run(seconds: 0.02)
        XCTAssertEqual(after.snapshots[0][.a].positionSeconds, 10.000_5 + 256 / 48_000.0, accuracy: 1e-6)
        XCTAssertTrue(rig.snapshot[.a].motorOn, "the motor state is unchanged")
        let natural = 2 * Double.pi * 1_000 / 48_000 * 0.8
        XCTAssertLessThanOrEqual(SignalAnalysis.maximumStep(before.left + after.left), natural * 1.6, "no click")

        let start = rig.time
        rig.engine.send(.touchBegan(.a, angle: 0, time: start))
        rig.run(seconds: 0.6) { time in rig.engine.send(.touchMoved(.a, angle: 0, time: time)) }
        let held = rig.snapshot[.a].positionSeconds
        rig.engine.send(.seek(.a, seconds: 3))
        rig.render()
        XCTAssertEqual(rig.snapshot[.a].positionSeconds, held, accuracy: 1e-6, "ignored while held")
    }

    /// CA7 — SF-69, RM-13, D-10 (6.11 « Le repère reste aligné après un saut de position ») : CUE à 4 s,
    /// needle drop à 30 s puis CUE → tête à 4 s et repère sous la position de lecture ; en lecture, le
    /// repère repasse sous la tête à chaque tour depuis le CUE ; à la sortie du sillon fermé aussi.
    func testStickerUnderPlayheadAtCue_SF69_IC09() {
        let rig = EngineRig()
        rig.engine.send(.slipmatCatchUp(0))
        rig.engine.send(.load(.a, TestClips.sine(frequency: 440, seconds: 40)))
        rig.engine.send(.seek(.a, seconds: 4))
        rig.engine.send(.setCue(.a))
        rig.engine.send(.seek(.a, seconds: 30))
        rig.render()
        rig.engine.send(.recallCue(.a))
        rig.render()
        XCTAssertEqual(rig.snapshot[.a].positionSeconds, 4)
        XCTAssertEqual(wrapped(rig.snapshot[.a].stickerAngle), 0, accuracy: 1e-9, "sticker under the playhead")
        // Playing: sticker ≡ 2π (p − cue) / 1.8 at every buffer.
        rig.engine.send(.motor(.a, on: true))
        let playing = rig.run(seconds: 2)
        let largest = playing.snapshots.map { wrapped($0[.a].stickerAngle - 2 * .pi * ($0[.a].positionSeconds - 4) / 1.8) }.max() ?? 1
        XCTAssertLessThan(largest, 1e-9)
        // Closed groove, then back into the sound: realigned at the exit.
        rig.engine.send(.seek(.a, seconds: 39.9))
        rig.run(seconds: 1.5)
        XCTAssertTrue(rig.snapshot[.a].isAtEnd)
        let start = rig.time
        rig.engine.send(.touchBegan(.a, angle: 0, time: start))
        rig.run(seconds: 0.6) { time in
            rig.engine.send(.touchMoved(.a, angle: -Double.pi * min(1, (time - start) / 0.3), time: time))
        }
        let state = rig.snapshot[.a]
        XCTAssertLessThan(state.positionSeconds, 40)
        XCTAssertEqual(wrapped(state.stickerAngle - 2 * .pi * (state.positionSeconds - 4) / 1.8), 0, accuracy: 1e-9)
    }

    /// CA8 — RM-56 : `stopAllMotors` arrête les deux moteurs sans rampe, positions conservées ; un
    /// disque tenu reste tenu.
    func testStopAllMotorsWithoutRamp_RM56() {
        let rig = EngineRig()
        rig.engine.send(.load(.a, TestClips.sine(frequency: 440, seconds: 20)))
        rig.engine.send(.load(.b, TestClips.sine(frequency: 220, seconds: 20)))
        rig.engine.send(.motor(.a, on: true))
        rig.engine.send(.motor(.b, on: true))
        rig.run(seconds: 1.2)
        let start = rig.time
        rig.engine.send(.touchBegan(.b, angle: 0, time: start))
        rig.run(seconds: 0.3) { time in rig.engine.send(.touchMoved(.b, angle: 0, time: time)) }
        let positionA = rig.snapshot[.a].positionSeconds
        rig.engine.send(.stopAllMotors)
        rig.render()
        let state = rig.snapshot
        XCTAssertFalse(state[.a].motorOn)
        XCTAssertFalse(state[.b].motorOn)
        XCTAssertEqual(state[.a].playbackRate, 0, "no ramp")
        XCTAssertEqual(state[.a].positionSeconds, positionA, accuracy: 1e-12, "position kept")
        XCTAssertTrue(state[.b].isHeld, "a held disc stays held")
        rig.run(seconds: 0.5)
        XCTAssertEqual(rig.snapshot[.a].positionSeconds, positionA, accuracy: 1e-12)
    }

    /// Fils (architecture §3.1) : un fil de rendu et un fil de contrôle en parallèle (commandes,
    /// instantanés, retour des clips) ; tous les clips reviennent. Relancé sous ThreadSanitizer.
    func testConcurrentControlAndRenderThreads() {
        let engine = ScratchEngine()
        let done = DispatchSemaphore(value: 0)
        let stop = ManagedFlag()
        let renderThread = Thread {
            let left = UnsafeMutablePointer<Float>.allocate(capacity: 256)
            let right = UnsafeMutablePointer<Float>.allocate(capacity: 256)
            while !stop.isSet { engine.render(frameCount: 256, left: left, right: right) }
            left.deallocate()
            right.deallocate()
            done.signal()
        }
        renderThread.start()
        weak var lastClip: AudioClip?
        var released = 0
        var rejected = 0
        for index in 0..<300 {
            let clip = TestClips.sine(frequency: 440, seconds: 0.5)
            lastClip = clip
            if !engine.send(.load(index % 2 == 0 ? .a : .b, clip)) { rejected += 1 }
            _ = engine.send(.motor(.a, on: true))
            _ = engine.send(.touchMoved(.b, angle: Double(index), time: Double(index) / 100))
            _ = engine.latestSnapshot()
            released += engine.drainReleasedClips()
            usleep(200)
        }
        stop.set()
        done.wait()
        engine.send(.unload(.a))
        engine.send(.unload(.b))
        engine.pump()
        released += engine.drainReleasedClips()
        XCTAssertEqual(released + rejected, 300, "every clip comes back through the release queue")
        XCTAssertNil(lastClip)
    }
}

/// Drapeau partagé entre deux fils de test.
private final class ManagedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}
