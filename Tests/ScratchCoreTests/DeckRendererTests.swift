import Foundation
import XCTest
@testable import ScratchCore

/// Voix de lecture (story 1.3 ; spec v2.1 §5.1 point 4, SF-07 à SF-09, SF-13, SF-71, SF-77, SF-80,
/// RM-04, RM-05, RM-08, RM-50 ; architecture §6.5). Sortie à 48 kHz sauf mention contraire.
final class DeckRendererTests: XCTestCase {
    private let outputRate = 48_000.0
    /// 20 premières millisecondes exclues des mesures (montée du gain de mouvement).
    private let settle = 960

    private func analytic(_ frequency: Double, _ positions: ArraySlice<Double>, amplitude: Double = 1) -> [Float] {
        positions.map { Float(amplitude * sin(2 * Double.pi * frequency * $0)) }
    }

    // MARK: CA 1, 2 — Position → son

    /// CA1 — RM-04, RM-50, 5.1 §4 : de bout en bout (physique + voix), la voix lit le clip à la
    /// position de la physique, et un tour de disque (1,8 s à 33⅓) déplace la tête de 1,8 s de son à
    /// un échantillon près.
    func testOneRevolutionIsOnePointEightSecondsOfSound_RM50() {
        let clip = TestClips.positionRamp(seconds: 30)
        let harness = VoiceHarness(clip: clip)
        harness.physics.setMotorTimings(MotorTimings(slipmatCatchUp: 0))
        harness.physics.setMotor(true)
        harness.run(seconds: 1.2)
        let output = harness.run(samples: 86_401)
        let secondsPerUnit = Double(clip.frameCount) / clip.sampleRate / 0.5
        let decoded = output.left.map { Double($0) * secondsPerUnit }
        let sample = 1 / clip.sampleRate
        XCTAssertEqual(decoded[86_400] - decoded[0], 1.8, accuracy: sample, "one revolution = 1.8 s of sound")
        let largestGap = zip(decoded, output.positions).map { abs($0 - $1) }.max() ?? 1
        XCTAssertLessThan(largestGap, sample, "the voice reads where the physics puts the head")
    }

    /// CA2 — RM-05, SF-07, SF-08, SF-09 : le son lu est le son chargé, à l'endroit, à l'envers et à
    /// vitesse double (échantillons exacts aux positions entières).
    func testForwardAndBackwardReadTheLoadedClip_RM05() {
        let clip = TestClips.noise(frames: 48_000)
        for (start, rate) in [(1_000, 1), (40_000, -1), (1_000, 2), (40_000, -2)] {
            var rig = VoiceRig(clip: clip)
            let count = 4_800
            let positions = (0..<count).map { Double(start + rate * $0) / outputRate }
            let output = rig.render(positions: positions, rates: [Double](repeating: Double(rate), count: count))
            var largest: Float = 0
            for index in 48..<count {
                largest = max(largest, abs(output.left[index] - clip.left[start + rate * index]))
                largest = max(largest, abs(output.right[index] - clip.right[start + rate * index]))
            }
            XCTAssertLessThan(largest, 1e-5, "rate \(rate): the loaded clip, sample for sample")
        }
    }

    // MARK: CA 3, 4, 5 — Qualité (SF-77)

    /// CA3 — SF-77 : Hermite 4 points, sinusoïde de 1 kHz lue à vitesse constante de 0,25× à 2× :
    /// écart au signal analytique ≤ −60 dB.
    func testHermiteErrorBelowMinus60dB_SF77() {
        let clip = TestClips.sine(frequency: 1_000, seconds: 3)
        for rate in [0.25, 0.5, 1.0, 1.37, 1.5, 2.0] {
            var rig = VoiceRig(clip: clip)
            let trajectory = VoiceRig.constantRate(rate, from: 0.5, samples: 24_000 + settle)
            let output = rig.render(positions: trajectory.positions, rates: trajectory.rates)
            let reference = analytic(1_000, trajectory.positions[settle...])
            let error = zip(output.left[settle...], reference).map { $0 - $1 }
            let relative = SignalAnalysis.decibels(SignalAnalysis.rms(error) / SignalAnalysis.rms(reference))
            XCTAssertLessThanOrEqual(relative, -60, "rate \(rate): \(relative) dB")
        }
    }

