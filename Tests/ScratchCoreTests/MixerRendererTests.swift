import Foundation
import XCTest
@testable import ScratchCore

/// Banc de la table de mixage : voies A et B synthétiques, rendu par blocs.
private struct MixerRig {
    var mixer = MixerRenderer(outputSampleRate: 48_000)

    struct Output {
        var left: [Float] = []
        var right: [Float] = []
        var blocks: [(gains: DeckPair<Double>, peaks: DeckPair<Double>, outputPeak: Double, reduction: Double)] = []
    }

    /// Rend `frames` échantillons par blocs de `block` ; `a(n)` et `b(n)` donnent les entrées.
    mutating func run(frames: Int, block: Int = 256, from offset: Int = 0,
                      a: (Int) -> Float, b: (Int) -> Float) -> Output {
        var output = Output()
        var start = 0
        while start < frames {
            let count = min(block, frames - start)
            let aL = (0..<count).map { a(offset + start + $0) }
            let bL = (0..<count).map { b(offset + start + $0) }
            var left = [Float](repeating: .nan, count: count)
            var right = [Float](repeating: .nan, count: count)
            aL.withUnsafeBufferPointer { ap in
                bL.withUnsafeBufferPointer { bp in
                    left.withUnsafeMutableBufferPointer { l in
                        right.withUnsafeMutableBufferPointer { r in
                            mixer.mix(a: (ap.baseAddress!, ap.baseAddress!), b: (bp.baseAddress!, bp.baseAddress!),
                                      frameCount: count, left: l.baseAddress!, right: r.baseAddress!)
                        }
                    }
                }
            }
            output.left += left
            output.right += right
            output.blocks.append((mixer.channelGains, mixer.channelPeaks, mixer.outputPeak, mixer.limiterReduction))
            start += count
        }
        return output
    }

    /// Laisse les gains rejoindre leurs cibles.
    mutating func settle() {
        _ = run(frames: 1_024, a: { _ in 0 }, b: { _ in 0 })
    }
}

/// Table de mixage (story 1.4 ; spec 3.2, 3.5, 5.2, SF-12, SF-65 à SF-67, RM-06, RM-08, RM-52 ;
/// D-06, D-13, D-26). Sortie à 48 kHz.
final class MixerRendererTests: XCTestCase {
    private let ceiling = Double(SoftLimiter.ceiling)

    private func peak<C: Collection>(_ samples: C) -> Double where C.Element == Float {
        samples.reduce(0.0) { max($0, abs(Double($1))) }
    }

    private func maximumStep(_ samples: [Float]) -> Double {
        zip(samples.dropFirst(), samples).map { abs(Double($0) - Double($1)) }.max() ?? 0
    }

    private func sine(_ frequency: Double, amplitude: Double = 1) -> (Int) -> Float {
        { Float(amplitude * sin(2 * Double.pi * frequency * Double($0) / 48_000)) }
    }

    // MARK: CA 1 — Gain de voie

    /// CA1 — 3.2 : faders à 100 %, crossfader au centre, coupure franche, hamster désactivé ; les deux
    /// voies sont ouvertes (gain 1) après la montée du premier tampon.
    func testInitialMixerState_3_2() {
        var rig = MixerRig()
        XCTAssertEqual(rig.mixer.crossfader, 0.5)
        XCTAssertEqual(rig.mixer.crossfaderCurve, 1)
        XCTAssertFalse(rig.mixer.hamster)
        XCTAssertEqual(rig.mixer.lineFaders, DeckPair(repeating: 1))
        XCTAssertEqual(rig.mixer.momentaryCuts, DeckPair(repeating: false))
        XCTAssertEqual(rig.mixer.channelGains, DeckPair(repeating: 0), "silent before the first block")
        let output = rig.run(frames: 512, a: { _ in 0.25 }, b: { _ in 0.25 })
        XCTAssertEqual(output.blocks.last?.gains, DeckPair(repeating: 1))
        XCTAssertEqual(Double(output.left.last ?? 0), 0.5, accuracy: 1e-6)
    }

