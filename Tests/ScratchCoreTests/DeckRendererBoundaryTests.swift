import Foundation
import XCTest
@testable import ScratchCore

/// Bornes de la voix : amorce, sillon fermé, lecture jamais hors du clip (story 1.3 CA 8 et 9 ;
/// SF-14, SF-72, RM-09, RM-55 ; Gherkin 6.12). Ces tests passent aussi sous AddressSanitizer :
/// `scripts/linux-test.sh --sanitize=address --filter DeckRendererBoundaryTests`.
final class DeckRendererBoundaryTests: XCTestCase {
    private let outputRate = 48_000.0
    private let reference = TurntableConstants.referenceAngularVelocity

    /// CA8 — RM-09 : têtes posées et en mouvement autour des indices −1, 0, n − 2, n − 1 et n, à
    /// toutes les vitesses (noyau anti-repliement plus large que le clip à 16×) : aucune lecture hors
    /// du clip (vérifiée par les contrôles de bornes en debug et par AddressSanitizer), sorties
    /// finies et bornées, silence hors de ]0 ; durée[.
    func testNoOutOfBoundsReadNearEdges_RM09() {
        for frames in [1, 2, 5, 64] {
            let clip = TestClips.noise(frames: frames)
            let n = Double(frames)
            let indices = [-3, -2, -1.5, -1, -0.5, 0, 0.25, 0.5, 1, n - 2, n - 1.5, n - 1, n - 0.5, n, n + 0.5, n + 1, n + 2]
            for rate in [0.0, 0.5, 1, -1, 2.2, 3, 16, -16] {
                for index in indices {
                    var rig = VoiceRig(clip: clip)
                    let position = index / outputRate
                    let output = rig.render(positions: [Double](repeating: position, count: 64),
                                            rates: [Double](repeating: rate, count: 64))
                    XCTAssertFalse(SignalAnalysis.containsNonFinite(output.left))
                    XCTAssertLessThanOrEqual(SignalAnalysis.peak(output.left), 1.2)
                    if position <= 0 || position >= clip.duration {
                        XCTAssertTrue(output.left.allSatisfy { $0 == 0 } && output.right.allSatisfy { $0 == 0 },
                                      "silent outside the clip: \(frames) frames, index \(index), rate \(rate)")
                    }
                }
                // Sweep across the whole clip and both bounds.
                var rig = VoiceRig(clip: clip)
                let count = 2_048
                let span = (n + 400) / outputRate
                let positions = (0..<count).map { -200 / outputRate + span * Double($0) / Double(count) }
                let output = rig.render(positions: rate < 0 ? positions.reversed() : positions,
                                        rates: [Double](repeating: rate, count: count))
                XCTAssertFalse(SignalAnalysis.containsNonFinite(output.left + output.right))
            }
        }
    }

    /// CA8 — SF-72, RM-09 : l'amorce [−2 s ; 0 s[ est un silence virtuel exact, à toute vitesse.
    func testLeadInIsVirtualSilence_SF72() {
        let clip = TestClips.noise(frames: 48_000)
        for rate in [-16.0, -1, 0.3, 1, 3, 16] {
            var rig = VoiceRig(clip: clip)
            let positions = (0..<4_800).map { -2 + 1.999 * Double($0) / 4_800 }
            let output = rig.render(positions: positions, rates: [Double](repeating: rate, count: positions.count))
            XCTAssertTrue(output.left.allSatisfy { $0 == 0 }, "rate \(rate)")
        }
    }

    // MARK: Gherkin 6.12 de bout en bout (physique + voix)

    /// Différence maximale attendue entre deux échantillons pour une sinusoïde de `frequency`
    /// d'amplitude 1 lue à `rate`, plus la pente d'un fondu de bord de `fade` secondes de son.
    private func naturalStep(frequency: Double, rate: Double, fade: Double = .infinity) -> Double {
        2 * Double.pi * frequency * rate / outputRate + Double.pi / 2 * rate / (fade * outputRate)
    }