    /// CA4 — SF-77, D-13 (scénario « Repliement atténué à 3× ») : 12 kHz à −6 dBFS lu à 3× (36 kHz,
    /// replié à 12 kHz) : la composante repliée est au moins 40 dB sous −6 dBFS ; une composante
    /// sous la coupure (2 kHz lu à 3×) passe à 0,5 dB près.
    func testAliasingOf12kHzAt3xIsAtLeast40dBDown_SF77_D13() {
        let alias = TestClips.sine(frequency: 12_000, seconds: 3, amplitude: 0.5)
        var rig = VoiceRig(clip: alias)
        let trajectory = VoiceRig.constantRate(3, from: 0.1, samples: 24_000 + settle)
        let output = Array(rig.render(positions: trajectory.positions, rates: trajectory.rates).left[settle...])
        let folded = SignalAnalysis.toneAmplitude(output, frequency: 12_000, sampleRate: outputRate)
        let rejection = SignalAnalysis.decibels(folded / 0.5)
        XCTAssertLessThanOrEqual(rejection, -40, "folded 12 kHz: \(rejection) dB under the input")
        XCTAssertLessThanOrEqual(SignalAnalysis.levelDBFS(output), -46, "nothing else leaks either")

        let passband = TestClips.sine(frequency: 2_000, seconds: 3, amplitude: 0.5)
        var passRig = VoiceRig(clip: passband)
        let passOutput = Array(passRig.render(positions: trajectory.positions, rates: trajectory.rates).left[settle...])
        let level = SignalAnalysis.toneAmplitude(passOutput, frequency: 6_000, sampleRate: outputRate)
        XCTAssertEqual(SignalAnalysis.decibels(level / 0.5), 0, accuracy: 0.5, "6 kHz out at 3× is kept")
    }

    /// T3 : franchir le seuil de 2× (fondu des deux chemins entre 2× et 2,5×) ne crée ni marche de
    /// niveau ni clic : 2 kHz lu en rampe de vitesse de 1,5× à 3,5×.
    func testAntiAliasingThresholdTransitionIsSmooth_SF77() {
        let clip = TestClips.sine(frequency: 2_000, seconds: 6)
        var rig = VoiceRig(clip: clip)
        let count = 48_000
        var positions = [Double]()
        var rates = [Double]()
        var position = 0.5
        for index in 0..<count {
            let rate = 1.5 + 2 * Double(index) / Double(count)
            position += rate / outputRate
            positions.append(position)
            rates.append(rate)
        }
        let output = rig.render(positions: positions, rates: rates).left
        // 2 kHz stays in the passband of both paths: per 10 ms window, the output matches the
        // analytic signal (a level or timbre step of 1 % would show at −40 dB).
        let reference = analytic(2_000, positions[...])
        var worst = SignalAnalysis.floorDB
        for start in stride(from: settle, to: count - 480, by: 480) {
            let window = start..<(start + 480)
            let error = zip(output[window], reference[window]).map { $0 - $1 }
            worst = max(worst, SignalAnalysis.decibels(SignalAnalysis.rms(error) / SignalAnalysis.rms(reference[window])))
        }
        XCTAssertLessThanOrEqual(worst, -40, "no level or timbre step across 2×–2.5×: \(worst) dB")
        XCTAssertLessThanOrEqual(SignalAnalysis.maximumStep(output[settle...]), 2 * Double.pi * 2_000 * 3.5 / outputRate * 1.01)
    }

