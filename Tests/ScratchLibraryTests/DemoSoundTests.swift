import Foundation
import ScratchCore
import XCTest
@testable import ScratchLibrary

/// Son de démonstration (SF-76, D-20) : story 3.3.
final class DemoSoundTests: XCTestCase {
    /// Clip partagé par les tests d'analyse (sa génération est déterministe).
    private static let clip = DemoSound.makeClip()
    private var clip: AudioClip { Self.clip }

    private func frame(_ seconds: Double) -> Int { Int((seconds * DemoSound.sampleRate).rounded()) }

    /// Crête des deux canaux sur `[start, end)`, en trames.
    private func peak(_ range: Range<Int>) -> Float {
        var maximum: Float = 0
        for index in range { maximum = max(maximum, clip.left[index].magnitude, clip.right[index].magnitude) }
        return maximum
    }

    /// Première trame de `range` dont la valeur absolue atteint `fraction` de la crête de `range`.
    private func attackFrames(_ range: Range<Int>, fraction: Float) -> Int? {
        let threshold = fraction * peak(range)
        return range.first { max(clip.left[$0].magnitude, clip.right[$0].magnitude) >= threshold }
            .map { $0 - range.lowerBound }
    }

    /// CA1 — SF-76, D-20, scénario « Démo déterministe et propre » : 384 000 trames à 48 kHz, deux
    /// générations identiques bit à bit.
    func testDemoIsDeterministic_SF76() {
        let first = DemoSound.makeClip()
        let second = DemoSound.makeClip()
        for clip in [first, second] {
            XCTAssertEqual(clip.frameCount, 384_000)
            XCTAssertEqual(clip.sampleRate, 48_000)
            XCTAssertEqual(clip.duration, 8)
            XCTAssertEqual(clip.title, "Son de démonstration")
        }
        XCTAssertTrue(first.left.elementsEqual(second.left) { $0.bitPattern == $1.bitPattern })
        XCTAssertTrue(first.right.elementsEqual(second.right) { $0.bitPattern == $1.bitPattern })
        XCTAssertNotEqual(first.id, second.id, "each call builds its own clip")
    }

    /// CA1 : la synthèse n'utilise que les opérations IEEE 754 de base ; son empreinte est la même
    /// sous Linux et macOS (FNV-1a 64 bits des motifs binaires, canal gauche puis droit).
    func testDemoFingerprintIsTheSameOnEveryPlatform_SF76() {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for channel in [clip.left, clip.right] {
            for sample in channel {
                var bits = sample.bitPattern
                for _ in 0 ..< 4 {
                    hash = (hash ^ UInt64(bits & 0xff)) &* 0x0000_0100_0000_01b3
                    bits >>= 8
                }
            }
        }
        XCTAssertEqual(String(hash, radix: 16), "2d7edb691fc94399")
    }

    /// CA2 : crête ≤ −1 dBFS (0,891) sur les deux canaux, atteinte par normalisation (≥ 0,88) ;
    /// aucune valeur NaN ni infinie.
    func testDemoPeakAndFiniteness() {
        for (name, channel) in [("left", clip.left), ("right", clip.right)] {
            XCTAssertTrue(channel.allSatisfy(\.isFinite), name)
            let channelPeak = channel.reduce(Float(0)) { max($0, $1.magnitude) }
            XCTAssertLessThanOrEqual(channelPeak, 0.891, name)
            XCTAssertGreaterThan(channelPeak, 0.5, name)
        }
        XCTAssertGreaterThanOrEqual(peak(0 ..< clip.frameCount), 0.88, "normalized just under −1 dBFS")
    }

    /// CA1, CA2 : stab à 0 s (et second stab à 4 s) : 90 % de sa crête en moins de 2 ms, depuis un
    /// premier échantillon nul (pas de saut au départ de la lecture).
    func testDemoHasAStabAtZero() {
        XCTAssertEqual(clip.left[0], 0)
        XCTAssertEqual(clip.right[0], 0)
        let firstStab = 0 ..< frame(0.35)
        XCTAssertLessThan(try XCTUnwrap(attackFrames(firstStab, fraction: 0.9)), frame(0.002))
        let secondStab = frame(4) ..< frame(4.35)
        XCTAssertLessThan(try XCTUnwrap(attackFrames(secondStab, fraction: 0.9)), frame(0.002))
        XCTAssertGreaterThan(peak(firstStab), 0.5, "the stab is a loud, sharp attack")
    }

    /// CA2 : aucun silence (crête < −60 dBFS sur des tranches de 10 ms) de plus de 0,5 s entre 0 et
    /// 4 s, zone utilisée par le self-test (2.4).
    func testDemoHasNoLongSilenceInTheScratchZone() {
        let block = frame(0.01)
        var longestRun = 0, run = 0
        for start in stride(from: 0, to: frame(4), by: block) {
            if peak(start ..< start + block) < 0.001 {
                run += 1
                longestRun = max(longestRun, run)
            } else {
                run = 0
            }
        }
        XCTAssertLessThanOrEqual(longestRun * block, frame(0.5))
    }

