import ScratchCore
import XCTest
@testable import ScratchUI

/// Forme d'onde : analyse, cache et géométrie de la bande zoomée (story 4.6 ; NFR4, SF-70, RM-57).
@MainActor
final class WaveformTests: XCTestCase {
    /// Clip de `duration` secondes à 3 kHz (10 trames par point), amplitude `level(t)` en créneaux.
    private func clip(duration: Double, sampleRate: Double = 3_000, level: (Double) -> Float = { _ in 0.5 }) -> AudioClip {
        AudioClip(title: "t.wav", sampleRate: sampleRate, frameCount: Int(duration * sampleRate)) { left, right in
            for index in left.indices {
                let value = level(Double(index) / sampleRate)
                left[index] = index.isMultiple(of: 2) ? value : -value
                right[index] = left[index] * 0.5
            }
        }
    }

    private func analyze(_ clip: AudioClip) -> WaveformPeaks? {
        WaveformAnalyzer.analyze(.init(left: clip.left, right: clip.right, sampleRate: clip.sampleRate))
    }

    // AC1 — NFR4 : ≈ 300 points par seconde, 2 Mo au plus pour 10 min.
    func testPeaksSizeAndResolution_NFR4() async throws {
        XCTAssertEqual(WaveformAnalyzer.blockSize(sampleRate: 44_100), 147)
        XCTAssertEqual(WaveformAnalyzer.blockSize(sampleRate: 48_000), 160)
        let peaks = try XCTUnwrap(analyze(clip(duration: 600)))
        XCTAssertEqual(peaks.pointsPerSecond, 300, accuracy: 1e-9)
        XCTAssertEqual(peaks.baseCount, 180_000)
        XCTAssertEqual(peaks.duration, 600, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(peaks.byteCount, 2_000_000, "2 Mo au plus par son, niveaux réduits compris")
        XCTAssertGreaterThan(peaks.levels.count, 10, "multirésolution jusqu'à quelques points")
    }

    // AC1 : enveloppe min/max des deux canaux, à toute résolution ; rien hors du son.
    func testEnvelopeValuesAtEveryResolution() async throws {
        let peaks = try XCTUnwrap(analyze(clip(duration: 4) { $0 < 1 ? 0.5 : ($0 < 2 ? 0 : 1) }))
        let loud = try XCTUnwrap(peaks.envelope(from: 0.1, to: 0.2))
        XCTAssertEqual(loud.min, -0.5, accuracy: 1e-4)
        XCTAssertEqual(loud.max, 0.5, accuracy: 1e-4)
        let silent = try XCTUnwrap(peaks.envelope(from: 1.25, to: 1.75))
        XCTAssertEqual(silent.min, 0, accuracy: 1e-4)
        XCTAssertEqual(silent.max, 0, accuracy: 1e-4)
        let whole = try XCTUnwrap(peaks.envelope(from: 0, to: 4), "coarse level")
        XCTAssertEqual(whole.min, -1, accuracy: 1e-4)
        XCTAssertEqual(whole.max, 1, accuracy: 1e-4)
        XCTAssertNil(peaks.envelope(from: -1, to: -0.5), "lead-in")
        XCTAssertNil(peaks.envelope(from: 4.1, to: 4.2), "after the end")
        XCTAssertLessThan(peaks.level(forSpan: 4).pointsPerSecond, peaks.pointsPerSecond)
    }

    // AC1 — RM-57 : un même clip chargé sur A et B n'est analysé qu'une fois ; libéré après les deux.
    func testSameClipIsAnalyzedOnce_RM57() async throws {
        let cache = WaveformCache()
        let engine = RecordingEngine()
        let deckA = DeckViewModel(deck: .a, engine: engine, waveformCache: cache)
        let deckB = DeckViewModel(deck: .b, engine: engine, waveformCache: cache)
        let shared = clip(duration: 2)
        deckA.loadedClip = shared
        deckB.loadedClip = shared
        XCTAssertEqual(cache.analysisCount, 1)
        let peaksA = try await waitForPeaks(deckA)
        let peaksB = try await waitForPeaks(deckB)
        XCTAssertTrue(peaksA === peaksB)
        deckA.loadedClip = nil
        XCTAssertNil(deckA.peaks)
        XCTAssertEqual(cache.cachedClipCount, 1, "still shown on B")
        deckB.loadedClip = clip(duration: 1)
        XCTAssertEqual(cache.cachedClipCount, 1, "the shared clip is released, the new one cached")
        XCTAssertEqual(cache.analysisCount, 2)
    }

    // AC1 : l'analyse est annulée quand plus aucune platine ne l'attend.
    func testAnalysisIsCancelledWhenReleased() async {
        let cache = WaveformCache { samples, isCancelled in
            let deadline = Date().addingTimeInterval(5)
            while !isCancelled(), Date() < deadline { usleep(1_000) }
            return isCancelled() ? nil : WaveformAnalyzer.analyze(samples)
        }
        let loaded = clip(duration: 1)
        let analysis = cache.retain(loaded)
        cache.release(loaded.id)
        XCTAssertEqual(cache.cachedClipCount, 0)
        let result = await analysis.value
        XCTAssertNil(result)
    }

    // AC2, AC3 — SF-70 : fenêtre de ±1,8 s centrée sur la tête, tuiles translatées, hachures.
    func testZoomWindowFollowsPlayhead_SF70() async {
        let geometry = ZoomGeometry(width: 448)
        XCTAssertEqual(geometry.window(position: 10).lowerBound, 8.2, accuracy: 1e-9)
        XCTAssertEqual(geometry.window(position: 10).upperBound, 11.8, accuracy: 1e-9)
        XCTAssertEqual(geometry.x(of: 10, position: 10), 224, accuracy: 1e-9, "playhead fixed at the center")
        XCTAssertEqual(geometry.x(of: 11.8, position: 10), 448, accuracy: 1e-9)
        for position in [-2.0, -0.4, 0, 10, 299.99] {
            let tiles = geometry.visibleTiles(position: position)
            XCTAssertTrue((1...3).contains(tiles.count), "\(position)")
            XCTAssertLessThanOrEqual(geometry.tileOffset(tiles.lowerBound, position: position), 0)
            XCTAssertGreaterThanOrEqual(geometry.tileOffset(tiles.upperBound, position: position) + 512, 448)
            // The playhead's time sits under the center of the view.
            let tile = Int((position / geometry.tileSeconds).rounded(.down))
            let offsetInTile = (position - geometry.tileRange(tile).lowerBound) / geometry.secondsPerPoint
            XCTAssertEqual(geometry.tileOffset(tile, position: position) + offsetInTile, 224, accuracy: 1e-6)
        }
        // Forward playback scrolls right to left; backward, left to right.
        XCTAssertLessThan(geometry.tileOffset(0, position: 1.1), geometry.tileOffset(0, position: 1))
        XCTAssertGreaterThan(geometry.tileOffset(0, position: 0.9), geometry.tileOffset(0, position: 1))
        XCTAssertEqual(ZoomGeometry.outsideRanges(of: -3 ..< -1, duration: 30), [-3 ..< -1])
        XCTAssertEqual(ZoomGeometry.outsideRanges(of: -1 ..< 1, duration: 30), [-1 ..< 0])
        XCTAssertEqual(ZoomGeometry.outsideRanges(of: 29 ..< 31, duration: 30), [30 ..< 31])
        XCTAssertEqual(ZoomGeometry.outsideRanges(of: 5 ..< 6, duration: 30), [])
    }

    // AC3 — SF-72 : l'aperçu couvre [−2 s ; durée], amorce comprise.
    func testOverviewCoversLeadInAndWholeSound_SF72() async {
        let geometry = OverviewGeometry(width: 488, duration: 120)
        XCTAssertEqual(geometry.x(of: -2), 0, accuracy: 1e-9)
        XCTAssertEqual(geometry.x(of: 0), 8, accuracy: 1e-9, "proportional lead-in")
        XCTAssertEqual(geometry.x(of: 120), 488, accuracy: 1e-9)
        XCTAssertEqual(geometry.seconds(atX: 128), 30, accuracy: 1e-9)
        XCTAssertEqual(geometry.seconds(atX: -10), -2, accuracy: 1e-9, "bounded")
        XCTAssertEqual(geometry.seconds(atX: 600), 120, accuracy: 1e-9, "bounded")
    }

    // AC1 — NFR4 (indicatif) : 10 min à 48 kHz analysées en 1 s au plus, en build release.
    func testAnalysisTime_NFR4() async throws {
        #if DEBUG
        throw XCTSkip("Mesure indicative, en build release seulement (la CI construit en Debug).")
        #else
        let long = clip(duration: 600, sampleRate: 48_000) { Float(sin($0 * 40)) }
        let start = Date()
        let peaks = analyze(long)
        XCTAssertNotNil(peaks)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        #endif
    }

    private struct AnalysisTimeout: Error {}

    private func waitForPeaks(_ deck: DeckViewModel) async throws -> WaveformPeaks {
        for _ in 0..<500 {
            if let peaks = deck.peaks { return peaks }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw AnalysisTimeout()
    }
}