    /// CA1 — SF-65, RM-52, D-06 : gain = fader × gain du crossfader (position inversée si hamster),
    /// sur une grille de réglages ; la sortie est la somme des voies pondérées.
    func testChannelGainIsFaderTimesCrossfader_SF65_RM52() {
        for hamster in [false, true] {
            for curve in [0.0, 0.6, 1] {
                for x in [0.0, 0.02, 0.25, 0.5, 0.9, 1] {
                    var rig = MixerRig()
                    rig.mixer.setLineFader(.a, 0.5)
                    rig.mixer.setLineFader(.b, 0.8)
                    rig.mixer.setCrossfaderCurve(curve)
                    rig.mixer.setCrossfader(x)
                    rig.mixer.setHamster(hamster)
                    rig.settle()
                    let gains = CrossfaderCurve.gains(position: hamster ? 1 - x : x, curve: curve)
                    let label = "hamster \(hamster), curve \(curve), x \(x)"
                    XCTAssertEqual(rig.mixer.channelGains.a, 0.5 * gains.a, accuracy: 1e-12, label)
                    XCTAssertEqual(rig.mixer.channelGains.b, 0.8 * gains.b, accuracy: 1e-12, label)
                    let output = rig.run(frames: 256, a: { _ in 0.3 }, b: { _ in -0.2 })
                    XCTAssertEqual(Double(output.left[100]), 0.3 * 0.5 * gains.a - 0.2 * 0.8 * gains.b, accuracy: 1e-6, label)
                }
            }
        }
    }

    // MARK: CA 3 — Lissage

    /// Gains échantillon par échantillon d'une voie, mesurés sur une entrée constante de 0,5 (sous le
    /// plafond du limiteur).
    private func gainTrace(_ rig: inout MixerRig, deck: DeckID, frames: Int) -> [Double] {
        let output = rig.run(frames: frames, a: { _ in deck == .a ? 0.5 : 0 }, b: { _ in deck == .b ? 0.5 : 0 })
        return output.left.map { Double($0) / 0.5 }
    }

    /// CA3 — RM-52, RM-08 : en courbe douce, crossfader et fader rejoignent leur cible en 5 ms
    /// (240 échantillons), par pas réguliers, sans marche.
    func testGainsAreSmoothedWithin5ms_RM52() {
        var rig = MixerRig()
        rig.mixer.setCrossfaderCurve(0)
        rig.mixer.setCrossfader(0)
        rig.settle()
        rig.mixer.setCrossfader(1) // B opens at the start of the next block
        let trace = gainTrace(&rig, deck: .b, frames: 480)
        guard let reached = trace.firstIndex(where: { $0 >= 1 - 1e-12 }) else { return XCTFail("never reached") }
        XCTAssertLessThanOrEqual(reached + 1, 240, "within 5 ms")
        XCTAssertGreaterThan(reached + 1, 48, "soft curve: not the 1 ms hard-cut rise")
        XCTAssertLessThanOrEqual(maximumStep(trace.map(Float.init)), 1.0 / 240 + 1e-6, "no step")

        rig.mixer.setLineFader(.b, 0.2)
        let fader = gainTrace(&rig, deck: .b, frames: 480)
        guard let faded = fader.firstIndex(where: { abs($0 - 0.2) < 1e-6 }) else { return XCTFail("fader never settled") }
        XCTAssertLessThanOrEqual(faded + 1, 240)
        XCTAssertLessThanOrEqual(maximumStep(fader.map(Float.init)), 0.8 / 240 + 1e-6)
    }

    /// CA3 — RM-52 (scénario « Montée en coupure franche ») : crossfader de la butée B à la butée A au
    /// début d'un tampon : gain de A > 0,99 au plus 48 échantillons plus tard, pas ≤ 1/8.
    func testHardCutRisesWithin1ms_RM52() {
        var rig = MixerRig()
        rig.mixer.setCrossfader(1)
        rig.settle()
        XCTAssertEqual(rig.mixer.channelGains.a, 0)
        rig.mixer.setCrossfader(0)
        let trace = gainTrace(&rig, deck: .a, frames: 256)
        guard let open = trace.firstIndex(where: { $0 > 0.99 }) else { return XCTFail("never opened") }
        XCTAssertLessThanOrEqual(open + 1, 48, "above 0.99 within 48 samples (1 ms)")
        XCTAssertLessThanOrEqual(maximumStep(trace.map(Float.init)), 1.0 / 8, "no step above 1/8")
        XCTAssertEqual(trace[47], 1, accuracy: 1e-12)
    }

