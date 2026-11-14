import Foundation
import ScratchAudio
import ScratchCore
import ScratchLibrary
import XCTest
@testable import ScratchUI

/// Contrat UI ↔ moteur (architecture §5.4) : les intentions produisent les bonnes commandes, et
/// `AppModel.tick()` répercute l'instantané sur les modèles de présentation.
@MainActor
final class ViewModelTests: XCTestCase {
    private struct EmptyLibrary: LibraryStoring {
        var entries: [LibraryEntry] { get async { [] } }
        func reconcile() async -> [LibraryEntry] { [] }
        func importFile(at url: URL) async throws -> ImportResult { throw LibraryError.unsupportedFormat }
        func delete(id: UUID) async throws { throw LibraryError.notFound }
        func url(for id: UUID) async throws -> URL { throw LibraryError.notFound }
    }

    private func makeModel(engine: RecordingEngine) -> AppModel {
        AppModel(engine: engine, host: nil, library: EmptyLibrary(),
                 preferences: InMemoryPreferencesStore(), decoder: AudioFileDecoder())
    }

    func testToggleMotorSendsStartThenStop_SF04_SF05() async {
        let engine = RecordingEngine()
        let deck = DeckViewModel(deck: .b, engine: engine)
        deck.toggleMotor()
        deck.toggleMotor()
        XCTAssertEqual(engine.sentCommands, [.motor(.b, on: true), .motor(.b, on: false)])
    }

    /// SF-11 : pas de 0,1 %, borné à ±8 %, remise à 0.
    func testPitchIsQuantizedAndClamped_SF11() async {
        let engine = RecordingEngine()
        let deck = DeckViewModel(deck: .a, engine: engine)
        deck.setPitch(0.05349)
        XCTAssertEqual(deck.pitch, 0.053, accuracy: 1e-12)
        deck.nudgePitch(steps: 1)
        XCTAssertEqual(deck.pitch, 0.054, accuracy: 1e-12)
        deck.setPitch(0.2)
        XCTAssertEqual(deck.pitch, 0.08, accuracy: 1e-12)
        deck.resetPitch()
        XCTAssertEqual(deck.pitch, 0)
        XCTAssertEqual(engine.sentCommands.last, .pitch(.a, 0))
    }

    /// SF-71 : needle drop en fraction de la durée, ignoré disque tenu.
    func testNeedleDropUsesDurationAndIsIgnoredWhileHeld_SF71() async {
        let engine = RecordingEngine()
        let deck = DeckViewModel(deck: .a, engine: engine)
        var snapshot = DeckSnapshot.initial
        snapshot.durationSeconds = 40
        deck.apply(snapshot)
        deck.needleDrop(fraction: 0.75)
        XCTAssertEqual(engine.sentCommands, [.seek(.a, seconds: 30)])
        snapshot.isHeld = true
        deck.apply(snapshot)
        deck.needleDrop(fraction: 0.25)
        XCTAssertEqual(engine.sentCommands.count, 1)
    }

    /// 6.14 : `⇧←` puis trois fois `→` → 15 % de la course vers B.
    func testKeyboardCrossfaderSteps_6_14() async {
        let engine = RecordingEngine()
        let mixer = MixerViewModel(engine: engine)
        mixer.moveCrossfaderToA()
        for _ in 0..<3 { mixer.nudgeCrossfader(steps: 1) }
        XCTAssertEqual(mixer.crossfader, 0.15, accuracy: 1e-12)
    }

    func testTickPumpsWithoutHostAndAppliesSnapshot() async {
        let engine = RecordingEngine()
        let model = makeModel(engine: engine)
        var snapshot = EngineSnapshot.initial
        snapshot.decks.a.motorOn = true
        snapshot.decks.b.cueSeconds = 12
        snapshot.mixer.hamster = true
        engine.snapshot = snapshot
        model.tick()
        XCTAssertEqual(engine.pumpCount, 1, "no audio thread: the model pumps the engine")
        XCTAssertEqual(engine.drainCount, 1)
        XCTAssertTrue(model.deckA.motorOn)
        XCTAssertEqual(model.deckB.cueSeconds, 12)
        XCTAssertTrue(model.mixer.hamster)
        XCTAssertEqual(model.deck(.b).frame, snapshot.decks.b)
    }

    /// Avec le vrai moteur et sans hôte : une intention est visible après une image.
    func testIntentRoundTripThroughRealEngine() async {
        let engine = ScratchEngine()
        let model = AppModel(engine: engine, host: nil, library: EmptyLibrary(),
                             preferences: InMemoryPreferencesStore(), decoder: AudioFileDecoder())
        model.mixer.setLineFader(.a, 0.4)
        model.deckB.setSpeed(.rpm45)
        model.tick()
        XCTAssertEqual(model.mixer.frame.lineFaders.a, 0.4)
        XCTAssertEqual(model.deckB.frame.speed, .rpm45)
    }
}
