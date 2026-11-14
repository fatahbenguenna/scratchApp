import Foundation
import ScratchCore
import XCTest
@testable import ScratchLibrary

final class AppPreferencesTests: XCTestCase {
    /// Valeurs du premier lancement : 33⅓ RPM (RM-02), pitch 0 %, résistance 50 % (3.1),
    /// crossfader au centre en coupure franche, hamster désactivé, faders à 100 % (3.2),
    /// démarrage 0,7 s, freinage 1,0 s, rattrapage 60 ms (SF-04, SF-05, SF-68).
    func testDefaultsMatchSpec_SF17() {
        let defaults = AppPreferences.defaults
        for deck in DeckID.allCases {
            XCTAssertEqual(defaults.decks[deck].speed, .rpm33)
            XCTAssertEqual(defaults.decks[deck].pitch, 0)
            XCTAssertEqual(defaults.decks[deck].resistance, 0.5)
            XCTAssertEqual(defaults.mixer.lineFaders[deck], 1)
        }
        XCTAssertEqual(defaults.mixer.crossfader, 0.5)
        XCTAssertEqual(defaults.mixer.crossfaderCurve, 1)
        XCTAssertFalse(defaults.mixer.hamster)
        XCTAssertEqual(defaults.motor, MotorTimings(startDuration: 0.7, brakeDuration: 1.0, slipmatCatchUp: 0.06))
    }

    /// Les valeurs par défaut des préférences et l'état initial du moteur concordent.
    func testDefaultsMatchInitialEngineSnapshot() {
        XCTAssertEqual(AppPreferences(snapshot: .initial), .defaults)
    }

    /// Scénario « Restaurer les préférences » (6.5) : aller-retour JSON.
    func testRoundTrip_SF17() throws {
        var preferences = AppPreferences.defaults
        preferences.decks.a = .init(speed: .rpm45, pitch: 0.03, resistance: 0.75)
        preferences.mixer.crossfader = 1
        preferences.mixer.crossfaderCurve = 0
        preferences.mixer.hamster = true
        preferences.motor.brakeDuration = 3
        let data = try JSONEncoder().encode(preferences)
        XCTAssertEqual(try JSONDecoder().decode(AppPreferences.self, from: data), preferences)
    }

    /// Format JSON figé : chemins de clés stables (les valeurs sont vérifiées par l'aller-retour).
    func testJSONKeysAreStable() throws {
        let data = try JSONEncoder().encode(AppPreferences.defaults)
        let object = try JSONSerialization.jsonObject(with: data)
        func keyPaths(_ value: Any, prefix: String = "") -> [String] {
            guard let dictionary = value as? [String: Any] else { return [prefix] }
            return dictionary.flatMap { keyPaths($0.value, prefix: prefix.isEmpty ? $0.key : "\(prefix).\($0.key)") }
        }
        XCTAssertEqual(keyPaths(object).sorted(), [
            "decks.a.pitch", "decks.a.resistance", "decks.a.speed",
            "decks.b.pitch", "decks.b.resistance", "decks.b.speed",
            "mixer.crossfader", "mixer.crossfaderCurve", "mixer.hamster", "mixer.lineFaders.a", "mixer.lineFaders.b",
            "motor.brakeDuration", "motor.slipmatCatchUp", "motor.startDuration",
            "version",
        ])
        XCTAssertEqual((object as? [String: Any])?["version"] as? Int, 1)
    }

    /// Décodage tolérant : une clé absente ou invalide reprend sa valeur par défaut.
    func testDecodingIsTolerant() throws {
        let json = #"{"mixer":{"hamster":true,"crossfader":"oops"},"decks":{"a":{"speed":"45"},"b":{}}}"#
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))
        XCTAssertTrue(preferences.mixer.hamster)
        XCTAssertEqual(preferences.mixer.crossfader, 0.5)
        XCTAssertEqual(preferences.decks.a.speed, .rpm45)
        XCTAssertEqual(preferences.decks.a.resistance, 0.5)
        XCTAssertEqual(preferences.motor, .defaults)
    }

    func testSanitizedClampsValues() {
        var preferences = AppPreferences.defaults
        preferences.decks.b.pitch = 0.5
        preferences.decks.b.resistance = .nan
        preferences.mixer.lineFaders.a = 3
        preferences.motor.startDuration = 0
        let sanitized = preferences.sanitized()
        XCTAssertEqual(sanitized.decks.b.pitch, 0.08)
        XCTAssertEqual(sanitized.decks.b.resistance, 0.5)
        XCTAssertEqual(sanitized.mixer.lineFaders.a, 1)
        XCTAssertEqual(sanitized.motor.startDuration, 0.1)
    }

    /// RM-10, SF-17 : appliquer les préférences ne démarre jamais un moteur ni ne charge un son.
    func testEngineCommandsNeverStartMotorsOrLoad_RM10() {
        let commands = AppPreferences.defaults.engineCommands
        XCTAssertFalse(commands.isEmpty)
        for command in commands {
            switch command {
            case .motor, .load, .unload, .touchBegan, .touchMoved, .touchEnded, .seek, .recallCue, .setCue:
                XCTFail("unexpected command \(command)")
            default:
                break
            }
        }
    }

    /// Appliquées à un moteur neuf, les préférences sont reflétées dans l'instantané.
    func testEngineCommandsRoundTripThroughTheEngine() {
        var preferences = AppPreferences.defaults
        preferences.decks.a = .init(speed: .rpm45, pitch: 0.03, resistance: 0.75)
        preferences.mixer = .init(crossfader: 1, crossfaderCurve: 0, hamster: true, lineFaders: DeckPair(a: 0.5, b: 0.25))
        preferences.motor = MotorTimings(startDuration: 0.2, brakeDuration: 3, slipmatCatchUp: 0.3)
        let engine = ScratchEngine()
        for command in preferences.engineCommands { XCTAssertTrue(engine.send(command)) }
        engine.pump()
        XCTAssertEqual(AppPreferences(snapshot: engine.latestSnapshot()), preferences)
    }

    func testInMemoryStore() {
        let store = InMemoryPreferencesStore()
        XCTAssertEqual(store.load(), .defaults)
        var preferences = AppPreferences.defaults
        preferences.mixer.hamster = true
        store.save(preferences)
        XCTAssertEqual(store.load(), preferences)
    }
}