    /// CA4 — SF-67 (6.10 « Activer le hamster ») : crossfader en butée gauche, le hamster passe la
    /// butée gauche à la voie B ; bascule lissée en 5 ms au plus, sans clic.
    func testHamsterSwapsSidesWithoutClick_SF67() {
        for curve in [1.0, 0] {
            var rig = MixerRig()
            rig.mixer.setCrossfaderCurve(curve)
            rig.mixer.setCrossfader(0)
            rig.settle()
            XCTAssertEqual(rig.mixer.channelGains.a, 1)
            XCTAssertEqual(rig.mixer.channelGains.b, 0, accuracy: 1e-15)
            rig.mixer.setHamster(true)
            let output = rig.run(frames: 512, a: { _ in 0.4 }, b: { _ in 0.2 })
            XCTAssertEqual(rig.mixer.channelGains.a, 0, accuracy: 1e-15, "left stop is now B (curve \(curve))")
            XCTAssertEqual(rig.mixer.channelGains.b, 1)
            guard let done = output.left.firstIndex(where: { abs($0 - 0.2) < 1e-6 }) else { return XCTFail("never settled") }
            XCTAssertLessThanOrEqual(done + 1, 240, "within 5 ms")
            XCTAssertLessThanOrEqual(maximumStep(output.left), (0.4 + 0.2) / 48 + 1e-6, "no click")
        }
    }

    /// CA5 — 3.5, RM-52, D-06 (scénario « Coupure momentanée », 6.14) : crossfader en butée B, fader A
    /// à 50 % : la coupure de A ouvre la voie à 0,5 en 1 ms et la referme de même ; fader à 0 : voie
    /// muette ; voie déjà ouverte : inchangée ; la coupure de A vise la voie A quel que soit le hamster.
    func testMomentaryCutOpensChannelKeepsFader_D06() {
        for curve in [1.0, 0] {
            var rig = MixerRig()
            rig.mixer.setCrossfaderCurve(curve)
            rig.mixer.setCrossfader(1)
            rig.mixer.setLineFader(.a, 0.5)
            rig.settle()
            rig.mixer.setMomentaryCut(.a, open: true)
            let opening = gainTrace(&rig, deck: .a, frames: 256)
            XCTAssertLessThanOrEqual((opening.firstIndex { $0 >= 0.5 * 0.99 } ?? 999) + 1, 48, "1 ms rise, curve \(curve)")
            XCTAssertEqual(rig.mixer.channelGains.a, 0.5)
            rig.mixer.setMomentaryCut(.a, open: false)
            let closing = gainTrace(&rig, deck: .a, frames: 256)
            XCTAssertLessThanOrEqual((closing.firstIndex { $0 <= 0.5 * 0.01 } ?? 999) + 1, 48, "1 ms fall, curve \(curve)")
            XCTAssertEqual(rig.mixer.channelGains.a, 0, accuracy: 1e-15)
        }

        var muted = MixerRig()
        muted.mixer.setCrossfader(1)
        muted.mixer.setLineFader(.a, 0)
        muted.mixer.setMomentaryCut(.a, open: true)
        muted.settle()
        XCTAssertEqual(muted.mixer.channelGains.a, 0, "a line fader at 0 keeps the channel muted")

        var open = MixerRig()
        open.mixer.setCrossfader(0)
        open.settle()
        open.mixer.setMomentaryCut(.a, open: true)
        let unchanged = gainTrace(&open, deck: .a, frames: 256)
        XCTAssertTrue(unchanged.allSatisfy { $0 == 1 }, "a channel already at 1 is not modified")

        var hamster = MixerRig()
        hamster.mixer.setHamster(true)
        hamster.mixer.setCrossfader(0) // hamster: the left stop is B, A closed
        hamster.settle()
        XCTAssertEqual(hamster.mixer.channelGains.a, 0, accuracy: 1e-15)
        hamster.mixer.setMomentaryCut(.a, open: true)
        hamster.settle()
        XCTAssertEqual(hamster.mixer.channelGains.a, 1, "the A cut targets channel A")
        XCTAssertEqual(hamster.mixer.channelGains.b, 1)
    }

