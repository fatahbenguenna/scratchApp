import Foundation
import Observation
import ScratchCore
import ScratchLibrary
import XCTest
@testable import ScratchUI

/// Cycle de vie de l'app (story 6.2) : démarrage de l'hôte au lancement, arrière-plan et premier plan,
/// verrouillage de l'écran, état de la sortie, scène de la CI. Hôte simulé, `RecordingEngine` et vrai
/// `LibraryStore` dans un dossier temporaire.
@MainActor
final class AppLifecycleTests: XCTestCase {
    private var library: TemporaryLibrary!
    private let demo = LibraryEntry.demo(title: DemoSound.title, duration: DemoSound.duration)
    private let headphones = AudioOutputInfo(name: "Casque", sampleRate: 48_000, bufferFrames: 256, outputLatency: 0.004)

    override func setUp() async throws {
        library = try TemporaryLibrary()
    }

    override func tearDown() async throws {
        library.remove()
    }

    private func makeModel(engine: any EngineControlling = RecordingEngine(), host: SimulatedHost? = nil,
                           preferences: InMemoryPreferencesStore = InMemoryPreferencesStore(),
                           launchOptions: LaunchOptions = LaunchOptions()) -> AppModel {
        let decoder = FakeDecoder()
        let store = library.makeStore(decoder: decoder)
        return AppModel(engine: engine, host: host, library: store, preferences: preferences,
                        decoder: decoder, launchOptions: launchOptions)
    }

    /// Préférences enregistrées différentes des valeurs par défaut.
    private static var saved: AppPreferences {
        var preferences = AppPreferences.defaults
        preferences.decks.a.speed = .rpm45
        preferences.mixer.hamster = true
        preferences.motor.brakeDuration = 2
        return preferences
    }

    /// Instantané d'un moteur qui aurait appliqué `preferences`.
    private static func snapshot(of preferences: AppPreferences) -> EngineSnapshot {
        let decks = preferences.decks.map { DeckSnapshot(speed: $0.speed, pitch: $0.pitch, resistance: $0.resistance) }
        let mixer = MixerSnapshot(crossfader: preferences.mixer.crossfader, crossfaderCurve: preferences.mixer.crossfaderCurve,
                                  hamster: preferences.mixer.hamster, lineFaders: preferences.mixer.lineFaders)
        return EngineSnapshot(decks: decks, mixer: mixer, motorTimings: preferences.motor)
    }

    /// Modèle lancé, préférences du lancement confirmées, puis un réglage changé (B à 45 tours) qui
    /// attend encore son enregistrement groupé.
    private func modelWithPendingChange(engine: RecordingEngine, host: SimulatedHost?,
                                        store: InMemoryPreferencesStore) async -> (AppModel, AppPreferences) {
        let model = makeModel(engine: engine, host: host, preferences: store)
        model.preferencesSaveDelay = 60
        await model.launch()
        model.tick() // defaults == initial snapshot: launch preferences confirmed
        var changed = AppPreferences.defaults
        changed.decks.b.speed = .rpm45
        engine.snapshot = Self.snapshot(of: changed)
        model.tick()
        return (model, changed)
    }

    /// Commande qui chargerait ou ferait jouer un son.
    private static func startsPlayback(_ command: EngineCommand) -> Bool {
        switch command {
        case .load, .motor(_, on: true): return true
        default: return false
        }
    }

    private static func snapshot(a: DeckSnapshot = .initial, b: DeckSnapshot = .initial) -> EngineSnapshot {
        EngineSnapshot(decks: DeckPair(a: a, b: b))
    }

    /// Laisse passer les tâches du fil principal jusqu'à `condition` (une seconde au plus).
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    // MARK: - CA 2 : lancement

    /// CA 2 — SF-01, RM-10 : l'hôte démarre une seule fois, après les préférences (3.4) puis la
    /// réconciliation et la liste de la bibliothèque ; aucun son n'est chargé ni joué.
    func testLaunchAppliesPreferencesThenStartsHostWithoutPlayback_RM10() async {
        let engine = RecordingEngine()
        let host = SimulatedHost()
        let model = makeModel(engine: engine, host: host, preferences: InMemoryPreferencesStore(Self.saved))
        var entriesWhenStarted: [LibraryEntry]?
        var commandsWhenStarted: [EngineCommand]?
        host.onStart = {
            entriesWhenStarted = model.libraryEntries
            commandsWhenStarted = engine.sentCommands
        }

        await model.launch()
        await model.launch()

        XCTAssertEqual(host.calls, ["start"])
        XCTAssertEqual(commandsWhenStarted, Self.saved.engineCommands, "preferences applied before the host starts")
        XCTAssertEqual(entriesWhenStarted, [demo], "library reconciled and listed before the host starts")
        XCTAssertEqual(engine.sentCommands, Self.saved.engineCommands)
        XCTAssertFalse(engine.sentCommands.contains(where: Self.startsPlayback))
        XCTAssertNil(model.deckA.loadedEntry)
        XCTAssertNil(model.deckB.loadedEntry)
    }