    /// CA9 — 6.12 « Reculer dans l'amorce », « Dépasser la borne de l'amorce en reculant » : un
    /// demi-tour arrière depuis 0 s mène à −0,9 s en silence ; la tête se bloque à −2 s sans bruit ;
    /// la poussée joue l'attaque en avant, sans clic.
    func testLeadInStopAndAttack_RM55_6_12() {
        let harness = VoiceHarness(clip: TestClips.sine(frequency: 1_000, seconds: 4, amplitude: 0.5))
        let start = harness.time
        harness.schedule(from: start, to: start + 6, release: false) { t in
            let u = t - start
            if u < 0.3 { return -.pi * u / 0.3 }                        // half a turn back
            if u < 0.8 { return -.pi }
            if u < 1.4 { return -.pi - 2 * .pi * (u - 0.8) / 0.6 }      // one more turn back: −2 s stop
            if u < 1.9 { return -3 * .pi }
            if u < 4.4 { return -3 * .pi + self.reference * (u - 1.9) }  // forward at nominal speed
            return -3 * .pi + self.reference * 2.5
        }
        let back = harness.run(seconds: 0.8)
        XCTAssertEqual(harness.physics.positionSeconds, -0.9, accuracy: 1e-3, "half a turn back from 0 s")
        XCTAssertTrue(back.left.allSatisfy { $0 == 0 }, "the lead-in is silent")
        let stop = harness.run(seconds: 1.1)
        XCTAssertEqual(harness.physics.positionSeconds, -2, "blocked at −2 s")
        XCTAssertTrue(stop.left.allSatisfy { $0 == 0 }, "no noise at the lead-in stop")

        let forward = harness.run(seconds: 2.6)
        guard let attack = forward.positions.firstIndex(where: { $0 > 0 }) else { return XCTFail("never reached 0 s") }
        XCTAssertTrue(forward.left[..<attack].allSatisfy { $0 == 0 })
        XCTAssertGreaterThan(SignalAnalysis.peak(forward.left[attack..<(attack + 2_400)]), 0.45, "the attack is played forward")
        let rate = forward.rates[attack...].map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(SignalAnalysis.maximumStep(forward.left),
                                 0.5 * naturalStep(frequency: 1_000, rate: rate, fade: DeckRenderer.startFadeSeconds) * 1.05,
                                 "no click entering the sound")
    }

    /// CA9 — 6.12 « Atteindre la fin du son moteur actif (sillon fermé) », « Revenir dans le son
    /// depuis le sillon fermé » : un son qui finit en pleine amplitude s'arrête sans clic, le disque
    /// continue de tourner, la tête reste à la fin ; tiré en arrière, le son revient aussitôt.
    func testClosedGrooveEndsWithoutClickAndReturnsImmediately_RM55_6_12() {
        // 1 kHz cosine of 4 s: the clip ends on a full-scale crest (hard cut in the file).
        let clip = TestClips.sine(frequency: 1_000, seconds: 4, phase: .pi / 2)
        XCTAssertGreaterThan(abs(clip.left[clip.frameCount - 1]), 0.99)
        let harness = VoiceHarness(clip: clip)
        harness.physics.setMotorTimings(MotorTimings(slipmatCatchUp: 0))
        harness.physics.setMotor(true)
        harness.run(seconds: 1.2)
        harness.physics.seek(to: 3.9)
        let end = harness.run(seconds: 2.5)
        guard let arrival = end.positions.firstIndex(where: { $0 >= 4 }) else { return XCTFail("never reached the end") }
        XCTAssertLessThanOrEqual(SignalAnalysis.maximumStep(end.left[480...]),
                                 naturalStep(frequency: 1_000, rate: 1, fade: DeckRenderer.endFadeSeconds) * 1.05,
                                 "the sound stops without click")
        XCTAssertTrue(end.left[arrival...].allSatisfy { $0 == 0 }, "silence at the end")
        XCTAssertTrue(end.positions[arrival...].allSatisfy { $0 == 4 }, "the head stays at the end")
        XCTAssertEqual(end.rates.last ?? 0, 1, accuracy: 1e-9, "the disc keeps turning")

        // Pull the disc back.
        let start = harness.time
        harness.schedule(from: start, to: start + 1, release: false) { -.pi / 2 * min(1, ($0 - start) / 0.3) }
        let back = harness.run(seconds: 0.4)
        guard let backward = back.rates.firstIndex(where: { $0 < 0 }) else { return XCTFail("never moved back") }
        let inSound = back.positions.firstIndex(where: { $0 < 4 }) ?? back.positions.count
        XCTAssertLessThanOrEqual(inSound - backward, 1, "back in the sound from the first backward sample")
        guard let pastFade = back.positions.firstIndex(where: { $0 < 4 - DeckRenderer.endFadeSeconds }) else {
            return XCTFail("never left the end fade")
        }
        XCTAssertGreaterThan(SignalAnalysis.peak(back.left[pastFade..<(pastFade + 480)]), 0.9,
                             "the sound is read backwards from the end, without unwinding")
        XCTAssertLessThan(Double(pastFade - inSound) / outputRate, 0.05, "within a few milliseconds")
    }