    /// CA5 — SF-77 : vitesse bornée à ±16 : au-delà, la voix traite la vitesse comme 16 (sortie
    /// identique) ; de bout en bout, un doigt à 30 × ωref donne une vitesse de lecture de 16 au plus.
    func testRateIsClampedTo16x_SF77() {
        let clip = TestClips.noise(frames: 480_000)
        let trajectory = VoiceRig.constantRate(16, from: 1, samples: 4_800)
        var clamped = VoiceRig(clip: clip)
        var excessive = VoiceRig(clip: clip)
        let reference = clamped.render(positions: trajectory.positions, rates: trajectory.rates)
        let output = excessive.render(positions: trajectory.positions, rates: trajectory.rates.map { $0 * 2.5 })
        XCTAssertEqual(output.left, reference.left)
        XCTAssertFalse(SignalAnalysis.containsNonFinite(output.left))

        let harness = VoiceHarness(clip: clip)
        harness.physics.seek(to: 2)
        let start = harness.time
        harness.schedule(from: start, to: start + 0.3, release: false) { 30 * TurntableConstants.referenceAngularVelocity * ($0 - start) }
        let scratched = harness.run(seconds: 0.3)
        XCTAssertEqual(scratched.rates.max() ?? 0, 16, accuracy: 1e-12)
        XCTAssertFalse(SignalAnalysis.containsNonFinite(scratched.left))
        XCTAssertLessThanOrEqual(SignalAnalysis.peak(scratched.left), 1)
    }

    /// CA5 — SF-77, 5.1 §4 : sinusoïde de 200 Hz scratchée, touches à 120 Hz livrées à 60 et 120 Hz
    /// (rejeu régulé par défaut) : énergie au-delà de 8 kHz ≤ −50 dBFS (aucune marche de vitesse).
    func testScratchedSineHasNoHighFrequencySteps_SF77() {
        for display in [60.0, 120.0] {
            let harness = VoiceHarness(clip: TestClips.sine(frequency: 200, seconds: 10),
                                       finger: FingerTrajectory.Configuration())
            harness.displayRate = display
            harness.physics.seek(to: 4)
            let start = harness.time
            harness.schedule(from: start, to: start + 2.5, touchRate: 120, release: false) {
                .pi / 2 * sin(2 * .pi * 1.5 * ($0 - start))
            }
            harness.run(seconds: 0.5)
            let output = harness.run(samples: 65_536)
            XCTAssertGreaterThan(output.rates.map(abs).max() ?? 0, 3, "a real scratch (> 3×)")
            let level = SignalAnalysis.levelAbove(8_000, in: output.left, sampleRate: outputRate)
            XCTAssertLessThanOrEqual(level, -50, "display \(display) Hz: \(level) dBFS above 8 kHz")
        }
    }

    /// CA6 — RM-08 (6.3 « Enchaîner des inversions rapides (baby scratch) ») : huit allers-retours par
    /// seconde sur un quart de tour : critère du CA5 respecté et retour au point de départ à ±10 ms.
    func testBabyScratchReturnsToStartWithin10ms_6_3() {
        let harness = VoiceHarness(clip: TestClips.sine(frequency: 200, seconds: 10),
                                   finger: FingerTrajectory.Configuration())
        harness.displayRate = 120
        harness.physics.seek(to: 4)
        let startPosition = harness.physics.positionSeconds
        let start = harness.time
        harness.schedule(from: start, to: start + 2, touchRate: 120, release: false) { t in
            let u = t - start
            return u < 1.5 ? .pi / 4 * sin(2 * .pi * 8 * u) : 0
        }
        harness.run(seconds: 0.2)
        let output = harness.run(samples: 65_536)
        let reversals = zip(output.rates.dropFirst(), output.rates).filter { $0.sign != $1.sign }.count
        XCTAssertGreaterThanOrEqual(reversals, 16, "eight back-and-forth movements per second")
        let level = SignalAnalysis.levelAbove(8_000, in: output.left, sampleRate: outputRate)
        XCTAssertLessThanOrEqual(level, -50, "\(level) dBFS above 8 kHz")
        harness.run(seconds: 1)
        XCTAssertEqual(harness.physics.positionSeconds, startPosition, accuracy: 0.010, "back to the start ± 10 ms")
    }

    // MARK: CA 7 — Disque immobile

