import Foundation
import ScratchCore
import XCTest
@testable import ScratchLibrary

/// Préférences dans `UserDefaults` (story 3.4, CA 1 à 3). Chaque test utilise une suite unique,
/// supprimée à la fin.
final class UserDefaultsPreferencesStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "scratchapp.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func store() -> UserDefaultsPreferencesStore {
        UserDefaultsPreferencesStore(defaults: defaults)
    }

    /// CA 1 — SF-17, SF-24, D-17 : un document JSON unique sous `app.scratchapp.preferences.v1`. Il
    /// contient, par platine, RPM, pitch et résistance ; globalement, le crossfader, la courbe, le
    /// hamster, les faders, les durées du moteur et le rattrapage. Une nouvelle instance le relit.
    func testRoundTripThroughUserDefaults_SF17_SF24() throws {
        var preferences = AppPreferences.defaults
        preferences.decks.a = .init(speed: .rpm45, pitch: 0.031, resistance: 0.8)
        preferences.decks.b = .init(speed: .rpm33, pitch: -0.05, resistance: 0.2)
        preferences.mixer = .init(crossfader: 0.25, crossfaderCurve: 0, hamster: true, lineFaders: DeckPair(a: 0.7, b: 0.4))
        preferences.motor = MotorTimings(startDuration: 1.5, brakeDuration: 3, slipmatCatchUp: 0.12)
        store().save(preferences)

        XCTAssertEqual(UserDefaultsPreferencesStore.defaultKey, "app.scratchapp.preferences.v1")
        let data = try XCTUnwrap(defaults.data(forKey: UserDefaultsPreferencesStore.defaultKey))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "decks", "mixer", "motor"])
        XCTAssertEqual(store().load(), preferences, "a new instance reads the same preferences")
    }

    /// CA 2 — 3.1, 3.2, SF-68 : premier lancement : 33⅓ RPM, pitch 0 %, résistance 50 %, crossfader
    /// au centre, coupure franche, hamster désactivé, faders à 100 %, 0,7 s, 1,0 s et 60 ms.
    func testFirstLaunchDefaults_3_1_3_2() {
        let preferences = store().load()
        XCTAssertEqual(preferences, .defaults)
        for deck in DeckID.allCases {
            XCTAssertEqual(preferences.decks[deck].speed, .rpm33)
            XCTAssertEqual(preferences.decks[deck].pitch, 0)
            XCTAssertEqual(preferences.decks[deck].resistance, 0.5)
            XCTAssertEqual(preferences.mixer.lineFaders[deck], 1)
        }
        XCTAssertEqual(preferences.mixer.crossfader, 0.5)
        XCTAssertEqual(preferences.mixer.crossfaderCurve, 1)
        XCTAssertFalse(preferences.mixer.hamster)
        XCTAssertEqual(preferences.motor, MotorTimings(startDuration: 0.7, brakeDuration: 1.0, slipmatCatchUp: 0.06))
    }

    /// CA 3 — SF-11, SF-21, SF-68 : hors bornes → borne ; valeur illisible ou clé absente → valeur par
    /// défaut ; document illisible ou d'un autre type → valeurs par défaut, sans erreur.
    func testOutOfRangeAndUnreadableValues() throws {
        let key = UserDefaultsPreferencesStore.defaultKey
        let json = #"{"version":1,"decks":{"a":{"speed":"45","pitch":0.5,"resistance":7},"b":{"pitch":"x"}},"#
            + #""mixer":{"crossfader":-3,"hamster":true},"motor":{"startDuration":9,"brakeDuration":0,"slipmatCatchUp":2}}"#
        defaults.set(Data(json.utf8), forKey: key)
        let preferences = store().load()
        XCTAssertEqual(preferences.decks.a.speed, .rpm45)
        XCTAssertEqual(preferences.decks.a.pitch, 0.08, "clamped to +8 %")
        XCTAssertEqual(preferences.decks.a.resistance, 1)
        XCTAssertEqual(preferences.decks.b, AppPreferences.Deck(), "unreadable or missing values take their defaults")
        XCTAssertEqual(preferences.mixer.crossfader, 0)
        XCTAssertTrue(preferences.mixer.hamster)
        XCTAssertEqual(preferences.mixer.crossfaderCurve, 1)
        XCTAssertEqual(preferences.motor, MotorTimings(startDuration: 5, brakeDuration: 0.1, slipmatCatchUp: 0.3))

        defaults.set(Data("{ pas du JSON".utf8), forKey: key)
        XCTAssertEqual(store().load(), .defaults)
        defaults.set("un texte", forKey: key)
        XCTAssertEqual(store().load(), .defaults)
    }

    /// CA 1 : une clé personnalisée isole deux documents.
    func testCustomKey() {
        var preferences = AppPreferences.defaults
        preferences.mixer.hamster = true
        UserDefaultsPreferencesStore(defaults: defaults, key: "autre").save(preferences)
        XCTAssertEqual(store().load(), .defaults)
        XCTAssertEqual(UserDefaultsPreferencesStore(defaults: defaults, key: "autre").load(), preferences)
    }
}