    /// CA9 — 6.12 « Son très court » (scénario de vérification) : un son de 0,2 s qui commence et
    /// finit en pleine amplitude, scratché d'un quart de tour (0,45 s de son) dans les deux sens :
    /// lecture dans ses bornes uniquement et aucun clic aux bornes.
    func testVeryShortSoundScratchedAcrossBothBounds_6_12() {
        let clip = TestClips.sine(frequency: 1_000, seconds: 0.2, phase: .pi / 2)
        XCTAssertEqual(clip.left[0], 1)
        let harness = VoiceHarness(clip: clip)
        harness.physics.seek(to: 0.1)
        let start = harness.time
        let quarter = Double.pi / 2
        harness.schedule(from: start, to: start + 2.5, release: false) { t in
            let u = t - start
            // +¼ turn, −¼, −¼, +¼, each in 0.3 s, with short holds.
            let keys: [(Double, Double)] = [(0, 0), (0.3, quarter), (0.5, quarter), (0.8, 0), (1.0, 0),
                                            (1.3, -quarter), (1.5, -quarter), (1.8, 0), (2.5, 0)]
            for (a, b) in zip(keys, keys.dropFirst()) where u <= b.0 {
                return a.1 + (b.1 - a.1) * (u - a.0) / (b.0 - a.0)
            }
            return 0
        }
        let output = harness.run(seconds: 2.5)
        XCTAssertGreaterThanOrEqual(output.positions.max() ?? 0, 0.2, "pushed against the end")
        XCTAssertLessThan(output.positions.min() ?? 0, -0.1, "pulled into the lead-in")
        XCTAssertFalse(SignalAnalysis.containsNonFinite(output.left))
        let inside = zip(output.positions, output.left).filter { $0.0 > 0.01 && $0.0 < 0.19 }.map(\.1)
        XCTAssertGreaterThan(SignalAnalysis.peak(inside), 0.5, "read forwards and backwards within its bounds")
        let outside = zip(output.positions, output.left).filter { $0.0 <= 0 || $0.0 >= 0.2 }.map(\.1)
        XCTAssertTrue(outside.allSatisfy { $0 == 0 }, "silent outside the clip")
        let rate = output.rates.map(abs).max() ?? 0
        let clickFree = naturalStep(frequency: 1_000, rate: rate, fade: DeckRenderer.startFadeSeconds) * 1.05
        XCTAssertLessThanOrEqual(SignalAnalysis.maximumStep(output.left), clickFree,
                                 "no click at the bounds (a hard cut would be a step of 1)")
        XCTAssertLessThan(clickFree, 0.6)
    }
}