    /// CA7 (6.3 « Maintenir un disque immobile ») : à vitesse nulle, la tête ne parcourt aucun
    /// échantillon et la sortie est silencieuse en régime établi, même sur un échantillon non nul ;
    /// l'arrêt ne clique pas.
    func testZeroSpeedIsSilent_6_3() {
        let clip = TestClips.sine(frequency: 100, seconds: 3)
        var rig = VoiceRig(clip: clip)
        // Head on a crest (sample ≈ 1), moving at 1× for 0.2 s, then stopped for 1 s.
        var trajectory = VoiceRig.constantRate(1, from: 0.4975, samples: 9_600)
        let stop = trajectory.positions.last!
        trajectory.positions += [Double](repeating: stop, count: 48_000)
        trajectory.rates += [Double](repeating: 0, count: 48_000)
        let output = rig.render(positions: trajectory.positions, rates: trajectory.rates).left
        XCTAssertGreaterThan(abs(sin(2 * .pi * 100 * stop)), 0.9, "a non-zero sample under the head")
        XCTAssertLessThanOrEqual(SignalAnalysis.peakDBFS(output[(9_600 + 24_000)...]), -60, "silent once stopped")
        XCTAssertLessThanOrEqual(SignalAnalysis.maximumStep(output[settle...]), 2 * Double.pi * 100 / outputRate * 1.01,
                                 "the stop does not click")

        // End to end: the disc held still under a fixed finger, motor running.
        let harness = VoiceHarness(clip: clip)
        harness.physics.setMotor(true)
        harness.run(seconds: 1.2)
        let start = harness.time
        harness.schedule(from: start, to: start + 2, release: false) { _ in 0 }
        harness.run(seconds: 1)
        let held = harness.run(seconds: 1)
        XCTAssertLessThan((held.positions.max() ?? 1) - (held.positions.min() ?? 0), 1 / outputRate,
                          "no new sample is read")
        XCTAssertLessThanOrEqual(SignalAnalysis.peakDBFS(held.left), -60)
    }

    /// CA7, 6.3 « Lancer le son depuis le repère », 6.9 « Rattrapage réglable » : le silence du disque
    /// immobile n'adoucit pas l'attaque d'un release (pleine amplitude en 2 ms), même à T = 0, sans clic.
    func testReleaseAttackIsNotSoftened_6_3() {
        let harness = VoiceHarness(clip: TestClips.sine(frequency: 1_000, seconds: 10))
        harness.physics.setMotorTimings(MotorTimings(slipmatCatchUp: 0))
        harness.physics.seek(to: 3)
        harness.physics.setMotor(true)
        let start = harness.time
        harness.schedule(from: start, to: start + 1.5) { _ in 0 }
        harness.run(seconds: 1.2)
        let output = harness.run(seconds: 0.5)
        guard let release = output.rates.firstIndex(where: { $0 > 0.5 }) else { return XCTFail("never released") }
        XCTAssertLessThanOrEqual(SignalAnalysis.peakDBFS(output.left[(release - 4_800)..<release]), -60, "silent before")
        XCTAssertGreaterThan(SignalAnalysis.peak(output.left[(release + 96)..<(release + 144)]), 0.95, "full level within 2 ms")
        // Natural slope of the sine plus the 1 ms rise of the motion gain: a click would be ≈ 1.
        XCTAssertLessThanOrEqual(SignalAnalysis.maximumStep(output.left[(release - 10)...]),
                                 (2 * Double.pi * 1_000 / outputRate + 1 / 48.0) * 1.01, "no click")
    }

    // MARK: CA 10 — Sauts

    /// CA10 — SF-13, SF-71 : un saut (CUE, needle drop) fond l'ancienne position dans la nouvelle en
    /// 5 ms : pas de marche malgré une opposition de phase, son de la nouvelle position ensuite.
    func testJumpCrossfadeWithin5ms_SF13_SF71() {
        let harness = VoiceHarness(clip: TestClips.sine(frequency: 1_000, seconds: 10))
        harness.physics.setMotorTimings(MotorTimings(slipmatCatchUp: 0))
        harness.physics.seek(to: 2)
        harness.physics.setMotor(true)
        harness.run(seconds: 1.2)
        // Half a period ahead: the new head is in phase opposition with the old one.
        harness.physics.seek(to: harness.physics.positionSeconds + 0.000_5 + 0.25)
        let output = harness.run(samples: 960)
        XCTAssertFalse(harness.channel.renderer.isCrossfading)
        let natural = 2 * Double.pi * 1_000 / outputRate
        XCTAssertLessThanOrEqual(SignalAnalysis.maximumStep(output.left), natural * 1.6, "no click at the jump")
        XCTAssertLessThan(abs(output.left[119]), 0.05, "mid-fade: opposite phases cancel")
        let reference = analytic(1_000, output.positions[240...])
        let largest = zip(output.left[240...], reference).map { abs($0 - $1) }.max() ?? 1
        XCTAssertLessThan(largest, 1e-3, "the new position alone after 5 ms (240 samples)")
    }