    // MARK: CA 6 — Lecture intacte

    /// CA6 — SF-12, RM-06 (6.4 « Fermer complètement la voie A au crossfader », « Ouvrir la voie A »,
    /// « Fader de voie ») : à travers `ScratchEngine`, position, vitesse et angle de chaque platine sont
    /// identiques à l'échantillon près avec ou sans mouvement du mixeur.
    func testMixerNeverMovesPlayback_RM06_SF12() {
        func makeClip() -> AudioClip {
            AudioClip(title: "clip", sampleRate: 44_100, frameCount: 44_100 * 20) { left, right in
                for i in 0..<left.count {
                    left[i] = Float(sin(Double(i) * 0.05))
                    right[i] = left[i]
                }
            }
        }
        let still = ScratchEngine()
        let moving = ScratchEngine()
        var left = [Float](repeating: 0, count: 256)
        var right = [Float](repeating: 0, count: 256)
        for engine in [still, moving] {
            engine.send(.load(.a, makeClip()))
            engine.send(.load(.b, makeClip()))
            engine.send(.motor(.a, on: true))
            engine.send(.motor(.b, on: true))
        }
        var compared = 0
        for buffer in 0..<400 {
            let time = Double(buffer) * 256 / 48_000
            for engine in [still, moving] {
                // A scratch on deck B, identical on both engines.
                if buffer == 100 { engine.send(.touchBegan(.b, angle: 0, time: time)) }
                if buffer > 100, buffer < 250 { engine.send(.touchMoved(.b, angle: sin(time * 9) - sin(100 * 256 / 48_000 * 9), time: time, predicted: false)) }
                if buffer == 250 { engine.send(.touchEnded(.b, time: time)) }
            }
            moving.send(.crossfader(0.5 + 0.5 * sin(Double(buffer) * 0.3)))
            moving.send(.lineFader(.a, Double(buffer % 7) / 6))
            moving.send(.lineFader(.b, Double(buffer % 5) / 4))
            moving.send(.momentaryCut(buffer % 3 == 0 ? .a : .b, open: buffer % 2 == 0))
            if buffer % 50 == 0 { moving.send(.hamster(buffer % 100 == 0)) }
            if buffer % 40 == 0 { moving.send(.crossfaderCurve(Double(buffer % 120) / 120)) }
            for engine in [still, moving] {
                left.withUnsafeMutableBufferPointer { l in
                    right.withUnsafeMutableBufferPointer { r in
                        engine.render(frameCount: 256, left: l.baseAddress!, right: r.baseAddress!)
                    }
                }
            }
            let a = still.latestSnapshot()
            let b = moving.latestSnapshot()
            for deck in DeckID.allCases {
                XCTAssertEqual(a[deck].positionSeconds, b[deck].positionSeconds, "buffer \(buffer)")
                XCTAssertEqual(a[deck].playbackRate, b[deck].playbackRate)
                XCTAssertEqual(a[deck].discAngle, b[deck].discAngle)
                XCTAssertEqual(a[deck].isHeld, b[deck].isHeld)
                compared += 1
            }
        }
        XCTAssertEqual(compared, 800)
        XCTAssertGreaterThan(still.latestSnapshot()[.a].positionSeconds, 1, "the decks did play")
        XCTAssertNotEqual(still.latestSnapshot().mixer, moving.latestSnapshot().mixer)
    }

    // MARK: CA 7, 8 — Sortie et mesures