    /// RM-01, SF-76 : la scène de démonstration n'existe que par l'argument de la CI.
    func testDemoSceneOnlyWithItsLaunchArgument_RM01() {
        XCTAssertFalse(LaunchOptions().demoScene)
        XCTAssertFalse(LaunchOptions(arguments: ["/Applications/ScratchApp.app/Contents/MacOS/ScratchApp"]).demoScene)
        XCTAssertFalse(LaunchOptions(arguments: ["--demo-scene"]).demoScene, "the first argument is the executable")
        XCTAssertFalse(LaunchOptions(arguments: ["ScratchApp", "--selftest"]).demoScene)
        XCTAssertTrue(LaunchOptions(arguments: ["ScratchApp", "--demo-scene"]).demoScene)
    }

    /// Scène de la CI : la démo sur A puis sur B (un seul clip, RM-57), puis le moteur de B, après le
    /// démarrage de l'hôte.
    func testDemoSceneLoadsDemoOnBothDecksThenStartsB() async throws {
        let engine = RecordingEngine()
        let host = SimulatedHost()
        let model = makeModel(engine: engine, host: host, launchOptions: LaunchOptions(demoScene: true))
        let preferences = AppPreferences.defaults.engineCommands
        var commandsWhenStarted: [EngineCommand]?
        host.onStart = { commandsWhenStarted = engine.sentCommands }

        await model.launch()

        XCTAssertEqual(commandsWhenStarted, preferences)
        let clip = try XCTUnwrap(model.deckA.loadedClip)
        XCTAssertTrue(model.deckB.loadedClip === clip)
        XCTAssertEqual(engine.sentCommands, preferences + [.load(.a, clip), .load(.b, clip), .motor(.b, on: true)])
        XCTAssertEqual(model.deckA.loadedEntry, demo)
        XCTAssertEqual(model.deckB.loadedEntry, demo)
    }

    // MARK: - CA 4 : arrière-plan

    /// CA 4 — SF-81, RM-56 (6.5 « Passer en arrière-plan ») : l'arrière-plan suspend l'hôte une fois,
    /// le premier plan le relance une fois ; aucun moteur ne redémarre et le son chargé reste.
    func testBackgroundSuspendsAndForegroundResumes_SF81() async {
        let engine = RecordingEngine()
        let host = SimulatedHost()
        let model = makeModel(engine: engine, host: host)
        await model.launch()
        await model.loadDemoAndWait(on: .a)
        model.deckA.setMotor(true)
        engine.clearSentCommands()

        model.enterBackground()
        model.enterBackground()
        XCTAssertEqual(host.calls, ["start", "suspend"])
        XCTAssertFalse(host.isRenderingAudio)
        model.tick()
        XCTAssertEqual(engine.pumpCount, 1, "commands are applied by tick() while the host is suspended")

        model.enterForeground()
        model.enterForeground()
        XCTAssertEqual(host.calls, ["start", "suspend", "resume"])
        XCTAssertFalse(engine.sentCommands.contains(where: Self.startsPlayback))
        XCTAssertEqual(model.deckA.loadedEntry, demo)
        XCTAssertNotNil(model.deckA.loadedClip)
    }

    /// CA 4 — SF-81, 3.4 : un réglage changé juste avant le passage en arrière-plan est enregistré
    /// tout de suite, avant la suspension de l'hôte.
    func testBackgroundSavesPendingPreferencesBeforeSuspending_SF81() async {
        let engine = RecordingEngine()
        let host = SimulatedHost()
        let store = InMemoryPreferencesStore()
        let (model, changed) = await modelWithPendingChange(engine: engine, host: host, store: store)
        XCTAssertEqual(store.load(), .defaults, "grouped write still pending")
        var savedWhenSuspended: AppPreferences?
        host.onSuspend = { savedWhenSuspended = store.load() }

        model.enterBackground()

        XCTAssertEqual(savedWhenSuspended, changed)
        XCTAssertEqual(store.load(), changed)
    }

    /// #97 — Mac : quitter moins de 0,5 s après un réglage ne le perd pas.
    func testTerminationSavesPendingPreferences_97() async {
        let engine = RecordingEngine()
        let store = InMemoryPreferencesStore()
        let (model, changed) = await modelWithPendingChange(engine: engine, host: SimulatedHost(), store: store)
        XCTAssertEqual(store.load(), .defaults)

        model.willTerminate()

        XCTAssertEqual(store.load(), changed)
    }