    /// Signal de saut de `DeckPhysics` : origine du premier saut d'un bloc, effacée une fois lue et au
    /// chargement.
    func testPhysicsReportsJumpOriginOncePerBlock() {
        var physics = DeckPhysics(sampleRate: outputRate)
        physics.reset(duration: 30)
        XCTAssertNil(physics.takeJumpOrigin())
        physics.seek(to: 12)
        physics.setCue()
        physics.seek(to: 20)
        XCTAssertEqual(physics.pendingJumpOrigin, 0, "the sound playing before the first jump")
        XCTAssertEqual(physics.takeJumpOrigin(), 0)
        XCTAssertNil(physics.takeJumpOrigin())
        physics.recallCue()
        XCTAssertEqual(physics.takeJumpOrigin(), 20)
        physics.seek(to: 3)
        physics.reset(duration: 10)
        XCTAssertNil(physics.takeJumpOrigin(), "a load is not crossfaded")
    }

    // MARK: CA 11, 12

    /// CA11 — SF-80, D-22, 6.15 (scénario « Hauteur indépendante de la fréquence du clip ») : un clip
    /// de 1 kHz à 22,05, 44,1, 48 ou 96 kHz est restitué à 1 kHz ± 1 Hz, en sortie à 48 et 44,1 kHz.
    func testPitchIndependentOfClipSampleRate_SF80_6_15() {
        for output in [48_000.0, 44_100] {
            for clipRate in [22_050.0, 44_100, 48_000, 96_000] {
                let clip = TestClips.sine(frequency: 1_000, seconds: 2, sampleRate: clipRate)
                var rig = VoiceRig(clip: clip, outputSampleRate: output)
                let count = Int(output) + settle
                let trajectory = VoiceRig.constantRate(1, from: 0.25, samples: count, outputSampleRate: output)
                let rendered = Array(rig.render(positions: trajectory.positions, rates: trajectory.rates).left[settle...])
                let frequency = SignalAnalysis.zeroCrossingFrequency(rendered, sampleRate: output)
                XCTAssertEqual(frequency, 1_000, accuracy: 1, "clip \(clipRate) Hz, output \(output) Hz")
            }
        }
    }

    /// CA12 : rendu à chaque échantillon, indépendant du découpage en blocs (déterminisme).
    func testOutputDoesNotDependOnBlockSize() {
        let clip = TestClips.noise(frames: 96_000)
        var positions = [Double]()
        var rates = [Double]()
        var position = 0.2
        for index in 0..<24_000 {
            let rate = 6 * sin(2 * Double.pi * 3 * Double(index) / outputRate)
            position += rate / outputRate
            positions.append(position)
            rates.append(rate)
        }
        var reference: [Float]?
        for block in [1, 64, 512] {
            var rig = VoiceRig(clip: clip)
            let output = rig.render(positions: positions, rates: rates, block: block).left
            if let reference { XCTAssertEqual(output, reference, "block \(block)") } else { reference = output }
        }
    }

    func testEmptyDeckIsSilent_RM01() {
        var rig = VoiceRig(clip: nil)
        let trajectory = VoiceRig.constantRate(1, from: 0, samples: 512)
        let output = rig.render(positions: trajectory.positions, rates: trajectory.rates)
        XCTAssertTrue(output.left.allSatisfy { $0 == 0 })
        XCTAssertTrue(output.right.allSatisfy { $0 == 0 })
    }
}