    /// CA7 — SF-65, D-13 (6.8 « Pas de saturation à la somme des deux voies ») : deux sinusoïdes à
    /// 0 dBFS, crossfader au centre en coupure franche : crête ≤ −0,1 dBFS, limiteur actif (≥ 1 dB),
    /// pas d'écrêtage.
    func testTwoFullScaleSinesAreLimited_6_8() {
        for (fa, fb) in [(1_000.0, 1_000.0), (440, 1_234)] {
            var rig = MixerRig()
            let output = rig.run(frames: 48_000, a: sine(fa), b: sine(fb))
            XCTAssertLessThanOrEqual(peak(output.left), ceiling, "\(fa) + \(fb) Hz")
            XCTAssertLessThanOrEqual(peak(output.right), ceiling)
            let snapshot = MixerSnapshot(channelGains: rig.mixer.channelGains, outputPeak: rig.mixer.outputPeak,
                                         limiterReduction: rig.mixer.limiterReduction)
            XCTAssertTrue(snapshot.limiterActive, "limiter reduction \(rig.mixer.limiterReduction) dB")
            XCTAssertFalse(snapshot.isClipping)
            XCTAssertTrue(output.blocks.allSatisfy { $0.outputPeak <= self.ceiling })
            XCTAssertLessThanOrEqual(20 * log10(output.blocks.map(\.outputPeak).max() ?? 1), -0.1 + 1e-6)
        }
        // In phase: the sum peaks at 2 (6 dB above full scale): reduction ≈ 6.1 dB.
        var rig = MixerRig()
        _ = rig.run(frames: 48_000, a: sine(1_000), b: sine(1_000))
        XCTAssertEqual(rig.mixer.limiterReduction, 20 * log10(2 / ceiling), accuracy: 0.05)
    }

    /// CA7 (indicatif) : un son seul à 0 dBFS, crossfader de son côté, perd 1 dB au plus (pas
    /// d'atténuation fixe) ; un son sous le plafond traverse le limiteur intact.
    func testSingleFullScaleSourceLevel() {
        var rig = MixerRig()
        rig.mixer.setCrossfader(0)
        let output = rig.run(frames: 48_000, a: sine(1_000), b: { _ in 0 })
        let rms = (output.left[4_800...].reduce(0.0) { $0 + Double($1) * Double($1) } / Double(output.left.count - 4_800)).squareRoot()
        let loss = 20 * log10((0.5).squareRoot() / rms)
        XCTAssertLessThanOrEqual(loss, 1, "level loss \(loss) dB")
        XCTAssertLessThanOrEqual(peak(output.left), ceiling)

        var quiet = MixerRig()
        quiet.mixer.setCrossfader(0)
        quiet.settle()
        let clean = quiet.run(frames: 4_800, a: sine(1_000, amplitude: 0.5), b: { _ in 0 })
        let input = (0..<4_800).map { self.sine(1_000, amplitude: 0.5)($0) }
        XCTAssertEqual(quiet.mixer.limiterReduction, 0)
        XCTAssertEqual(clean.left, input, "below the ceiling, the output is the input")
    }

