import Foundation
import ScratchCore
import ScratchLibrary
import XCTest
@testable import ScratchUI

/// Préférences et écran Réglages côté `AppModel` (story 3.4, CA 4 à 7).
@MainActor
final class AppModelPreferencesTests: XCTestCase {
    private var library: TemporaryLibrary!
    private var now = 1_000.0

    override func setUp() async throws {
        library = try TemporaryLibrary()
    }

    override func tearDown() async throws {
        library.remove()
    }

    private func makeModel(engine: RecordingEngine, store: InMemoryPreferencesStore) -> AppModel {
        let decoder = FakeDecoder()
        let model = AppModel(engine: engine, host: nil, library: library.makeStore(decoder: decoder),
                             preferences: store, decoder: decoder)
        model.clock = { [unowned self] in self.now }
        return model
    }

    private static var custom: AppPreferences {
        var preferences = AppPreferences.defaults
        preferences.decks.a = .init(speed: .rpm45, pitch: 0.03, resistance: 0.75)
        preferences.mixer = .init(crossfader: 1, crossfaderCurve: 0, hamster: true, lineFaders: DeckPair(a: 0.5, b: 0.25))
        preferences.motor = MotorTimings(startDuration: 0.2, brakeDuration: 3, slipmatCatchUp: 0.3)
        return preferences
    }

    /// Instantané d'un moteur qui aurait appliqué `preferences`.
    private static func snapshot(of preferences: AppPreferences) -> EngineSnapshot {
        let decks = preferences.decks.map { DeckSnapshot(speed: $0.speed, pitch: $0.pitch, resistance: $0.resistance) }
        let mixer = MixerSnapshot(crossfader: preferences.mixer.crossfader, crossfaderCurve: preferences.mixer.crossfaderCurve,
                                  hamster: preferences.mixer.hamster, lineFaders: preferences.mixer.lineFaders)
        return EngineSnapshot(decks: decks, mixer: mixer, motorTimings: preferences.motor)
    }

    /// CA 4 — SF-17, RM-10, PO-12, D-45, scénarios « Restaurer les préférences » et « Restaurer le
    /// réglage mémorisé » : au lancement, les préférences sont envoyées au moteur. Ni `motor` ni
    /// `load` ne part, et aucun son n'est rechargé.
    func testLaunchAppliesPreferencesWithoutPlayback_RM10() async {
        let engine = RecordingEngine()
        let model = makeModel(engine: engine, store: InMemoryPreferencesStore(Self.custom))
        await model.launch()

        XCTAssertEqual(engine.sentCommands, Self.custom.engineCommands)
        for command in engine.sentCommands {
            switch command {
            case .motor, .load, .unload:
                XCTFail("unexpected \(command)")
            default:
                break
            }
        }
        XCTAssertEqual(model.motorTimings, Self.custom.motor)
        XCTAssertNil(model.deckA.loadedEntry)
        XCTAssertNil(model.deckB.loadedEntry)
    }

    /// CA 5 : un changement est enregistré 0,5 s après le dernier changement, pas à chaque image.
    /// Rien n'est écrit avant que l'instantané confirme les préférences du lancement.
    func testChangesAreSavedDebounced() async throws {
        let engine = RecordingEngine()
        let store = InMemoryPreferencesStore(Self.custom)
        let model = makeModel(engine: engine, store: store)
        model.preferencesSaveDelay = 0.05
        await model.launch()

        model.tick() // the engine has not applied the launch commands yet: initial snapshot
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(store.load(), Self.custom, "an image rendered before the launch commands never overwrites them")

        engine.snapshot = Self.snapshot(of: Self.custom)
        model.tick()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(store.load(), Self.custom, "no change, no write")

        var changed = Self.custom
        changed.mixer.hamster = false
        changed.decks.b.pitch = -0.02
        engine.snapshot = Self.snapshot(of: changed)
        model.tick()
        model.tick()
        XCTAssertEqual(store.load(), Self.custom, "grouped: nothing written immediately")
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(store.load(), changed)
    }

