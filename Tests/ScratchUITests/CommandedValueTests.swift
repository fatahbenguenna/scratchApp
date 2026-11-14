import Foundation
import ScratchAudio
import ScratchCore
import ScratchLibrary
import XCTest
@testable import ScratchUI

/// Bug #57 : avec l'hôte audio réel, l'instantané a du retard sur les commandes. Une valeur commandée
/// reste affichée jusqu'à confirmation, et la boucle d'affichage ne se suspend pas trop tôt.
@MainActor
final class CommandedValueTests: XCTestCase {
    private final class ManualClock: @unchecked Sendable {
        var now = 0.0
    }

    /// Moteur dont l'instantané a `lag` images de retard sur les commandes, comme le vrai moteur
    /// rendu par un hôte (commande appliquée au rendu suivant).
    private final class LaggingEngine: EngineControlling {
        let base: FakeEngine
        private var history: [EngineSnapshot]

        init(lag: Int, clock: ManualClock) {
            base = FakeEngine(clock: { clock.now })
            history = Array(repeating: .initial, count: lag + 1)   // history[0] is `lag` pumps old
        }

        func send(_ command: EngineCommand) -> Bool { base.send(command) }
        func latestSnapshot() -> EngineSnapshot { history[0] }
        func drainReleasedClips() -> Int { base.drainReleasedClips() }
        func pump() {
            base.pump()
            history.removeFirst()
            history.append(base.latestSnapshot())
        }
    }

    private struct EmptyLibrary: LibraryStoring {
        var entries: [LibraryEntry] { get async { [] } }
        func reconcile() async -> [LibraryEntry] { [] }
        func importFile(at url: URL) async throws -> ImportResult { throw LibraryError.unsupportedFormat }
        func delete(id: UUID) async throws { throw LibraryError.notFound }
        func url(for id: UUID) async throws -> URL { throw LibraryError.notFound }
    }

    private let clock = ManualClock()
    private let frame = 1.0 / 120

    private func makeModel(lag: Int) -> AppModel {
        let model = AppModel(engine: DisplayWakingEngine(wrapping: LaggingEngine(lag: lag, clock: clock)),
                             host: nil, library: EmptyLibrary(), preferences: InMemoryPreferencesStore(),
                             decoder: AudioFileDecoder())
        for deck in [model.deckA, model.deckB] { deck.clock = { [clock] in clock.now } }
        model.mixer.clock = { [clock] in clock.now }
        return model
    }

    private func tick(_ model: AppModel) {
        clock.now += frame
        model.tick()
    }

    // #57, effet 1 — START/STOP ne clignote pas (story 4.1 CA 3).
    func testStartStopDoesNotFlickerWhileTheSnapshotLags() async {
        for lag in [1, 2] {
            let model = makeModel(lag: lag)
            tick(model)
            model.deckA.setMotor(true)
            for index in 0..<6 {
                tick(model)
                XCTAssertEqual(model.deckA.startStopTitle, "STOP", "lag \(lag), frame \(index)")
            }
            XCTAssertTrue(model.deckA.frame.motorOn, "the snapshot confirmed the command")
            model.deckA.setMotor(false)
            for index in 0..<6 {
                tick(model)
                XCTAssertEqual(model.deckA.startStopTitle, "START", "lag \(lag), frame \(index)")
            }
        }
    }

    // #57 — la vitesse, le pitch et la table de mixage suivent la même règle (story 4.5 CA 5, 4.2).
    func testSettingsAndMixerHoldCommandedValues() async {
        let model = makeModel(lag: 2)
        tick(model)
        model.deckB.setSpeed(.rpm45)
        model.deckB.setPitch(0.031)
        model.deckB.setResistance(0.73)
        model.mixer.setCrossfader(0.1)
        model.mixer.setLineFader(.a, 0.4)
        model.mixer.setLineFader(.b, 0.7)
        model.mixer.setHamster(true)
        for _ in 0..<4 {
            tick(model)
            XCTAssertEqual(model.deckB.speed, .rpm45)
            XCTAssertEqual(model.deckB.pitch, 0.031, accuracy: 1e-12)
            XCTAssertEqual(model.deckB.resistance, 0.73, accuracy: 1e-12, "#94: CA 5 of 4.5")
            XCTAssertEqual(model.mixer.crossfader, 0.1, accuracy: 1e-12)
            XCTAssertEqual(model.mixer.lineFaders, DeckPair(a: 0.4, b: 0.7))
            XCTAssertTrue(model.mixer.hamster)
        }
        XCTAssertEqual(model.mixer.frame.crossfader, 0.1, accuracy: 1e-12, "confirmed by the snapshot")
    }

    // #57 — au-delà de 100 ms sans confirmation, l'instantané fait foi (commande refusée ou bornée).
    func testSnapshotWinsAfterTheConfirmationTimeout() async {
        let engine = RecordingEngine()
        let deck = DeckViewModel(deck: .a, engine: engine)
        deck.clock = { [clock] in clock.now }
        deck.setMotor(true)
        clock.now = 0.09
        deck.apply(.initial)
        XCTAssertTrue(deck.motorOn, "within 100 ms: the command is shown")
        clock.now = 0.1
        deck.apply(.initial)
        XCTAssertFalse(deck.motorOn, "never confirmed: the snapshot is shown")
        var value = CommandedValue<Int>()
        value.command(3, at: 0)
        XCTAssertEqual(value.resolve(1, at: 0.01), 3)
        XCTAssertEqual(value.resolve(3, at: 0.02), 3)
        XCTAssertNil(value.pending, "confirmed")
        XCTAssertEqual(value.resolve(5, at: 0.03), 5, "after confirmation the snapshot is followed")
    }

    // #57, effet 2 — la boucle ne se suspend pas avant que l'instantané montre le moteur en marche.
    func testDisplayLoopStaysAwakeUntilTheSnapshotCatchesUp() async {
        let model = makeModel(lag: 2)
        let session = RootSession(model: model, intents: PreviewDeckIntents(model: model))
        var now = 10.0
        func step() {
            now += frame
            clock.now += frame
            session.driver.step(now: now)
        }
        for _ in 0..<20 { step() }
        XCTAssertTrue(session.driver.isSuspended, "idle for longer than the grace period")
        model.deckA.setMotor(true)
        XCTAssertFalse(session.driver.isSuspended)
        for index in 0..<10 {
            step()
            XCTAssertFalse(session.driver.isSuspended, "frame \(index): the lagging snapshot is still idle")
        }
        XCTAssertTrue(model.deckA.frame.motorOn)
        XCTAssertGreaterThan(model.deckA.frame.platterAngle, 0, "the platter moves on screen")
    }
}