    /// CA8 — SF-65, D-26, D-13, 3.2 : crête de voie après le fader de voie et avant le crossfader
    /// (une voie fermée au crossfader garde un VU-mètre actif), gains effectifs, crête de sortie et
    /// réduction du limiteur publiés par tampon ; à travers `ScratchEngine`, les gains sont publiés.
    func testMetersArePublished_SF65() {
        var rig = MixerRig()
        rig.mixer.setCrossfader(1) // A closed at the crossfader
        rig.mixer.setLineFader(.a, 0.5)
        rig.settle()
        let output = rig.run(frames: 2_048, a: sine(1_000, amplitude: 0.8), b: sine(500, amplitude: 0.3))
        XCTAssertEqual(rig.mixer.channelPeaks.a, 0.4, accuracy: 1e-3, "VU of a closed channel: after the fader")
        XCTAssertEqual(rig.mixer.channelPeaks.b, 0.3, accuracy: 1e-3)
        XCTAssertEqual(rig.mixer.channelGains, DeckPair(a: 0, b: 1))
        XCTAssertEqual(rig.mixer.outputPeak, 0.3, accuracy: 1e-3, "only B reaches the output")
        XCTAssertEqual(rig.mixer.limiterReduction, 0)
        XCTAssertEqual(peak(output.left[1_024...]), 0.3, accuracy: 1e-3)

        // Meters are per buffer: silence resets them.
        _ = rig.run(frames: 256, a: { _ in 0 }, b: { _ in 0 })
        XCTAssertEqual(rig.mixer.channelPeaks, DeckPair(repeating: 0))
        XCTAssertEqual(rig.mixer.outputPeak, 0)

        let engine = ScratchEngine()
        engine.send(.crossfader(0))
        engine.send(.lineFader(.a, 0.7))
        var left = [Float](repeating: 0, count: 512)
        var right = [Float](repeating: 0, count: 512)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                engine.render(frameCount: 512, left: l.baseAddress!, right: r.baseAddress!)
            }
        }
        XCTAssertEqual(engine.latestSnapshot().mixer.channelGains.a, 0.7, accuracy: 1e-12)
        XCTAssertEqual(engine.latestSnapshot().mixer.channelGains.b, 0, accuracy: 1e-15)
    }

    /// CA7, CA8 — 6.8 « Pas de saturation à la somme des deux voies », de bout en bout : deux
    /// platines lisant une sinusoïde à 0 dBFS (voix de la 1.3), crossfader au centre en coupure
    /// franche : sortie ≤ −0,1 dBFS, « limiteur actif » et pas d'écrêtage dans l'instantané ;
    /// VU-mètres de voie publiés (`DeckSnapshot.peakLevel`).
    func testEngineSumOfTwoFullScaleDecksIsLimited_6_8() {
        let engine = ScratchEngine()
        engine.send(.load(.a, TestClips.sine(frequency: 1_000, seconds: 10)))
        engine.send(.load(.b, TestClips.sine(frequency: 1_000, seconds: 10)))
        engine.send(.motor(.a, on: true))
        engine.send(.motor(.b, on: true))
        var left = [Float](repeating: 0, count: 256)
        var right = [Float](repeating: 0, count: 256)
        var largest = 0.0
        for buffer in 0..<400 {
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    engine.render(frameCount: 256, left: l.baseAddress!, right: r.baseAddress!)
                }
            }
            if buffer >= 300 { largest = max(largest, peak(left), peak(right)) }
        }
        let snapshot = engine.latestSnapshot()
        XCTAssertEqual(snapshot[.a].playbackRate, 1, accuracy: 1e-6, "both decks play at speed")
        XCTAssertLessThanOrEqual(largest, ceiling)
        XCTAssertTrue(snapshot.mixer.limiterActive, "reduction \(snapshot.mixer.limiterReduction) dB")
        XCTAssertFalse(snapshot.mixer.isClipping)
        // Sampled crest of a 1 kHz sine at 48 kHz: between cos(π/48) ≈ 0.9979 and 1.
        XCTAssertEqual(snapshot[.a].peakLevel, 1, accuracy: 3e-3, "channel VU after the line fader")
        XCTAssertEqual(snapshot[.b].peakLevel, 1, accuracy: 3e-3)
    }

    /// CA9 : sorties finies, gains et enveloppe du limiteur exacts au repos (pas de dénormaux),
    /// fréquence de sortie modifiable.
    func testSilenceAndSampleRateChange() {
        var rig = MixerRig()
        rig.mixer.setOutputSampleRate(96_000)
        rig.mixer.setCrossfader(1)
        let output = rig.run(frames: 4_800, a: sine(100), b: { _ in 0 })
        XCTAssertFalse(output.left.contains { !$0.isFinite })
        rig.mixer.setCrossfader(0)
        let trace = gainTrace(&rig, deck: .a, frames: 256)
        XCTAssertLessThanOrEqual((trace.firstIndex { $0 > 0.99 } ?? 999) + 1, 96, "1 ms at 96 kHz")
        rig.mixer.setOutputSampleRate(.nan)
        XCTAssertEqual(rig.mixer.outputSampleRate, 96_000)
    }
}