    /// CA 5 — 6.2 : `savePreferencesNow()` écrit tout de suite (passage en arrière-plan).
    func testSaveNowOnBackground() async {
        let engine = RecordingEngine()
        let store = InMemoryPreferencesStore()
        let model = makeModel(engine: engine, store: store)
        model.preferencesSaveDelay = 60
        await model.launch()
        model.tick() // defaults == initial snapshot: confirmed

        var changed = AppPreferences.defaults
        changed.decks.a.speed = .rpm45
        engine.snapshot = Self.snapshot(of: changed)
        model.tick()
        XCTAssertEqual(store.load(), .defaults)
        model.savePreferencesNow()
        XCTAssertEqual(store.load(), changed)
    }

    /// CA 6 — D-18, scénarios 6.2 « Régler les durées de démarrage et de freinage », 6.9 « Rattrapage
    /// réglable » : valeurs ramenées au pas et à la plage, envoyées au moteur et affichées tout de
    /// suite, maintenues jusqu'à confirmation par l'instantané (#57).
    func testSettingsSettersQuantizeAndCommand() {
        let engine = RecordingEngine()
        let model = makeModel(engine: engine, store: InMemoryPreferencesStore())
        model.setStartDuration(0.73)
        model.setBrakeDuration(9)
        model.setSlipmatCatchUp(0.0649)
        XCTAssertEqual(engine.sentCommands, [.startDuration(0.7), .brakeDuration(5), .slipmatCatchUp(0.06)])
        XCTAssertEqual(model.motorTimings, MotorTimings(startDuration: 0.7, brakeDuration: 5, slipmatCatchUp: 0.06))

        model.tick() // the snapshot still shows the defaults: the commanded values stay displayed
        XCTAssertEqual(model.motorTimings, MotorTimings(startDuration: 0.7, brakeDuration: 5, slipmatCatchUp: 0.06))
        engine.snapshot = EngineSnapshot(motorTimings: MotorTimings(startDuration: 0.7, brakeDuration: 5, slipmatCatchUp: 0.06))
        model.tick()
        XCTAssertEqual(model.motorTimings, engine.snapshot.motorTimings)

        model.setSlipmatCatchUp(-1)
        model.setStartDuration(.nan)
        XCTAssertEqual(engine.sentCommands.suffix(2), [.slipmatCatchUp(0), .startDuration(0.1)])

        XCTAssertFalse(model.isSettingsPresented)
        model.openSettings()
        XCTAssertTrue(model.isSettingsPresented)
    }

    /// CA 7 — SF-83, UX §5.20 : valeurs affichées et lues par VoiceOver ; champ numérique Mac à
    /// virgule décimale française ; saisie invalide refusée.
    func testSettingsAccessibilityValues() {
        let nbsp = "\u{00A0}"
        XCTAssertEqual(SettingsFormatting.seconds(0.7), "0,7\(nbsp)s")
        XCTAssertEqual(SettingsFormatting.seconds(1), "1,0\(nbsp)s")
        XCTAssertEqual(SettingsFormatting.milliseconds(0.06), "60\(nbsp)ms")
        XCTAssertEqual(SettingsFormatting.spokenSeconds(0.7), "0,7 seconde")
        XCTAssertEqual(SettingsFormatting.spokenSeconds(1), "1 seconde")
        XCTAssertEqual(SettingsFormatting.spokenSeconds(2.5), "2,5 secondes")
        XCTAssertEqual(SettingsFormatting.spokenMilliseconds(0.06), "60 millisecondes")
        XCTAssertEqual(SettingsFormatting.spokenMilliseconds(0), "0 milliseconde")
        XCTAssertEqual(SettingsFormatting.fieldText(0.7, milliseconds: false), "0,7")
        XCTAssertEqual(SettingsFormatting.fieldText(0.06, milliseconds: true), "60")
        XCTAssertEqual(SettingsFormatting.parse("0,7", milliseconds: false), 0.7)
        XCTAssertEqual(SettingsFormatting.parse(" 1.5 ", milliseconds: false), 1.5)
        XCTAssertEqual(SettingsFormatting.parse("120", milliseconds: true), 0.12)
        XCTAssertNil(SettingsFormatting.parse("abc", milliseconds: false))
        XCTAssertNil(SettingsFormatting.parse("", milliseconds: true))
        XCTAssertEqual(SettingsFormatting.quantized(0.7, step: 0.1, in: 0.1...5), 0.7, "no binary rounding residue")
        XCTAssertEqual(SettingsFormatting.quantized(12, step: 0.1, in: 0.1...5), 5, "out of range: clamped")
    }
}
