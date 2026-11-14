import XCTest
@testable import ScratchCore

/// Contrat du moteur minimal (story 0.2) : les commandes sont appliquées par le rendu et
/// reflétées dans l'instantané ; le rendu produit du silence ; les clips reviennent au fil de
/// contrôle.
final class ScratchEngineTests: XCTestCase {
    private var left = [Float](repeating: 1, count: 1024)
    private var right = [Float](repeating: 1, count: 1024)

    private func render(_ engine: ScratchEngine, frames: Int = 256) {
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                engine.render(frameCount: frames, left: l.baseAddress!, right: r.baseAddress!)
            }
        }
    }

    private func makeClip(seconds: Double = 4, rate: Double = 44_100) -> AudioClip {
        AudioClip(title: "test", sampleRate: rate, frameCount: Int(seconds * rate)) { _, _ in }
    }

    func testMotorCommandIsReflectedInSnapshotAfterRender() {
        let engine = ScratchEngine()
        XCTAssertFalse(engine.latestSnapshot()[.a].motorOn)
        XCTAssertTrue(engine.send(.motor(.a, on: true)))
        XCTAssertFalse(engine.latestSnapshot()[.a].motorOn, "nothing changes before the audio thread runs")
        render(engine)
        XCTAssertTrue(engine.latestSnapshot()[.a].motorOn)
    }

    /// RM-51 : une commande d'une platine ne modifie jamais l'autre.
    func testDecksAreIndependent_RM51() {
        let engine = ScratchEngine()
        engine.send(.motor(.b, on: true))
        engine.send(.pitch(.a, 0.04))
        engine.send(.speed(.a, .rpm45))
        engine.send(.resistance(.a, 0.75))
        render(engine)
        let snapshot = engine.latestSnapshot()
        XCTAssertFalse(snapshot[.a].motorOn)
        XCTAssertTrue(snapshot[.b].motorOn)
        XCTAssertEqual(snapshot[.a].pitch, 0.04)
        XCTAssertEqual(snapshot[.b].pitch, 0)
        XCTAssertEqual(snapshot[.a].speed, .rpm45)
        XCTAssertEqual(snapshot[.b].speed, .rpm33)
        XCTAssertEqual(snapshot[.a].resistance, 0.75)
        XCTAssertEqual(snapshot[.b].resistance, TurntableConstants.defaultResistance)
    }

    func testRenderProducesSilenceAndAdvancesSampleTime() {
        let engine = ScratchEngine()
        engine.send(.load(.a, makeClip()))
        engine.send(.motor(.a, on: true))
        render(engine, frames: 1000)
        XCTAssertTrue(left[0..<1000].allSatisfy { $0 == 0 })
        XCTAssertTrue(right[0..<1000].allSatisfy { $0 == 0 })
        XCTAssertEqual(left[1000], 1, "render must not write past frameCount")
        XCTAssertEqual(engine.latestSnapshot().sampleTime, 1000)
    }

    /// SF-03 : après chargement, son chargé, tête à 0 s, moteur arrêté, CUE effacé.
    func testLoadResetsDeckToInitialState_SF03() {
        let engine = ScratchEngine()
        let clip = makeClip(seconds: 4)
        engine.send(.motor(.a, on: true))
        engine.send(.seek(.a, seconds: 0))
        engine.send(.setCue(.a))
        engine.send(.load(.a, clip))
        render(engine)
        let deck = engine.latestSnapshot()[.a]
        XCTAssertTrue(deck.isLoaded)
        XCTAssertEqual(deck.clipID, clip.id)
        XCTAssertEqual(deck.durationSeconds, 4, accuracy: 1e-9)
        XCTAssertEqual(deck.positionSeconds, 0)
        XCTAssertFalse(deck.motorOn)
        XCTAssertNil(deck.cueSeconds)
        XCTAssertFalse(engine.latestSnapshot()[.b].isLoaded)
    }

    /// Le clip remplacé n'est jamais libéré par le fil audio : il attend `drainReleasedClips()`.
    func testReplacedClipIsReleasedOnlyByDrain() {
        let engine = ScratchEngine()
        weak var weakClip: AudioClip?
        do {
            let clip = makeClip()
            weakClip = clip
            engine.send(.load(.a, clip))
        }
        render(engine)
        XCTAssertNotNil(weakClip, "the engine retains the loaded clip")
        engine.send(.unload(.a))
        render(engine)
        XCTAssertFalse(engine.latestSnapshot()[.a].isLoaded)
        XCTAssertNotNil(weakClip, "the audio thread must not release the clip")
        XCTAssertEqual(engine.drainReleasedClips(), 1)
        XCTAssertNil(weakClip, "the clip is freed on the control thread")
    }

    /// RM-57 : le même son peut être chargé sur les deux platines.
    func testSameClipOnBothDecks_RM57() {
        let engine = ScratchEngine()
        let clip = makeClip()
        engine.send(.load(.a, clip))
        engine.send(.load(.b, clip))
        render(engine)
        XCTAssertEqual(engine.latestSnapshot()[.a].clipID, clip.id)
        XCTAssertEqual(engine.latestSnapshot()[.b].clipID, clip.id)
    }

    func testPendingCommandsAndLoadedClipsAreReleasedWithTheEngine() {
        weak var weakLoaded: AudioClip?
        weak var weakPending: AudioClip?
        do {
            let engine = ScratchEngine()
            let loaded = makeClip()
            let pending = makeClip()
            weakLoaded = loaded
            weakPending = pending
            engine.send(.load(.a, loaded))
            render(engine)
            engine.send(.load(.b, pending))
        }
        XCTAssertNil(weakLoaded)
        XCTAssertNil(weakPending)
    }

    func testFullQueueRejectsCommandAndKeepsClipBalance() {
        let engine = ScratchEngine()
        var accepted = 0
        while engine.send(.crossfader(0.25)) { accepted += 1 }
        XCTAssertGreaterThanOrEqual(accepted, ScratchEngine.commandCapacity)
        weak var weakClip: AudioClip?
        do {
            let clip = makeClip()
            weakClip = clip
            XCTAssertFalse(engine.send(.load(.a, clip)))
        }
        XCTAssertNil(weakClip, "a rejected load must not leak the clip")
        render(engine)
        XCTAssertTrue(engine.send(.crossfader(0.75)))
    }

    /// SF-13 : CUE sans point mémorisé ramène à 0 s ; SET CUE mémorise la position.
    func testCueAndSeek_SF13_SF71() {
        let engine = ScratchEngine()
        engine.send(.load(.a, makeClip(seconds: 30)))
        engine.send(.seek(.a, seconds: 12))
        render(engine)
        XCTAssertEqual(engine.latestSnapshot()[.a].positionSeconds, 12)
        engine.send(.setCue(.a))
        engine.send(.seek(.a, seconds: 20))
        render(engine)
        XCTAssertEqual(engine.latestSnapshot()[.a].cueSeconds, 12)
        XCTAssertEqual(engine.latestSnapshot()[.a].positionSeconds, 20)
        engine.send(.recallCue(.a))
        render(engine)
        XCTAssertEqual(engine.latestSnapshot()[.a].positionSeconds, 12)

        engine.send(.load(.a, makeClip(seconds: 30)))
        engine.send(.seek(.a, seconds: 5))
        engine.send(.recallCue(.a))
        render(engine)
        XCTAssertEqual(engine.latestSnapshot()[.a].positionSeconds, 0, "without CUE, CUE recalls 0 s")
    }

    /// SF-14 : la tête reste dans [−2 s ; durée].
    func testSeekIsClampedToLeadInAndDuration_SF14() {
        let engine = ScratchEngine()
        engine.send(.load(.a, makeClip(seconds: 4)))
        engine.send(.seek(.a, seconds: -10))
        render(engine)
        XCTAssertEqual(engine.latestSnapshot()[.a].positionSeconds, -2)
        XCTAssertTrue(engine.latestSnapshot()[.a].isInLeadIn)
        engine.send(.seek(.a, seconds: 99))
        render(engine)
        XCTAssertEqual(engine.latestSnapshot()[.a].positionSeconds, 4, accuracy: 1e-9)
        XCTAssertTrue(engine.latestSnapshot()[.a].isAtEnd)
    }

    /// SF-71 : needle drop ignoré disque tenu ; RM-60 : touchBegan saisit, touchEnded relâche
    /// (après le retard de rejeu du doigt).
    func testTouchHoldsDiscAndBlocksNeedleDrop_SF71_RM60() {
        let engine = ScratchEngine()
        engine.send(.load(.a, makeClip(seconds: 30)))
        engine.send(.touchBegan(.a, angle: 0, time: 100))
        engine.send(.seek(.a, seconds: 10))
        render(engine)
        XCTAssertTrue(engine.latestSnapshot()[.a].isHeld)
        XCTAssertEqual(engine.latestSnapshot()[.a].positionSeconds, 0, "needle drop is ignored while held")
        engine.send(.touchEnded(.a, time: 100.01))
        for _ in 0..<20 { render(engine) } // ≈ 107 ms > playout delay
        XCTAssertFalse(engine.latestSnapshot()[.a].isHeld)
    }

    /// IC-09, SF-69 : après chaque saut, `discAngle ≡ 2π × position / 1,8` et le repère
    /// (`stickerAngle = discAngle − 2π × CUE / 1,8`) passe sous la tête quand la tête est au CUE.
    func testStickerIsUnderThePlayheadAtCueAfterJumps_SF69_IC09() {
        let twoPi = 2 * Double.pi
        func wrapped(_ angle: Double) -> Double {
            let value = angle.truncatingRemainder(dividingBy: twoPi)
            return value < 0 ? value + twoPi : value
        }
        func distanceToNoon(_ angle: Double) -> Double {
            let value = wrapped(angle)
            return min(value, twoPi - value)
        }
        let engine = ScratchEngine()
        engine.send(.load(.a, makeClip(seconds: 30)))
        render(engine)
        XCTAssertEqual(distanceToNoon(engine.latestSnapshot()[.a].stickerAngle), 0, accuracy: 1e-9,
                       "after load, the head is at 0 s: sticker at noon")

        engine.send(.seek(.a, seconds: 0.9)) // half a turn
        render(engine)
        var deck = engine.latestSnapshot()[.a]
        XCTAssertEqual(wrapped(deck.discAngle), Double.pi, accuracy: 1e-9)
        XCTAssertEqual(distanceToNoon(deck.stickerAngle), Double.pi, accuracy: 1e-9, "half a turn away from the CUE")

        engine.send(.setCue(.a))
        render(engine)
        deck = engine.latestSnapshot()[.a]
        XCTAssertEqual(distanceToNoon(deck.stickerAngle), 0, accuracy: 1e-9, "head at the CUE: sticker at noon")

        engine.send(.seek(.a, seconds: 17.3))
        engine.send(.recallCue(.a))
        render(engine)
        deck = engine.latestSnapshot()[.a]
        XCTAssertEqual(deck.positionSeconds, 0.9, accuracy: 1e-12)
        XCTAssertEqual(distanceToNoon(deck.stickerAngle), 0, accuracy: 1e-9, "recalled CUE: sticker at noon")
        XCTAssertEqual(deck.stickerAngle, deck.discAngle - twoPi * 0.9 / 1.8, accuracy: 1e-12)
    }

    func testValuesAreClampedAndNonFiniteValuesIgnored() {
        let engine = ScratchEngine()
        engine.send(.pitch(.a, 0.5))
        engine.send(.resistance(.a, -1))
        engine.send(.crossfader(.nan))
        engine.send(.lineFader(.b, 2))
        engine.send(.startDuration(10))
        engine.send(.slipmatCatchUp(-1))
        engine.send(.outputSampleRate(.infinity))
        render(engine)
        let snapshot = engine.latestSnapshot()
        XCTAssertEqual(snapshot[.a].pitch, TurntableConstants.pitchRange.upperBound)
        XCTAssertEqual(snapshot[.a].resistance, 0)
        XCTAssertEqual(snapshot.mixer.crossfader, TurntableConstants.defaultCrossfader)
        XCTAssertEqual(snapshot.mixer.lineFaders.b, 1)
        XCTAssertEqual(snapshot.motorTimings.startDuration, TurntableConstants.motorDurationRange.upperBound)
        XCTAssertEqual(snapshot.motorTimings.slipmatCatchUp, 0)
        XCTAssertEqual(snapshot.outputSampleRate, 48_000)
    }

    func testMixerCommandsAreReflected() {
        let engine = ScratchEngine()
        engine.send(.crossfader(1))
        engine.send(.crossfaderCurve(0))
        engine.send(.hamster(true))
        engine.send(.lineFader(.a, 0.5))
        engine.send(.momentaryCut(.b, open: true))
        engine.send(.outputSampleRate(44_100))
        engine.send(.touchMoved(.a, angle: 1, time: 1, predicted: true))
        render(engine)
        let snapshot = engine.latestSnapshot()
        XCTAssertEqual(snapshot.mixer.crossfader, 1)
        XCTAssertEqual(snapshot.mixer.crossfaderCurve, 0)
        XCTAssertTrue(snapshot.mixer.hamster)
        XCTAssertEqual(snapshot.mixer.lineFaders, DeckPair(a: 0.5, b: 1))
        XCTAssertEqual(snapshot.mixer.momentaryCuts, DeckPair(a: false, b: true))
        XCTAssertEqual(snapshot.outputSampleRate, 44_100)
    }

    /// RM-56 : STOP immédiat des deux moteurs, positions conservées.
    func testStopAllMotors_RM56() {
        let engine = ScratchEngine()
        engine.send(.load(.a, makeClip(seconds: 30)))
        engine.send(.seek(.a, seconds: 7))
        engine.send(.motor(.a, on: true))
        engine.send(.motor(.b, on: true))
        render(engine)
        // One block of motor start-up (5.3 ms of a 0.7 s ramp) moves the head by about 2 µs.
        let positionAtStop = engine.latestSnapshot()[.a].positionSeconds
        XCTAssertEqual(positionAtStop, 7, accuracy: 1e-4)
        engine.send(.stopAllMotors)
        render(engine)
        render(engine)
        let snapshot = engine.latestSnapshot()
        XCTAssertFalse(snapshot[.a].motorOn)
        XCTAssertFalse(snapshot[.b].motorOn)
        XCTAssertEqual(snapshot[.a].positionSeconds, positionAtStop, "positions are kept, without ramp")
        XCTAssertEqual(snapshot[.a].playbackRate, 0)
    }

    /// `pump` applique les commandes sans rendre d'audio ni avancer le temps (hôte arrêté, SF-82).
    func testPumpAppliesCommandsWithoutAdvancingTime() {
        let engine = ScratchEngine()
        engine.send(.crossfader(0.2))
        engine.pump()
        XCTAssertEqual(engine.latestSnapshot().mixer.crossfader, 0.2)
        XCTAssertEqual(engine.latestSnapshot().sampleTime, 0)
    }

    func testInitialSnapshotMatchesSpecDefaults() {
        let snapshot = ScratchEngine().latestSnapshot()
        XCTAssertEqual(snapshot, EngineSnapshot.initial)
        XCTAssertEqual(snapshot[.a].speed, .rpm33) // RM-02
        XCTAssertEqual(snapshot.mixer.crossfader, 0.5)
        XCTAssertEqual(snapshot.mixer.crossfaderCurve, 1)
        XCTAssertFalse(snapshot.mixer.hamster)
        XCTAssertEqual(snapshot.motorTimings, .defaults)
    }

    /// Règle temps réel : l'instantané et les commandes internes restent des types triviaux.
    func testRealtimeTypesAreTrivial() {
        XCTAssertTrue(_isPOD(EngineSnapshot.self))
        XCTAssertTrue(_isPOD(RenderCommand.self))
        XCTAssertTrue(_isPOD(Unmanaged<AudioClip>.self))
    }

    func testSnapshotActivityFlag_SF15() {
        var deck = DeckSnapshot.initial
        XCTAssertFalse(deck.isActive)
        deck.motorOn = true
        XCTAssertTrue(deck.isActive)
        deck.motorOn = false
        deck.isHeld = true
        XCTAssertTrue(deck.isActive)
        deck.isHeld = false
        deck.playbackRate = -0.5
        XCTAssertTrue(deck.isActive)
    }

    func testMixerIndicatorsAndIdleState() {
        var snapshot = EngineSnapshot.initial
        XCTAssertTrue(snapshot.isIdle)
        XCTAssertFalse(snapshot.mixer.limiterActive)
        snapshot.mixer.limiterReduction = 1.5
        snapshot.mixer.outputPeak = 1
        XCTAssertTrue(snapshot.mixer.limiterActive)
        XCTAssertTrue(snapshot.mixer.isClipping)
        XCTAssertFalse(snapshot.isIdle, "a sounding output is not idle")
        snapshot.mixer = .initial
        snapshot.decks.b.motorOn = true
        XCTAssertFalse(snapshot.isIdle)
    }

    func testRecordingEngineRecordsCommands() {
        let engine = RecordingEngine()
        engine.send(.motor(.a, on: true))
        engine.acceptsCommands = false
        XCTAssertFalse(engine.send(.motor(.b, on: true)))
        XCTAssertEqual(engine.sentCommands, [.motor(.a, on: true)])
        engine.pump()
        engine.drainReleasedClips()
        XCTAssertEqual(engine.pumpCount, 1)
        XCTAssertEqual(engine.drainCount, 1)
    }
}
