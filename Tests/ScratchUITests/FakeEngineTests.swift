import Foundation
import ScratchAudio
import ScratchCore
import ScratchLibrary
import XCTest
@testable import ScratchUI

/// Faux moteur des aperçus (story 4.1 CA 1, CA 2) et boucle d'affichage (CA 8).
@MainActor
final class FakeEngineTests: XCTestCase {
    private final class ManualClock: @unchecked Sendable {
        var now = 0.0
    }

    private struct EmptyLibrary: LibraryStoring {
        var entries: [LibraryEntry] { get async { [] } }
        func importFile(at url: URL) async throws -> ImportResult { throw LibraryError.unsupportedFormat }
        func reconcile() async -> [LibraryEntry] { [] }
        func delete(id: UUID) async throws { throw LibraryError.notFound }
        func url(for id: UUID) async throws -> URL { throw LibraryError.notFound }
    }

    private let clock = ManualClock()
    private lazy var engine = FakeEngine(clock: { [clock] in clock.now })

    /// Avance l'horloge de `seconds` par pas de 10 ms, un `pump()` par pas.
    private func run(_ seconds: Double) {
        for _ in 0..<Int((seconds * 100).rounded()) {
            clock.now += 0.01
            engine.pump()
        }
    }

    /// Écart angulaire ramené dans ]−π ; π].
    private func wrapped(_ angle: Double) -> Double {
        let twoPi = 2 * Double.pi
        var value = angle.truncatingRemainder(dividingBy: twoPi)
        if value > .pi { value -= twoPi } else if value <= -.pi { value += twoPi }
        return value
    }

    private func loadClip(duration: Double = 225, on deck: DeckID = .a) {
        engine.send(.load(deck, PreviewDeckIntents.syntheticClip(title: "test.wav", duration: duration)))
        engine.pump()
    }

    // AC1, AC2 — SF-04 : rampe de démarrage, plateau et disque qui tournent, tête qui avance.
    func testFakeEngineSpinsPlatterAndAdvancesPosition() async {
        loadClip()
        engine.send(.motor(.a, on: true))
        XCTAssertFalse(engine.latestSnapshot().decks.a.motorOn, "commands apply on pump, like the real engine")
        engine.pump()
        run(1.0)
        let deck = engine.latestSnapshot().decks.a
        XCTAssertTrue(deck.motorOn)
        XCTAssertEqual(deck.playbackRate, 1, accuracy: 0.01, "nominal speed reached after 0.7 s")
        XCTAssertEqual(deck.platterAngle, TurntableConstants.referenceAngularVelocity * 0.65, accuracy: 0.05)
        XCTAssertEqual(deck.positionSeconds, 0.63, accuracy: 0.05)
        XCTAssertEqual(deck.stickerAngle, deck.discAngle, "no CUE: sticker on 0 s (D-01)")
        XCTAssertEqual(wrapped(deck.discAngle - 2 * .pi * deck.positionSeconds / 1.8), 0, accuracy: 1e-9)
        XCTAssertEqual(engine.latestSnapshot().decks.b, .initial, "deck B untouched (RM-51)")
    }

    // AC2 — 6.9 « Le plateau tourne sous le disque retenu ».
    func testPlatterKeepsSpinningUnderHeldDisc_6_9() async {
        loadClip()
        engine.send(.motor(.a, on: true))
        run(1.0)
        engine.send(.touchBegan(.a, angle: 0, time: 1))
        run(0.1)
        let gripped = engine.latestSnapshot().decks.a
        run(2.0)
        let held = engine.latestSnapshot().decks.a
        XCTAssertTrue(held.isHeld)
        XCTAssertTrue(held.motorOn, "the motor stays START (RM-53)")
        XCTAssertEqual(held.discAngle, gripped.discAngle, accuracy: 1e-12, "disc still under the finger")
        XCTAssertEqual(held.playbackRate, 0, accuracy: 1e-9)
        XCTAssertEqual(held.platterAngle - gripped.platterAngle, TurntableConstants.referenceAngularVelocity * 2,
                       accuracy: 0.01)
        engine.send(.touchMoved(.a, angle: 0.5, time: 3.2))
        run(0.01)
        XCTAssertEqual(engine.latestSnapshot().decks.a.discAngle - held.discAngle, 0.5, accuracy: 1e-9,
                       "the disc follows the finger")
        engine.send(.touchEnded(.a, time: 3.3))
        run(0.5)
        XCTAssertEqual(engine.latestSnapshot().decks.a.playbackRate, 1, accuracy: 0.01, "slipmat catch-up")
    }