    /// CA1 : voix « ahh » tenue après le stab, de fondamentale proche de 140 Hz (autocorrélation sur
    /// 50 ms à 1 s), puis voix plus aiguë (165 Hz) après le second stab.
    func testDemoVoiceFollowsTheStab() {
        func fundamental(at seconds: Double) -> Double {
            let start = frame(seconds), length = frame(0.05)
            var bestLag = 0, bestScore = -Double.infinity
            for lag in 150 ... 500 {
                var score = 0.0
                for index in start ..< start + length {
                    score += Double(clip.left[index]) * Double(clip.left[index + lag])
                }
                if score > bestScore { (bestLag, bestScore) = (lag, score) }
            }
            return DemoSound.sampleRate / Double(bestLag)
        }
        XCTAssertEqual(fundamental(at: 1.0), 140, accuracy: 5)
        XCTAssertEqual(fundamental(at: 5.0), 165, accuracy: 6)
        XCTAssertGreaterThan(peak(frame(1) ..< frame(3.5)), 0.2, "the voice is clearly audible")
    }

    /// CA1 : vraie stéréo, sans opposition de phase : canaux corrélés positivement sur tout le son et
    /// sur chaque tranche de 100 ms audible, et la somme mono ne perd pas d'énergie.
    func testDemoIsStereoWithoutPhaseOpposition() {
        func correlation(_ range: Range<Int>) -> (correlation: Double, monoGain: Double) {
            var sumLR = 0.0, sumLL = 0.0, sumRR = 0.0
            for index in range {
                let l = Double(clip.left[index]), r = Double(clip.right[index])
                sumLR += l * r
                sumLL += l * l
                sumRR += r * r
            }
            // Energy of (L + R) / 2 relative to the mean channel energy: 1 when L == R, < 0.5 on opposition.
            let mono = (sumLL + sumRR + 2 * sumLR) / 4, channels = (sumLL + sumRR) / 2
            return (sumLR / (sumLL * sumRR).squareRoot(), mono / channels)
        }
        XCTAssertFalse(clip.left.elementsEqual(clip.right), "left and right are not identical")
        let whole = correlation(0 ..< clip.frameCount)
        XCTAssertGreaterThan(whole.correlation, 0.5)
        XCTAssertGreaterThan(whole.monoGain, 0.75)
        let slice = frame(0.1)
        for start in stride(from: 0, to: frame(7.6) - slice, by: slice) where peak(start ..< start + slice) > 0.01 {
            XCTAssertGreaterThan(correlation(start ..< start + slice).correlation, 0.3, "slice at \(start)")
        }
    }

    /// Fin du son : fondu jusqu'à un dernier échantillon nul (sillon fermé, RM-55).
    func testDemoEndsWithAFadeOut_RM55() {
        let last = clip.frameCount - 1
        XCTAssertEqual(clip.left[last], 0)
        XCTAssertEqual(clip.right[last], 0)
        XCTAssertLessThan(peak(clip.frameCount - frame(0.01) ..< clip.frameCount), 0.01)
    }

    /// CA3 : objectif de 250 ms en configuration optimisée (release) sur Mac Apple Silicon. Les tests
    /// tournent en débogage, sans optimisation, sur des machines partagées : borne large de 3 s.
    func testDemoGenerationTime() {
        let start = Date()
        _ = DemoSound.makeClip()
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 3, "debug bound; release target is 0.25 s")
    }

    /// CA4 — SF-74, D-36, scénario 6.13 « Le son de démonstration ne peut pas être supprimé » :
    /// entrée en tête, origine `.demo` (« Intégré »), sans fichier, non supprimable, `url(for:)` lève
    /// `notFound` ; aucun fichier n'est écrit.
    func testDemoEntryIsFirstUndeletableWithoutFile_SF74() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(locations: LibraryLocations(documentsDirectory: root.appendingPathComponent("Documents"),
                                                             supportDirectory: root.appendingPathComponent("Support")),
                                 decoder: NoDecoder())
        let entries = await store.entries
        let demo = try XCTUnwrap(entries.first)
        XCTAssertEqual(demo, LibraryEntry.demo(title: DemoSound.title, duration: DemoSound.duration))
        XCTAssertEqual(demo.id, LibraryEntry.demoID)
        XCTAssertEqual(demo.title, "Son de démonstration")
        XCTAssertEqual(demo.duration, 8)
        XCTAssertEqual(demo.origin, .demo)
        XCTAssertFalse(demo.isDeletable)
        XCTAssertEqual(demo.fileName, "")
        XCTAssertEqual(demo.fileSize, 0)
        do {
            try await store.delete(id: LibraryEntry.demoID)
            XCTFail("the demo must not be deletable")
        } catch {
            XCTAssertEqual(error as? LibraryError, .demoCannotBeDeleted)
        }
        do {
            _ = try await store.url(for: LibraryEntry.demoID)
            XCTFail("the demo has no file")
        } catch {
            XCTAssertEqual(error as? LibraryError, .notFound)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path), "the demo is never written to disk")
    }

    /// CA5 — SF-76, RM-01 : rien dans ScratchLibrary ne charge la démo. `DemoSound` et
    /// `LibraryStore` n'ont accès à aucun moteur (ni paramètre ni dépendance `EngineControlling`) ;
    /// les seules commandes produites par le module, celles des préférences appliquées au
    /// lancement, ne contiennent ni chargement ni démarrage de moteur.
    func testDemoIsNeverLoadedAutomatically_RM01() {
        for command in AppPreferences.defaults.engineCommands {
            if case .load = command { XCTFail("preferences must never load a sound") }
            if case .motor = command { XCTFail("preferences must never start a motor") }
        }
    }

    private struct NoDecoder: AudioDecoding {
        func probe(url: URL) async throws -> AudioFileInfo { throw LibraryError.unsupportedFormat }
        func decode(url: URL, title: String) async throws -> AudioClip { throw LibraryError.unsupportedFormat }
    }
}