    /// Le premier plan sans arrière-plan préalable (lancement, retour d'un état inactif) ne touche
    /// pas à l'hôte.
    func testForegroundWithoutBackgroundLeavesHostAlone() async {
        let host = SimulatedHost()
        let model = makeModel(host: host)
        await model.launch()

        model.enterForeground()

        XCTAssertEqual(host.calls, ["start"])
    }

    // MARK: - CA 4 : verrouillage de l'écran

    /// CA 4 — D-37 : l'écran reste allumé tant qu'un moteur tourne ou qu'un disque est tenu, sur A ou
    /// sur B ; jamais en arrière-plan.
    func testIdleTimerFollowsMotorAndHold_D37() async {
        let engine = RecordingEngine()
        let model = makeModel(engine: engine, host: SimulatedHost())
        await model.launch()
        var motor = DeckSnapshot.initial
        motor.motorOn = true
        var held = DeckSnapshot.initial
        held.isHeld = true
        var coasting = DeckSnapshot.initial
        coasting.playbackRate = 0.4

        model.tick()
        XCTAssertFalse(model.keepsScreenAwake)
        engine.snapshot = Self.snapshot(a: motor)
        model.tick()
        XCTAssertTrue(model.keepsScreenAwake)
        engine.snapshot = Self.snapshot(b: held)
        model.tick()
        XCTAssertTrue(model.keepsScreenAwake)
        engine.snapshot = Self.snapshot(a: coasting)
        model.tick()
        XCTAssertFalse(model.keepsScreenAwake, "neither a running motor nor a held disc")

        engine.snapshot = Self.snapshot(a: motor, b: held)
        model.tick()
        XCTAssertTrue(model.keepsScreenAwake)
        model.enterBackground()
        XCTAssertFalse(model.keepsScreenAwake)
        model.tick()
        XCTAssertFalse(model.keepsScreenAwake)
        model.enterForeground()
        model.tick()
        XCTAssertTrue(model.keepsScreenAwake)
    }

    // MARK: - CA 5 : sortie audio

    /// CA 5 — SF-16, SF-82, D-35 : le badge suit l'état de l'hôte dès son démarrage (« Sortie audio
    /// indisponible » sur la CI), puis à chaque changement, sans attendre une image ; chaque changement
    /// réveille la boucle d'affichage suspendue, car il ne passe pas par une commande.
    func testOutputStatusFollowsHostAndWakesDisplay_SF82() async {
        let waking = DisplayWakingEngine(wrapping: RecordingEngine())
        var wakes = 0
        waking.onCommand = { wakes += 1 }
        let host = SimulatedHost()
        let model = makeModel(engine: waking, host: host)

        await model.launch()
        XCTAssertEqual(model.outputStatus, .unavailable(reason: SimulatedHost.noOutput))
        XCTAssertGreaterThan(wakes, 0)

        let wakesBefore = wakes
        host.status = .running(headphones)
        await waitUntil { model.outputStatus == .running(self.headphones) }
        XCTAssertGreaterThan(wakes, wakesBefore)

        let wakesAfterOutput = wakes
        host.status = .unavailable(reason: SimulatedHost.noOutput)
        await waitUntil { model.outputStatus == .unavailable(reason: SimulatedHost.noOutput) }
        XCTAssertGreaterThan(wakes, wakesAfterOutput, "still observed after the first change")
    }

    /// Sans hôte (aperçus), rien ne démarre et l'état reste « arrêté ».
    func testLaunchWithoutHost() async {
        let engine = RecordingEngine()
        let model = makeModel(engine: engine)
        await model.launch()
        model.enterBackground()
        model.enterForeground()
        XCTAssertEqual(model.outputStatus, .stopped)
        XCTAssertEqual(engine.sentCommands, AppPreferences.defaults.engineCommands, "preferences only")
    }
}

/// Hôte simulé, conforme à `AudioOutputHosting` et observable comme `AudioEngineHost`. Sans sortie,
/// comme l'exécuteur de la CI : `start()` et `resume()` publient « Sortie audio indisponible ».
@MainActor
@Observable
final class SimulatedHost: AudioOutputHosting {
    static let noOutput = "Aucune sortie audio."

    var status: AudioOutputStatus = .stopped
    private(set) var isRenderingAudio = false
    private(set) var calls: [String] = []
    /// Appelé au début de `start()`.
    @ObservationIgnored var onStart: (() -> Void)?
    /// Appelé au début de `suspend()`.
    @ObservationIgnored var onSuspend: (() -> Void)?

    func start() {
        calls.append("start")
        onStart?()
        isRenderingAudio = true
        status = .unavailable(reason: Self.noOutput)
    }

    func stop() {
        calls.append("stop")
        isRenderingAudio = false
        status = .stopped
    }

    func suspend() {
        calls.append("suspend")
        onSuspend?()
        isRenderingAudio = false
        status = .stopped
    }

    func resume() {
        calls.append("resume")
        isRenderingAudio = true
        status = .unavailable(reason: Self.noOutput)
    }
}