    // AC5 — PO-01 : START sans son fait tourner le plateau, sans tête ni son ; STOP freine (SF-05).
    func testStartOnEmptyDeckSpinsPlatterWithoutSound_PO01() async {
        engine.send(.motor(.b, on: true))
        engine.pump()
        run(1.0)
        var deck = engine.latestSnapshot().decks.b
        XCTAssertFalse(deck.isLoaded)
        XCTAssertGreaterThan(deck.platterAngle, 1)
        XCTAssertEqual(deck.positionSeconds, 0)
        engine.send(.motor(.b, on: false))
        run(0.5)
        XCTAssertFalse(engine.latestSnapshot().isIdle, "still braking: the display loop keeps running")
        run(1.0)
        deck = engine.latestSnapshot().decks.b
        XCTAssertEqual(deck.playbackRate, 0)
        XCTAssertTrue(engine.latestSnapshot().isIdle)
    }

    // SF-03, SF-69 (D-10) : chargement à l'état initial, repère aligné après chaque saut.
    func testJumpsRealignStickerAndLoadResetsDeck_SF03_SF69() async {
        loadClip()
        engine.send(.motor(.a, on: true))
        run(1.0)
        engine.send(.setCue(.a))
        engine.send(.seek(.a, seconds: 5))
        run(0.01)
        var deck = engine.latestSnapshot().decks.a
        let cue = try? XCTUnwrap(deck.cueSeconds)
        XCTAssertEqual(wrapped(deck.discAngle - 2 * .pi * deck.positionSeconds / 1.8), 0, accuracy: 1e-9)
        engine.send(.recallCue(.a))
        engine.pump()
        deck = engine.latestSnapshot().decks.a
        XCTAssertEqual(deck.positionSeconds, cue ?? -1, accuracy: 1e-9)
        XCTAssertEqual(wrapped(deck.stickerAngle), 0, accuracy: 1e-9, "sticker under the playhead at CUE")
        engine.send(.load(.a, PreviewDeckIntents.syntheticClip(title: "b.wav", duration: 30)))
        engine.pump()
        deck = engine.latestSnapshot().decks.a
        XCTAssertEqual(deck.positionSeconds, 0)
        XCTAssertFalse(deck.motorOn)
        XCTAssertNil(deck.cueSeconds)
        XCTAssertEqual(wrapped(deck.stickerAngle), 0, accuracy: 1e-9)
        XCTAssertEqual(deck.durationSeconds, 30, accuracy: 1e-9)
        XCTAssertEqual(engine.drainReleasedClips(), 1, "the replaced clip is returned")
        XCTAssertEqual(engine.drainReleasedClips(), 0)
    }

    // AC1, AC6 — de l'intention d'aperçu à l'affichage, par `AppModel.tick()`.
    func testPreviewIntentsLoadDemoThroughAppModel_SF76() async {
        let model = AppModel(engine: DisplayWakingEngine(wrapping: engine), host: nil, library: EmptyLibrary(),
                             preferences: InMemoryPreferencesStore(), decoder: AudioFileDecoder())
        let intents = PreviewDeckIntents(model: model)
        intents.loadDemo(on: .a)
        XCTAssertEqual(model.deckA.title, "Son de démonstration", "title shown before the load is applied")
        model.tick()
        XCTAssertTrue(model.deckA.isLoaded)
        XCTAssertEqual(model.deckA.loadedEntry?.origin, .demo)
        XCTAssertEqual(model.deckA.positionText, "00:00,0")
        XCTAssertEqual(model.deckA.durationText, "00:08,0")
        XCTAssertEqual(model.deckA.discAccessibilityValue, "à l'arrêt, position 0 seconde")
        model.deckA.toggleMotor()
        clock.now += 0.01
        model.tick()
        XCTAssertTrue(model.deckA.frame.motorOn)
        XCTAssertFalse(model.deckB.isLoaded)
    }

    // AC8 — UX §10.1 : boucle suspendue au repos, reprise à la commande suivante.
    func testDisplayLoopSuspendsWhenIdleAndWakesOnCommand() async {
        let environment = PreviewEnvironment()
        let session = RootSession(model: environment.model, intents: environment.intents)
        XCTAssertTrue(session.driver.allowsSuspension, "the preview engine is a wake source")
        session.driver.step(now: 1)
        XCTAssertFalse(session.driver.isSuspended, "idle, but within the grace period")
        session.driver.step(now: 1 + DisplayLinkDriver.idleGracePeriod)
        XCTAssertTrue(session.driver.isSuspended, "empty decks, motors off: idle for the whole grace period")
        session.model.deckA.setMotor(true)
        XCTAssertFalse(session.driver.isSuspended, "a command wakes the loop")
        session.driver.step(now: 2)
        XCTAssertFalse(session.driver.isSuspended, "motor on: not idle")

        let unwired = DisplayLinkDriver { true }
        unwired.step(now: 0)
        unwired.step(now: 10)
        XCTAssertFalse(unwired.isSuspended, "without a wake source the loop never sleeps")
    }
}
