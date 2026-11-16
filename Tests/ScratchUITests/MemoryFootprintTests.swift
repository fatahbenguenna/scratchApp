import Foundation
import ScratchAudio
import ScratchCore
import ScratchLibrary
import XCTest
@testable import ScratchUI

/// Mémoire (NFR4, D-21 ; recette 6.3 CA 4), mesurée en release par l'étape dédiée de la CI : le
/// vrai `AppModel`, le vrai `ScratchEngine`, le décodeur AVFoundation et la bibliothèque. Le test
/// rend le moteur lui-même, comme le ferait le fil audio de l'hôte, et appelle `tick()` entre deux
/// lots de tampons : les clips remplacés sont libérés par `drainReleasedClips()`.
///
/// L'empreinte (`phys_footprint`) est celle du processus de test. L'écart entre deux relevés donne
/// la part des sons ; l'empreinte totale de l'app se relève sur le Mac de recette.
@MainActor
final class MemoryFootprintTests: XCTestCase {
    private var library: TemporaryLibrary!

    /// Budget de D-21 pour deux sons de 10 min, en mégaoctets.
    private static let budget = 650.0
    /// Variation tolérée de l'empreinte après 20 remplacements, en mégaoctets.
    private static let stability = 30.0

    override func setUp() async throws {
        library = try TemporaryLibrary()
    }

    override func tearDown() async throws {
        library.remove()
    }

    /// NFR4 — deux sons distincts de près de 10 min, à 48 kHz en stéréo (le pire cas de D-21, environ
    /// 230 Mo chacun), chargés sur A et B : ils tiennent dans le budget de 650 Mo. Après 20
    /// remplacements, l'empreinte est stable : chaque son remplacé est libéré. Le pic du décodage
    /// d'un remplacement est relevé et rapporté à la taille du clip (objectif ≤ 1,5).
    func testTwoTenMinuteSoundsAndTwentyReplacements_NFR4() async throws {
        try XCTSkipIf(MeasurementLog.isDebugBuild, "measured in release by the CI release step")
        let engine = ScratchEngine()
        let host = SimulatedHost()
        let decoder = AudioFileDecoder()
        let model = AppModel(engine: engine, host: host, library: library.makeStore(decoder: decoder),
                             preferences: InMemoryPreferencesStore(), decoder: decoder)
        host.start() // the test renders the engine, as the audio thread would
        let renderer = EngineRenderer(engine: engine)
        defer { renderer.deallocate() }

        let first = try writeNoise("premier.wav", seed: 1)
        let second = try writeNoise("second.wav", seed: 2)
        let baseline = MemoryFootprint.current()
        await model.importAndLoad(first, on: .a)
        await model.importAndLoad(second, on: .b)
        await settle(model, renderer)
        XCTAssertNil(model.alert)
        let clipBytes: Int64
        do { // no strong reference to the clips outside this scope: they must be freed once replaced
            let clipA = try XCTUnwrap(model.deckA.loadedClip)
            let clipB = try XCTUnwrap(model.deckB.loadedClip)
            XCTAssertNotEqual(clipA.id, clipB.id, "two distinct sounds")
            XCTAssertEqual(clipA.sampleRate, 48_000)
            clipBytes = Int64(clipA.frameCount) * 2 * Int64(MemoryLayout<Float>.size)
        }
        XCTAssertTrue(engine.latestSnapshot()[.a].isLoaded && engine.latestSnapshot()[.b].isLoaded)
        let loaded = MemoryFootprint.current()
        let loadedDelta = MemoryFootprint.megabytes(Int64(loaded) - Int64(baseline))

        // 20 replacements: each deck in turn takes the other sound, decoded again.
        let entries = model.libraryEntries.filter { $0.id != LibraryEntry.demoID }
        XCTAssertEqual(entries.count, 2)
        var decodePeakRatio = 0.0
        var replacedClips: [WeakClip] = []
        for round in 0 ..< 20 {
            let deck: DeckID = round.isMultiple(of: 2) ? .a : .b
            let entry = try XCTUnwrap(entries.first { $0.id != model.deck(deck).loadedEntry?.id })
            replacedClips.append(WeakClip(model.deck(deck).loadedClip))
            if round == 0 {
                let before = MemoryFootprint.current()
                let (_, peak) = await MemoryFootprint.peak { await model.load(entry, on: deck) }
                decodePeakRatio = Double(Int64(peak) - Int64(before)) / Double(clipBytes)
            } else {
                await model.load(entry, on: deck)
            }
            XCTAssertEqual(model.deck(deck).loadedEntry?.id, entry.id, "round \(round)")
            await settle(model, renderer)
        }
        XCTAssertNil(model.alert)
        XCTAssertEqual(replacedClips.count, 20)
        XCTAssertEqual(replacedClips.filter { $0.clip != nil }.count, 0, "NFR4: every replaced clip is freed")
        let replaced = MemoryFootprint.current()
        let drift = MemoryFootprint.megabytes(Int64(replaced) - Int64(loaded))

        MeasurementLog.write(String(
            format: "NFR4 — mémoire : 2 sons distincts de 10 min (48 kHz, stéréo, %.0f Mo par clip) chargés : +%.0f Mo "
                + "(budget %.0f Mo) ; après 20 remplacements : %+.0f Mo ; pic de décodage d'un remplacement : %.2f × le clip "
                + "(empreinte du processus de test : %.0f Mo, build %@)",
            MemoryFootprint.megabytes(clipBytes), loadedDelta, Self.budget, drift, decodePeakRatio,
            MemoryFootprint.megabytes(replaced), MeasurementLog.configuration))
        XCTAssertLessThanOrEqual(loadedDelta, Self.budget, "D-21: two 10-minute sounds within 650 MB")
        XCTAssertLessThanOrEqual(abs(drift), Self.stability, "NFR4: every replaced sound is released")
    }

    // MARK: - Helpers

    /// Son de 599 s (sous la limite de SF-80), 48 kHz, stéréo, 16 bits ; `seed` le rend distinct.
    private func writeNoise(_ name: String, seed: UInt32) throws -> URL {
        let url = library.sources.appendingPathComponent(name)
        try TestWAV.noise(seconds: 599, sampleRate: 48_000, channels: 2, seed: seed).write(to: url)
        return url
    }

    /// Quelques lots de tampons rendus puis une image : commandes appliquées, clips remplacés
    /// libérés, formes d'onde calculées.
    private func settle(_ model: AppModel, _ renderer: EngineRenderer) async {
        for _ in 0 ..< 20 {
            renderer.render(buffers: 8)
            model.tick()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

/// Référence faible vers un clip remplacé : nulle une fois le clip libéré.
private final class WeakClip {
    weak var clip: AudioClip?

    init(_ clip: AudioClip?) {
        self.clip = clip
    }
}

/// Rendu du moteur par le test, à la place du fil audio : tampons de 256 trames alloués une fois.
private final class EngineRenderer {
    private let engine: ScratchEngine
    private let left = UnsafeMutablePointer<Float>.allocate(capacity: 256)
    private let right = UnsafeMutablePointer<Float>.allocate(capacity: 256)

    init(engine: ScratchEngine) {
        self.engine = engine
    }

    func render(buffers: Int) {
        for _ in 0 ..< buffers {
            engine.render(frameCount: 256, left: left, right: right)
        }
    }

    func deallocate() {
        left.deallocate()
        right.deallocate()
    }
}
