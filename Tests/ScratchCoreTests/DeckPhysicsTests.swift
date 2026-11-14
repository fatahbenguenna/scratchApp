import Foundation
import XCTest
@testable import ScratchCore

/// Banc d'essai hors ligne de `DeckPhysics` : rendu par blocs ou échantillon par échantillon, gestes
/// horodatés sur l'horloge audio (touches à 240 Hz livrées au début de chaque bloc).
///
/// Par défaut, le rejeu du doigt a un retard constant (14 ms) et une cadence de 1 : la cible du
/// doigt est exactement le geste programmé, décalé de 14 ms, ce qui rend les mesures exactes.
final class PhysicsHarness {
    struct Sample {
        var position: Double
        var rate: Double
        var discAngle: Double
        var discVelocity: Double
        var platterVelocity: Double
        var fingerAngle: Double
        var trackingError: Double
        var gripOffset: Double
        var isHeld: Bool
    }

    struct Output {
        var positions: [Double] = []
        var rates: [Double] = []
    }

    private enum Touch {
        case began(Double)
        case moved(Double)
        case ended
    }

    static let exactFinger: FingerTrajectory.Configuration = {
        var configuration = FingerTrajectory.Configuration()
        configuration.rateGain = 0
        configuration.delaySmoothing = 0
        return configuration
    }()

    static let capacity = 512

    var physics: DeckPhysics
    let sampleRate: Double
    private(set) var sampleCount = 0
    private var pending: [(time: Double, touch: Touch)] = []
    private let positions = UnsafeMutablePointer<Double>.allocate(capacity: PhysicsHarness.capacity)
    private let rates = UnsafeMutablePointer<Double>.allocate(capacity: PhysicsHarness.capacity)

    init(sampleRate: Double = 48_000, duration: Double = 30,
         finger: FingerTrajectory.Configuration = PhysicsHarness.exactFinger) {
        self.sampleRate = sampleRate
        physics = DeckPhysics(sampleRate: sampleRate, fingerConfiguration: finger)
        physics.reset(duration: duration)
        positions.initialize(repeating: 0, count: Self.capacity)
        rates.initialize(repeating: 0, count: Self.capacity)
    }

    deinit {
        positions.deallocate()
        rates.deallocate()
    }

    var time: Double { Double(sampleCount) / sampleRate }
    var dt: Double { 1 / sampleRate }

    /// Programme un geste : contact à `start`, touches à `touchRate` jusqu'à `end` (angle `path(t)`,
    /// `t` sur l'horloge audio), relâchement à `end` si demandé.
    func schedule(from start: Double, to end: Double, touchRate: Double = 240, release: Bool = true,
                  path: (Double) -> Double) {
        pending.append((start, .began(path(start))))
        var index = 1
        while true {
            let t = start + Double(index) / touchRate
            if t > end + 1e-12 { break }
            pending.append((t, .moved(path(t))))
            index += 1
        }
        let last = start + Double(index - 1) / touchRate
        if end - last > 1e-9 { pending.append((end, .moved(path(end)))) }
        if release { pending.append((end, .ended)) }
    }

    private func deliverDueTouches() {
        var delivered = 0
        for event in pending {
            guard event.time <= time + 1e-12 else { break }
            switch event.touch {
            case let .began(angle): physics.touchBegan(angle: angle, time: event.time)
            case let .moved(angle): physics.touchMoved(angle: angle, time: event.time, predicted: false)
            case .ended: physics.touchEnded(time: event.time)
            }
            delivered += 1
        }
        pending.removeFirst(delivered)
    }

    /// Un échantillon (un bloc d'une trame).
    @discardableResult
    func step() -> Sample {
        deliverDueTouches()
        physics.process(frameCount: 1, positions: positions, rates: rates)
        sampleCount += 1
        return Sample(position: positions[0], rate: rates[0], discAngle: physics.discAngle,
                      discVelocity: physics.discVelocity, platterVelocity: physics.platterVelocity,
                      fingerAngle: physics.fingerAngle, trackingError: physics.holdTrackingError,
                      gripOffset: physics.gripOffset, isHeld: physics.isHeld)
    }

    func record(samples: Int) -> [Sample] {
        (0..<samples).map { _ in step() }
    }

    func record(seconds: Double) -> [Sample] {
        record(samples: Int((seconds * sampleRate).rounded()))
    }

    /// Avance par blocs de `block` trames et renvoie les sorties.
    @discardableResult
    func run(samples: Int, block: Int = 256) -> Output {
        var output = Output()
        output.positions.reserveCapacity(samples)
        output.rates.reserveCapacity(samples)
        var remaining = samples
        while remaining > 0 {
            let count = min(block, remaining, Self.capacity)
            deliverDueTouches()
            physics.process(frameCount: count, positions: positions, rates: rates)
            for index in 0..<count {
                output.positions.append(positions[index])
                output.rates.append(rates[index])
            }
            sampleCount += count
            remaining -= count
        }
        return output
    }

    @discardableResult
    func run(seconds: Double, block: Int = 256) -> Output {
        run(samples: Int((seconds * sampleRate).rounded()), block: block)
    }

    /// Avance échantillon par échantillon jusqu'à `condition` ; renvoie le nombre d'échantillons.
    func stepUntil(maximumSeconds: Double, _ condition: (DeckPhysics) -> Bool) -> Int? {
        for count in 1...Int(maximumSeconds * sampleRate) {
            step()
            if condition(physics) { return count }
        }
        return nil
    }

    /// Moteur à START jusqu'au régime (rampe de 0,7 s, rattrapage du disque compris).
    func spinUp(seconds: Double = 1.2) {
        physics.setMotor(true)
        run(seconds: seconds)
    }
}

/// Physique d'une platine (story 1.1 ; spec v2.1 §5.1, §5.4 ; architecture §6.3).
final class DeckPhysicsTests: XCTestCase {
    private let reference = TurntableConstants.referenceAngularVelocity
    private let secondsPerRadian = TurntableConstants.secondsPerRevolution / (2 * Double.pi)
    private let replayDelay = PhysicsHarness.exactFinger.initialDelay

    private func rpm(_ omega: Double) -> Double { omega * 60 / (2 * Double.pi) }

    private func wrapped(_ angle: Double) -> Double {
        let twoPi = 2 * Double.pi
        var value = angle.truncatingRemainder(dividingBy: twoPi)
        if value > Double.pi { value -= twoPi }
        if value <= -Double.pi { value += twoPi }
        return value
    }

    /// Écart entre l'angle du disque et `2π × p / 1,8` (mod 2π), dans ]−π ; π].
    private func misalignment(_ physics: DeckPhysics) -> Double {
        wrapped(physics.discAngle - physics.positionSeconds / secondsPerRadian)
    }

    // MARK: Plateau (CA 1 à 5)

    /// CA1, CA2 — SF-04, SF-68 (6.2 « Démarrer la platine à 33 tours », 6.9 « Démarrage court ») :
    /// rampe linéaire, ωt atteint en `startDuration` ± 1 ms, jamais dépassé.
    func testStartReachesTargetInStartDuration_SF04_SF68() {
        for (rate, duration) in [(48_000.0, 0.7), (48_000, 0.1), (48_000, 5.0), (44_100, 0.7)] {
            let label = "\(rate) Hz, \(duration) s"
            let harness = PhysicsHarness(sampleRate: rate)
            harness.physics.setMotorTimings(MotorTimings(startDuration: duration))
            let target = harness.physics.nominalPlatterVelocity
            XCTAssertEqual(target, 2 * Double.pi * (100.0 / 3) / 60, accuracy: 1e-12)
            harness.physics.setMotor(true)

            let half = Int((duration / 2 * rate).rounded())
            harness.run(samples: half)
            XCTAssertEqual(harness.physics.platterVelocity, target / 2, accuracy: target * 1e-9, "linear, \(label)")

            harness.run(samples: Int(((duration - 0.002) * rate).rounded()) - half)
            XCTAssertLessThan(harness.physics.platterVelocity, target, label)
            let reached = harness.stepUntil(maximumSeconds: 0.004) { $0.platterVelocity == target }
            XCTAssertNotNil(reached, label)
            XCTAssertEqual(harness.time, duration, accuracy: 0.001, "ωt reached in startDuration ± 1 ms, \(label)")

            let after = harness.record(seconds: 0.05)
            XCTAssertTrue(after.allSatisfy { $0.platterVelocity == target }, "ωp never exceeds ωt, \(label)")
        }
    }

    /// CA1 — SF-05, SF-68 (6.2 « Arrêter la platine », « Régler les durées ») : arrêt en
    /// `brakeDuration` ± 1 ms ; le son ralentit avec le disque ; la position est conservée.
    func testStopKeepsPositionAndTakesBrakeDuration_SF05() {
        for brake in [1.0, 3.0] {
            let harness = PhysicsHarness()
            harness.physics.setMotorTimings(MotorTimings(brakeDuration: brake))
            harness.spinUp()
            XCTAssertEqual(harness.physics.platterVelocity, reference)
            let positionAtStop = harness.physics.positionSeconds
            harness.physics.setMotor(false)
            let stopTime = harness.time

            let braking = harness.run(samples: Int(((brake - 0.002) * 48_000).rounded()))
            XCTAssertGreaterThan(harness.physics.platterVelocity, 0)
            XCTAssertNotNil(harness.stepUntil(maximumSeconds: 0.004) { $0.platterVelocity == 0 })
            XCTAssertEqual(harness.time - stopTime, brake, accuracy: 0.001, "stop in brakeDuration ± 1 ms")
            XCTAssertTrue(zip(braking.rates.dropFirst(), braking.rates).allSatisfy { $0 <= $1 + 1e-12 },
                          "the sound slows down with the disc")

            harness.run(seconds: 1.0)
            XCTAssertEqual(harness.physics.discVelocity, 0)
            let rest = harness.physics.positionSeconds
            // Area of the braking ramp (brake / 2 s of sound at 33⅓) plus the slipmat lag τ = T / 3.
            XCTAssertEqual(rest - positionAtStop, brake / 2 + 0.02, accuracy: 1e-3)
            harness.run(seconds: 0.5)
            XCTAssertEqual(harness.physics.positionSeconds, rest, "the position is kept once stopped")
            XCTAssertFalse(harness.physics.motorOn)
        }
    }

    /// CA2 — SF-68 : durées bornées à 0,1…5 s et rattrapage à 0…300 ms ; non fini ignoré.
    func testMotorDurationsAreClamped_SF68() {
        var physics = DeckPhysics(sampleRate: 48_000)
        physics.setMotorTimings(MotorTimings(startDuration: 0.05, brakeDuration: 9, slipmatCatchUp: 0.5))
        XCTAssertEqual(physics.motorTimings, MotorTimings(startDuration: 0.1, brakeDuration: 5, slipmatCatchUp: 0.3))
        physics.setMotorTimings(MotorTimings(startDuration: 2, brakeDuration: 3, slipmatCatchUp: -1))
        XCTAssertEqual(physics.motorTimings, MotorTimings(startDuration: 2, brakeDuration: 3, slipmatCatchUp: 0))
        physics.setMotorTimings(MotorTimings(startDuration: .nan, brakeDuration: .infinity, slipmatCatchUp: -.infinity))
        XCTAssertEqual(physics.motorTimings, MotorTimings(startDuration: 2, brakeDuration: 3, slipmatCatchUp: 0),
                       "non-finite values are ignored")
    }

    /// CA3 — SF-11, RM-50 (6.6 « Modifier le pitch ») : vitesses cibles à 0,01 RPM près ; vitesse
    /// de lecture RPM / 33⅓ (1,35 à 45) ; pitch borné à ±8 %.
    func testPitchTable_SF11_RM50() {
        let rows: [(TurntableSpeed, Double, Double)] = [
            (.rpm33, -0.08, 30.67), (.rpm33, 0, 33.33), (.rpm33, 0.08, 36.00),
            (.rpm45, -0.08, 41.40), (.rpm45, 0, 45.00), (.rpm45, 0.08, 48.60),
        ]
        for (speed, pitch, expected) in rows {
            let harness = PhysicsHarness()
            harness.physics.setSpeed(speed)
            harness.physics.setPitch(pitch)
            harness.spinUp()
            let measured = rpm(harness.physics.platterVelocity)
            XCTAssertEqual(measured, expected, accuracy: 0.01, "\(speed.rawValue) RPM, pitch \(pitch)")
            XCTAssertEqual(harness.physics.playbackRate, measured / TurntableConstants.referenceRPM, accuracy: 1e-9)
        }
        var physics = DeckPhysics(sampleRate: 48_000)
        physics.setPitch(0.2)
        XCTAssertEqual(physics.pitch, 0.08)
        physics.setPitch(-0.5)
        XCTAssertEqual(physics.pitch, -0.08)
        physics.setPitch(.nan)
        XCTAssertEqual(physics.pitch, -0.08)
    }

    /// CA3 — SF-11 (6.2 « Sélectionner 45 tours », « Modifier la vitesse pendant la lecture » ;
    /// 6.6 « Remettre le pitch à zéro ») : rampe vers la nouvelle cible, sans marche de ωp.
    func testSpeedChangeWhileSpinningIsContinuous_SF11() {
        let harness = PhysicsHarness()
        harness.spinUp()
        harness.physics.setSpeed(.rpm45)
        let target45 = harness.physics.nominalPlatterVelocity
        XCTAssertEqual(rpm(target45), 45, accuracy: 1e-9)
        let accelerationStep = target45 / 0.7 * harness.dt

        var previous = harness.step()
        var largestStep = previous.platterVelocity - reference
        var largestMove = 0.0
        var reached: Double?
        for _ in 0..<Int(0.4 * 48_000) {
            let sample = harness.step()
            largestStep = max(largestStep, abs(sample.platterVelocity - previous.platterVelocity))
            largestMove = max(largestMove, abs(sample.position - previous.position))
            if reached == nil, sample.platterVelocity == target45 { reached = harness.time }
            previous = sample
        }
        XCTAssertLessThanOrEqual(largestStep, accelerationStep * (1 + 1e-9), "no step of ωp")
        XCTAssertLessThanOrEqual(largestMove, 1.35 * harness.dt * (1 + 1e-6), "the position stays continuous")
        let expected = 1.2 + (target45 - reference) / target45 * 0.7
        XCTAssertEqual(reached ?? 0, expected, accuracy: 0.001)
        XCTAssertEqual(harness.physics.playbackRate, 1.35, accuracy: 1e-6, "45 RPM is read 1.35 × faster")

        // Pitch back to zero: progressive return (brake slope), no step.
        harness.physics.setSpeed(.rpm33)
        harness.physics.setPitch(0.053)
        harness.run(seconds: 1.5)
        let pitched = harness.physics.platterVelocity
        XCTAssertEqual(pitched, reference * 1.053, accuracy: 1e-9)
        harness.physics.setPitch(0)
        let brakeStep = reference / 1.0 * harness.dt
        let trace = harness.record(seconds: 0.1)
        let steps = zip(trace.dropFirst(), trace).map { $1.platterVelocity - $0.platterVelocity }
        XCTAssertLessThanOrEqual(steps.max() ?? 0, brakeStep * (1 + 1e-9))
        XCTAssertEqual(trace.last?.platterVelocity ?? 0, reference)
    }

    /// CA4 (6.2 « Appuyer sur START pendant le freinage ») : réaccélération depuis la vitesse
    /// courante, sans discontinuité de ωp ni de position.
    func testStartDuringBrakingResumesFromCurrentSpeed() {
        let harness = PhysicsHarness()
        harness.spinUp()
        harness.physics.setMotor(false)
        harness.run(seconds: 0.4)
        let before = harness.physics.platterVelocity
        XCTAssertEqual(before, reference * 0.6, accuracy: reference * 1e-3)
        let discBefore = harness.physics.discVelocity
        let positionBefore = harness.physics.positionSeconds
        harness.physics.setMotor(true)
        let first = harness.step()
        XCTAssertEqual(first.platterVelocity, before + reference / 0.7 * harness.dt, accuracy: 1e-12)
        XCTAssertEqual(first.discVelocity, discBefore, accuracy: reference * 1e-3)
        XCTAssertEqual(first.position - positionBefore, discBefore * harness.dt * secondsPerRadian,
                       accuracy: 1e-3 * reference * harness.dt * secondsPerRadian)
        XCTAssertNotNil(harness.stepUntil(maximumSeconds: 0.5) { $0.platterVelocity == self.reference })
        XCTAssertEqual(harness.time, 1.6 + (reference - before) / reference * 0.7, accuracy: 0.001)
    }

    /// CA4 — PO-01, RM-01 (6.2 « Démarrer sans fichier ») : START sur une platine vide fait tourner
    /// le plateau.
    func testPlatterSpinsWithoutClip_PO01() {
        let harness = PhysicsHarness(duration: 0)
        harness.spinUp(seconds: 1.0)
        XCTAssertEqual(harness.physics.platterVelocity, reference)
        XCTAssertTrue(harness.physics.motorOn)
        // Ramp area (0.35 s) then 0.3 s at full speed.
        XCTAssertEqual(harness.physics.platterAngle, reference * 0.65, accuracy: reference * 1e-4)
        XCTAssertGreaterThan(harness.physics.discAngle, 0, "the (empty) disc turns too")
        XCTAssertEqual(harness.physics.positionSeconds, 0)
    }

    /// CA5 — RM-53, SF-06 (6.9 « Le plateau tourne sous le disque retenu ») : moteur actif, ωp et
    /// START ne dépendent pas de la tenue ; le disque retenu s'immobilise.
    func testPlatterIgnoresHold_RM53() {
        let harness = PhysicsHarness()
        harness.spinUp()
        let start = harness.time
        let platterStart = harness.physics.platterAngle
        harness.schedule(from: start, to: start + 2.5, release: false) { _ in 1.0 }
        var largestDeviation = 0.0
        for _ in 0..<375 { // 2 s
            harness.run(samples: 256)
            largestDeviation = max(largestDeviation, abs(harness.physics.platterVelocity - reference))
            XCTAssertTrue(harness.physics.motorOn)
        }
        XCTAssertEqual(largestDeviation, 0, "ωp is independent of the hold")
        XCTAssertEqual(harness.physics.platterAngle - platterStart, reference * 2, accuracy: 1e-6)
        XCTAssertTrue(harness.physics.isHeld)
        XCTAssertEqual(harness.physics.playbackRate, 0, accuracy: 1e-9, "the held disc stopped")
        XCTAssertEqual(harness.physics.discMode, .held)
    }

    /// CA5 — RM-07 (6.2 « Appuyer sur STOP pendant que je retiens le disque ») : le plateau
    /// s'arrête sous le disque tenu ; au relâchement, aucune reprise motorisée.
    func testStopWhileHeldNoRestart_RM07() {
        let harness = PhysicsHarness()
        harness.spinUp()
        let start = harness.time
        harness.schedule(from: start, to: start + 1.5) { _ in 0 }
        harness.run(seconds: 0.3)
        harness.physics.setMotor(false)
        harness.run(seconds: 1.1)
        XCTAssertEqual(harness.physics.platterVelocity, 0, "the platter stopped under the disc")
        XCTAssertTrue(harness.physics.isHeld, "the disc stays under control")
        harness.run(seconds: 0.2)
        XCTAssertFalse(harness.physics.isHeld)
        XCTAssertEqual(harness.physics.discMode, .coasting)
        let rest = harness.physics.positionSeconds
        let output = harness.run(seconds: 0.5)
        XCTAssertTrue(output.rates.allSatisfy { $0 == 0 }, "no motorized playback")
        XCTAssertEqual(harness.physics.positionSeconds, rest)
    }

    // MARK: Relâchement (CA 6, 7)

    /// Tient le disque immobile `holdSeconds` puis le relâche ; s'arrête juste avant le premier
    /// échantillon libre. Renvoie la position au dernier échantillon tenu.
    private func holdStillThenRelease(_ harness: PhysicsHarness, holdSeconds: Double) -> Double {
        let start = harness.time
        harness.schedule(from: start, to: start + holdSeconds) { _ in 0 }
        harness.run(seconds: holdSeconds)
        XCTAssertTrue(harness.physics.isHeld, "released only once the replay reaches the end")
        XCTAssertNotNil(harness.stepUntil(maximumSeconds: 0.1) { !$0.isHeld })
        XCTAssertEqual(harness.time, start + holdSeconds + replayDelay, accuracy: 2 * harness.dt)
        return harness.physics.positionSeconds
    }

    /// CA6 — SF-10, SF-68, D-03 (6.3 « Relâcher le disque moteur actif » ; 6.9 « Rattrapage
    /// réglable », « Rattrapage plus lent ») : |ωd − ωp| ≤ 5 % de l'écart initial au terme de T,
    /// mesuré depuis l'instant où le relâchement prend effet ; T = 0 → ωp dès l'échantillon suivant.
    func testCatchUpReaches95PercentInSlipmatTime_SF10_SF68() {
        for catchUp in [0.060, 0.300, 0.0] {
            let harness = PhysicsHarness()
            harness.physics.setMotorTimings(MotorTimings(slipmatCatchUp: catchUp))
            harness.spinUp()
            let lastHeldPosition = holdStillThenRelease(harness, holdSeconds: 1.0)
            let platter = harness.physics.platterVelocity
            let initialGap = platter - harness.physics.discVelocity
            XCTAssertEqual(initialGap, platter, accuracy: platter * 1e-9, "released from rest: initial gap = ωp")

            if catchUp == 0 {
                let first = harness.step()
                XCTAssertEqual(first.discVelocity, platter, "T = 0: platter speed from the next sample")
                // Trapezoidal step from rest to ωp: half a sample of motion, no position jump.
                XCTAssertEqual(first.position - lastHeldPosition, 0.5 * platter * harness.dt * secondsPerRadian,
                               accuracy: 1e-12, "no position jump")
                continue
            }
            let samples = Int((catchUp * 48_000).rounded())
            let trace = harness.record(samples: samples)
            let gapAtT = platter - trace[samples - 1].discVelocity
            XCTAssertLessThanOrEqual(gapAtT, 0.05 * initialGap, "T = \(catchUp): 95 % at T")
            XCTAssertGreaterThan(gapAtT, 0.045 * initialGap, "T = \(catchUp): not faster than T / 3")
            XCTAssertLessThanOrEqual(abs(trace[0].position - lastHeldPosition), platter * harness.dt * secondsPerRadian,
                                     "the position is continuous at the release")
            XCTAssertTrue(zip(trace.dropFirst(), trace).allSatisfy { $0.discVelocity >= $1.discVelocity },
                          "monotonic catch-up")
        }
    }

    /// CA6 — SF-10 : disque relâché en marche arrière (ωd ≈ −ωref) : l'écart, ≈ 2 ωp, est réduit à
    /// 5 % en T. Rejeu par défaut (cadence régulée), livraison des touches par lots.
    func testCatchUpFromReverseMotion_SF10() {
        let harness = PhysicsHarness(finger: FingerTrajectory.Configuration())
        harness.spinUp()
        let start = harness.time
        harness.schedule(from: start, to: start + 0.5, touchRate: 120) { -self.reference * ($0 - start) }
        harness.run(seconds: 0.5)
        XCTAssertNotNil(harness.stepUntil(maximumSeconds: 0.1) { !$0.isHeld })
        let platter = harness.physics.platterVelocity
        let initialGap = platter - harness.physics.discVelocity
        XCTAssertEqual(initialGap, 2 * platter, accuracy: 0.1 * platter)
        let trace = harness.record(samples: 2_880)
        XCTAssertLessThanOrEqual(platter - trace[2_879].discVelocity, 0.05 * initialGap)
    }

    /// CA7 — SF-10, RM-07, D-03 (6.3 « Relâcher le disque moteur arrêté ») : décélération linéaire
    /// et arrêt 150 ms au plus après le relâchement, de 1 à 16 × ωref, sans reprise motorisée.
    func testFreeSpinStopsWithin150ms_SF10() {
        for (rate, multiple) in [(48_000.0, 1.0), (48_000, 4), (48_000, 16), (48_000, -16), (44_100, 8), (48_000, -1)] {
            let label = "\(multiple) × ωref at \(rate) Hz"
            let harness = PhysicsHarness(sampleRate: rate)
            harness.physics.seek(to: 15)
            let velocity = multiple * reference
            let start = harness.time
            harness.schedule(from: start, to: start + 0.3) { velocity * ($0 - start) }
            harness.run(seconds: 0.3)
            XCTAssertNotNil(harness.stepUntil(maximumSeconds: 0.1) { !$0.isHeld }, label)
            let initial = harness.physics.discVelocity
            XCTAssertEqual(initial, velocity, accuracy: abs(velocity) * 0.01, "thrown at \(label)")
            XCTAssertEqual(harness.physics.discMode, .coasting)
            let startPosition = harness.physics.positionSeconds

            let trace = harness.record(seconds: 0.3)
            guard let stop = trace.firstIndex(where: { $0.discVelocity == 0 }) else {
                XCTFail("never stops, \(label)")
                continue
            }
            XCTAssertLessThanOrEqual(Double(stop + 1) / rate, 0.150 + 1e-9, "stopped within 150 ms, \(label)")
            let decrement = abs(initial) / (0.150 * rate)
            var previous = abs(initial)
            for sample in trace[..<stop] {
                XCTAssertEqual(previous - abs(sample.discVelocity), decrement, accuracy: decrement * 1e-6,
                               "linear deceleration, \(label)")
                XCTAssertEqual(sample.discVelocity.sign, initial.sign)
                previous = abs(sample.discVelocity)
            }
            XCTAssertTrue(trace[stop...].allSatisfy { $0.discVelocity == 0 && $0.rate == 0 },
                          "no motorized playback, \(label)")
            XCTAssertEqual(trace[stop].position - startPosition, initial * 0.075 * secondsPerRadian,
                           accuracy: abs(initial) * 1e-4, "triangle area, \(label)")
            XCTAssertFalse(harness.physics.motorOn)
        }
    }

    // MARK: Disque tenu (CA 8)

    /// CA8 — RM-12, SF-06 (6.3 « Maintenir un disque immobile » ; 6.7 « Conserver la possibilité
    /// d'arrêter le disque ») : après un mouvement à 2 × ωref, |ωd| ≤ 10⁻³ × ωref au plus 10 τ après
    /// l'immobilisation de la cible, y compris à 100 % ; puis la position n'évolue plus.
    func testFixedFingerStopsDisc_RM12() {
        for resistance in [0.0, 0.5, 1.0] {
            let harness = PhysicsHarness()
            harness.physics.setResistance(resistance)
            harness.spinUp()
            let tau = harness.physics.holdTimeConstant
            let start = harness.time
            let moveEnd = start + 0.6
            let finalAngle = 2 * reference * (moveEnd - start)
            harness.schedule(from: start, to: start + 5, release: false) { 2 * self.reference * (min($0, moveEnd) - start) }
            harness.run(seconds: 0.6)
            // Sampled speed of the zero-order-hold follower: (h/τ)²/12 below the finger speed (≤ 1e-5).
            XCTAssertEqual(harness.physics.discVelocity, 2 * reference, accuracy: 2e-5 * reference, "follows the finger")
            XCTAssertNotNil(harness.stepUntil(maximumSeconds: 0.1) { $0.fingerAngle == finalAngle }, "target frozen")

            let tenTau = harness.record(samples: Int(10 * tau * 48_000))
            XCTAssertLessThanOrEqual(abs(tenTau.last?.discVelocity ?? 1), 1e-3 * reference,
                                     "|ωd| ≤ 1e-3 ωref within 10 τ, resistance \(resistance)")
            XCTAssertLessThanOrEqual(abs(tenTau.last?.rate ?? 1), 1e-3)
            // Residual drift after 10 τ ≈ 12 v τ e^-10 (≈ 1.8 samples of sound at 100 %); from 15 τ
            // the position moves by less than one sample of sound per second.
            harness.run(samples: Int(5 * tau * 48_000))
            let settled = harness.physics.positionSeconds
            harness.run(seconds: 1.0)
            XCTAssertLessThan(abs(harness.physics.positionSeconds - settled), 1 / 48_000.0)
            harness.run(seconds: 1.5)
            XCTAssertEqual(harness.physics.discVelocity, 0, "exact rest")
            XCTAssertEqual(harness.physics.playbackRate, 0)
            XCTAssertTrue(harness.physics.isHeld)
        }
    }

    /// CA8 — SF-06, ADR-08 (6.3 « Saisir le disque en rotation ») : le filtre part de l'angle et de
    /// la vitesse courants (`gripOffset = θd − θf`), sans saut ; aller-retour v₀ τ / e attendu.
    func testGrabbingSpinningDiscHasNoPositionJump_SF06() {
        let harness = PhysicsHarness()
        harness.spinUp()
        let angle = harness.physics.discAngle
        let velocity = harness.physics.discVelocity
        let position = harness.physics.positionSeconds
        XCTAssertEqual(velocity, reference, accuracy: 1e-9)
        let tau = harness.physics.holdTimeConstant
        let start = harness.time
        harness.schedule(from: start, to: start + 1, release: false) { _ in 7.3 }
        let first = harness.step()
        XCTAssertEqual(first.gripOffset, angle - 7.3, accuracy: 1e-12)
        XCTAssertTrue(first.isHeld)
        // First step from (θd, ωd) toward a fixed target: Δθ = ωd h e^(−h/τ), one sample of motion.
        XCTAssertEqual(first.position - position, velocity * harness.dt * exp(-harness.dt / tau) * secondsPerRadian,
                       accuracy: 1e-12, "no position jump")
        XCTAssertEqual(first.discVelocity, velocity, accuracy: 0.01 * velocity, "no velocity jump")

        let trace = harness.record(seconds: 0.6)
        let peak = (trace.map(\.discAngle).max() ?? angle) - angle
        XCTAssertEqual(peak, velocity * tau / M_E, accuracy: velocity * tau / M_E * 0.01)
        XCTAssertEqual(trace.last?.discAngle ?? 0, angle, accuracy: 1e-6, "back under the finger")
        XCTAssertEqual(trace.last?.position ?? 0, position, accuracy: 1e-6)
    }

    // MARK: Résistance (CA 9)

    private func peakAcceleration(resistance: Double, speed: Double) -> (peak: Double, final: Double) {
        let harness = PhysicsHarness()
        harness.physics.setResistance(resistance)
        let start = harness.time
        let flick = start + 0.05
        harness.schedule(from: start, to: start + 0.5, release: false) { max(0, $0 - flick) * speed }
        let trace = harness.record(seconds: 0.4)
        let peak = zip(trace.dropFirst(), trace).map { abs($0.discVelocity - $1.discVelocity) * 48_000 }.max() ?? 0
        return (peak, trace.last?.discVelocity ?? 0)
    }

    /// CA9 — SF-22, RM-11 (6.7 « Réduire la résistance », « Augmenter la résistance ») : à geste
    /// identique, la crête d'accélération de ωd est plus faible à 90 % qu'à 10 %.
    func testHigherResistanceDampsAcceleration_SF22() {
        let speed = 4 * reference
        let light = peakAcceleration(resistance: 0.1, speed: speed)
        let heavy = peakAcceleration(resistance: 0.9, speed: speed)
        XCTAssertLessThan(heavy.peak, light.peak / 3, "accelerations are damped at 90 %")
        // Critically damped response to a speed step v: peak acceleration v / (e τ).
        let heavyTau = 0.002 + 0.033 * 0.9
        XCTAssertEqual(heavy.peak, speed / (M_E * heavyTau), accuracy: speed / (M_E * heavyTau) * 0.05)
        XCTAssertEqual(light.final, speed, accuracy: speed * 1e-5, "the sound follows the simulated disc")
        XCTAssertEqual(heavy.final, speed, accuracy: speed * 1e-3)
    }

    /// CA9 — RM-12 (6.7 « Scratcher en sens inverse avec une résistance élevée ») : geste arrière
    /// soutenu à 90 % sur un disque qui tourne : ωd < 0, une seule inversion de sens.
    func testReverseAtHighResistance_RM12() {
        let harness = PhysicsHarness()
        harness.physics.setResistance(0.9)
        harness.spinUp()
        let start = harness.time
        harness.schedule(from: start, to: start + 1.2, release: false) { -self.reference * ($0 - start) }
        let trace = harness.record(seconds: 1.0)
        var signChanges = 0
        var sign = 1.0
        for sample in trace where abs(sample.discVelocity) > 1e-9 && sample.discVelocity.sign != (sign > 0 ? .plus : .minus) {
            signChanges += 1
            sign = -sign
        }
        XCTAssertEqual(signChanges, 1, "a single reversal, no parasitic inversion")
        XCTAssertEqual(trace.last?.discVelocity ?? 0, -reference, accuracy: reference * 1e-3)
        XCTAssertLessThan(trace.last?.rate ?? 0, 0, "the sound is read backwards")
        XCTAssertLessThan(trace.last!.position, trace[trace.count - 100].position)
    }

    /// CA9 — SF-23, RM-13 (6.7 « Modifier la résistance pendant le scratch ») : changer la
    /// résistance pendant un scratch ne fait sauter ni θd ni ωd ni la position ; le doigt garde le
    /// contrôle du disque.
    func testResistanceChangeWhileHeldIsContinuous_SF23() {
        let harness = PhysicsHarness()
        harness.physics.setResistance(0.1)
        let start = harness.time
        harness.schedule(from: start, to: start + 3, release: false) { .pi / 4 * sin(2 * .pi * ($0 - start)) }
        harness.run(seconds: 0.3)
        var largestError = 0.0
        for value in [0.9, 0.1, 1.0, 0.0, 0.5] {
            harness.run(seconds: 0.3)
            let before = harness.physics
            harness.physics.setResistance(value)
            XCTAssertEqual(harness.physics.discAngle, before.discAngle)
            XCTAssertEqual(harness.physics.discVelocity, before.discVelocity)
            XCTAssertEqual(harness.physics.positionSeconds, before.positionSeconds)
            let tau = harness.physics.holdTimeConstant
            let next = harness.step()
            // The step is bounded by the dynamics of the new τ: no jump of angle, speed or position.
            let error = abs(before.holdTrackingError)
            let acceleration = error / (tau * tau) + 2 * abs(before.discVelocity) / tau
            XCTAssertLessThanOrEqual(abs(next.discVelocity - before.discVelocity), acceleration * harness.dt * 1.05)
            let move = (abs(before.discVelocity) + acceleration * harness.dt) * harness.dt * 1.05
            XCTAssertLessThanOrEqual(abs(next.discAngle - before.discAngle), move)
            XCTAssertLessThanOrEqual(abs(next.position - before.positionSeconds), move * secondsPerRadian)
            largestError = max(largestError, error)
        }
        // Finger speed ≤ π²/2 rad/s: the lag stays below 2 τmax v (control kept).
        XCTAssertLessThan(largestError, 2 * 0.035 * .pi * .pi / 2 * 1.2)
    }

    /// CA9 — RM-11, RM-54 (6.7 « Ne pas modifier la vitesse nominale », « La résistance ne ralentit
    /// pas le rattrapage ») : démarrage, régime, rattrapage et freinage identiques à 0 % et à 100 %.
    func testResistanceDoesNotAffectMotorOrCatchUp_RM11_RM54() {
        func profile(resistance: Double) -> [Double] {
            let harness = PhysicsHarness()
            harness.physics.setResistance(resistance)
            harness.physics.setMotor(true)
            var values = [Double]()
            for _ in 0..<200 {
                harness.run(samples: 256)
                values.append(harness.physics.platterVelocity)
            }
            XCTAssertEqual(harness.physics.platterVelocity, reference, "nominal 33⅓ RPM at pitch 0")
            _ = holdStillThenRelease(harness, holdSeconds: 1.5)
            values += harness.record(seconds: 0.3).map(\.discVelocity)
            harness.physics.setMotor(false)
            for _ in 0..<200 {
                harness.run(samples: 256)
                values.append(harness.physics.platterVelocity)
            }
            return values
        }
        let light = profile(resistance: 0)
        let heavy = profile(resistance: 1)
        XCTAssertEqual(light.count, heavy.count)
        let largest = zip(light, heavy).map { abs($0 - $1) }.max() ?? 1
        XCTAssertLessThanOrEqual(largest, 1e-9)
    }

    // MARK: Tête, butées et recalage (CA 10)

    /// CA10 — RM-50, RM-04 : un tour de disque = 1,8 s de son, moteur ou doigt ; vitesse de lecture
    /// `ωd / ωref` bornée à ±16 ; `platterAngle` intègre ωp.
    func testHeadIntegratesOneRevolutionPerOnePointEightSeconds_RM50() {
        let harness = PhysicsHarness()
        harness.physics.setMotorTimings(MotorTimings(slipmatCatchUp: 0))
        harness.spinUp()
        var position = harness.physics.positionSeconds
        let angle = harness.physics.discAngle
        let platter = harness.physics.platterAngle
        harness.run(samples: 86_400) // 1.8 s
        XCTAssertEqual(harness.physics.positionSeconds - position, 1.8, accuracy: 1e-9)
        XCTAssertEqual(harness.physics.discAngle - angle, 2 * .pi, accuracy: 1e-9)
        XCTAssertEqual(harness.physics.platterAngle - platter, 2 * .pi, accuracy: 1e-9)
        XCTAssertEqual(harness.physics.playbackRate, 1, accuracy: 1e-12)

        harness.physics.setSpeed(.rpm45)
        harness.run(seconds: 1.0)
        position = harness.physics.positionSeconds
        harness.run(samples: 86_400)
        XCTAssertEqual(harness.physics.positionSeconds - position, 1.8 * 1.35, accuracy: 1e-9)
        XCTAssertEqual(harness.physics.playbackRate, 1.35, accuracy: 1e-12)

        // One turn of the finger, motor off.
        let manual = PhysicsHarness()
        manual.physics.seek(to: 10)
        let manualAngle = manual.physics.discAngle
        let start = manual.time
        manual.schedule(from: start, to: start + 2, release: false) { 2 * .pi * min(1, $0 - start) }
        manual.run(seconds: 2)
        XCTAssertEqual(manual.physics.positionSeconds, 11.8, accuracy: 1e-9)
        XCTAssertEqual(manual.physics.discAngle - manualAngle, 2 * .pi, accuracy: 1e-9)

        // A finger at 30 × ωref: playback rate (and disc speed) bounded at 16, disc and head together.
        let fast = PhysicsHarness()
        fast.physics.seek(to: 10)
        let fastStart = fast.time
        let angle0 = fast.physics.discAngle
        fast.schedule(from: fastStart, to: fastStart + 0.2, release: false) { 30 * self.reference * ($0 - fastStart) }
        let output = fast.run(seconds: 0.2)
        XCTAssertEqual(output.rates.max() ?? 0, 16, accuracy: 1e-12)
        XCTAssertEqual(fast.physics.positionSeconds - 10, (fast.physics.discAngle - angle0) * secondsPerRadian, accuracy: 1e-9)
    }

    /// CA10 — RM-55, SF-14, SF-72 (scénario « Sillon fermé et retour immédiat » ; 6.12 « Atteindre
    /// la fin du son », « Revenir dans le son depuis le sillon fermé ») : en butée, le disque
    /// continue de tourner ; un mouvement arrière revient immédiatement dans le son.
    func testEndStopWithImmediateReturn_RM55() {
        let harness = PhysicsHarness(duration: 4)
        harness.spinUp()
        harness.physics.seek(to: 3.9)
        let angle = harness.physics.discAngle
        harness.run(seconds: 2)
        XCTAssertEqual(harness.physics.positionSeconds, 4.0)
        XCTAssertTrue(harness.physics.isAtEnd)
        XCTAssertEqual(harness.physics.discAngle - angle, 2 * reference, accuracy: 1e-6, "the disc kept turning")
        XCTAssertEqual(harness.physics.playbackRate, 1, accuracy: 1e-9)

        // Bring the disc back by an eighth of a turn.
        let start = harness.time
        harness.schedule(from: start, to: start + 1, release: false) { -.pi / 4 * min(1, ($0 - start) / 0.1) }
        let trace = harness.record(seconds: 0.5)
        guard let firstBackward = trace.firstIndex(where: { $0.discVelocity < 0 }),
              let exit = trace.firstIndex(where: { $0.position < 4 }) else {
            return XCTFail("the disc never came back")
        }
        XCTAssertTrue(trace[..<exit].allSatisfy { $0.position == 4 })
        XCTAssertLessThanOrEqual(exit - firstBackward, 1, "back in the sound from the first backward sample")
        XCTAssertLessThanOrEqual(4 - trace[exit].position, 16 * reference * harness.dt * secondsPerRadian,
                                 "no unwinding of the accumulated turns")
    }

    /// CA10 — RM-55, SF-14 (6.12 « Reculer dans l'amorce », « Dépasser la borne de l'amorce ») :
    /// un demi-tour arrière depuis 0 s mène à −0,9 s ; la tête se bloque à −2 s ; un mouvement avant
    /// revient immédiatement dans l'amorce.
    func testLeadInStopWithImmediateReturn_RM55() {
        let harness = PhysicsHarness(duration: 4)
        let start = harness.time
        // Half a turn back in 0.2 s, hold, one more turn back, hold, then an eighth of a turn forward.
        harness.schedule(from: start, to: start + 2.5, release: false) { t in
            let u = t - start
            if u < 0.2 { return -.pi * u / 0.2 }
            if u < 0.7 { return -.pi }
            if u < 1.2 { return -.pi - 2 * .pi * (u - 0.7) / 0.5 }
            if u < 1.7 { return -3 * .pi }
            return -3 * .pi + .pi / 4 * min(1, (u - 1.7) / 0.1)
        }
        harness.run(seconds: 0.7)
        XCTAssertEqual(harness.physics.positionSeconds, -0.9, accuracy: 1e-6)
        XCTAssertTrue(harness.physics.isInLeadIn)
        harness.run(seconds: 1.0)
        XCTAssertEqual(harness.physics.positionSeconds, -2, "blocked at the lead-in bound")
        let trace = harness.record(seconds: 0.4)
        guard let firstForward = trace.firstIndex(where: { $0.discVelocity > 0 }),
              let exit = trace.firstIndex(where: { $0.position > -2 }) else {
            return XCTFail("the disc never came forward")
        }
        XCTAssertLessThanOrEqual(exit - firstForward, 1)
        XCTAssertEqual(trace.last?.position ?? 0, -2 + 0.225, accuracy: 1e-3, "an eighth of a turn forward")
    }

    /// CA10 — IC-09, D-10, RM-13 (spec 5.4) : à la sortie d'une butée, `discAngle ≡ 2π p / 1,8` ;
    /// disque tenu, `gripOffset` reçoit la même correction : ni l'écart de suivi `θd − (θf +
    /// gripOffset)`, ni ωd, ni p ne sautent. Disque libre : recalage à la sortie de l'amorce.
    func testDiscRealignsWhenLeavingEnd_IC09() {
        let harness = PhysicsHarness(duration: 4)
        harness.spinUp()
        harness.physics.seek(to: 3.5)
        harness.run(seconds: 1.3)
        XCTAssertTrue(harness.physics.isPinnedAtBound)
        XCTAssertGreaterThan(abs(misalignment(harness.physics)), 0.5, "misaligned after turning at the end")

        let start = harness.time
        harness.schedule(from: start, to: start + 1, release: false) { -.pi / 2 * min(1, ($0 - start) / 0.2) }
        let trace = harness.record(seconds: 0.5)
        guard let exit = trace.firstIndex(where: { $0.position < 4 }), exit > 0 else {
            return XCTFail("no exit")
        }
        let (before, after) = (trace[exit - 1], trace[exit])
        let correction = after.gripOffset - before.gripOffset
        XCTAssertGreaterThan(abs(correction), 0.5)
        XCTAssertEqual(wrapped(after.discAngle - after.position / secondsPerRadian), 0, accuracy: 1e-9)
        XCTAssertLessThan(abs(after.trackingError - before.trackingError), 1e-3, "no jump under the finger")
        XCTAssertLessThan(abs(after.discVelocity - before.discVelocity), 0.05 * reference)
        XCTAssertLessThan(4 - after.position, 16 * reference * harness.dt * secondsPerRadian, "no sound jump")
        XCTAssertEqual(misalignment(harness.physics), 0, accuracy: 1e-9, "stays aligned off the bounds")

        // Free disc: pushed into the lead-in by hand, then released motor on: the platter brings it
        // forward out of the lead-in, where it is realigned.
        let free = PhysicsHarness(duration: 4)
        free.spinUp()
        free.physics.seek(to: -1.8)
        let freeStart = free.time
        free.schedule(from: freeStart, to: freeStart + 0.5) { -2 * .pi * ($0 - freeStart) / 0.2 }
        free.run(seconds: 0.5)
        XCTAssertEqual(free.physics.positionSeconds, -2)
        XCTAssertGreaterThan(abs(misalignment(free.physics)), 0.5)
        XCTAssertNotNil(free.stepUntil(maximumSeconds: 0.5) { $0.positionSeconds > -2 })
        XCTAssertFalse(free.physics.isHeld)
        XCTAssertEqual(misalignment(free.physics), 0, accuracy: 1e-9)
    }

    /// CA10 — IC-09, 6.6 « Rappeler le CUE pendant que je retiens le disque » : le saut au CUE
    /// disque tenu recale le disque et ré-ancre le geste ; le disque suit le doigt depuis le CUE.
    func testRecallCueWhileHeldReanchorsGesture_IC09() {
        let harness = PhysicsHarness()
        harness.physics.seek(to: 12)
        harness.physics.setCue()
        harness.physics.seek(to: 20.3)
        let start = harness.time
        harness.schedule(from: start, to: start + 2, release: false) { t in
            t - start < 0.5 ? 0 : 2 * .pi * min(1, (t - start - 0.5) / 0.5)
        }
        harness.run(seconds: 0.3)
        let error = harness.physics.holdTrackingError
        harness.physics.recallCue()
        XCTAssertEqual(harness.physics.positionSeconds, 12)
        XCTAssertEqual(harness.physics.holdTrackingError, error, accuracy: 1e-12, "the disc stays under the finger")
        XCTAssertEqual(misalignment(harness.physics), 0, accuracy: 1e-9)
        XCTAssertEqual(wrapped(harness.physics.stickerAngle), 0, accuracy: 1e-9, "sticker at noon on the CUE")
        harness.run(seconds: 1.5)
        XCTAssertEqual(harness.physics.positionSeconds, 13.8, accuracy: 1e-6, "one turn from the CUE")
    }

    // MARK: STOP immédiat (CA 11)

    /// CA11 — RM-56 : ωp = 0 sans rampe, moteur STOP, disque libre arrêté, position conservée ;
    /// disque tenu : reste tenu, sans saut.
    func testStopAllMotorsImmediately_RM56() {
        let harness = PhysicsHarness()
        harness.spinUp()
        let position = harness.physics.positionSeconds
        harness.physics.stopMotorImmediately()
        XCTAssertEqual(harness.physics.platterVelocity, 0)
        XCTAssertFalse(harness.physics.motorOn)
        XCTAssertEqual(harness.physics.discVelocity, 0)
        XCTAssertEqual(harness.physics.playbackRate, 0)
        let output = harness.run(seconds: 0.5)
        XCTAssertTrue(output.rates.allSatisfy { $0 == 0 })
        XCTAssertEqual(harness.physics.positionSeconds, position)

        let held = PhysicsHarness()
        held.spinUp()
        let start = held.time
        held.schedule(from: start, to: start + 1, release: false) { self.reference * ($0 - start) }
        held.run(seconds: 0.4)
        let before = held.physics
        held.physics.stopMotorImmediately()
        XCTAssertTrue(held.physics.isHeld)
        XCTAssertEqual(held.physics.platterVelocity, 0)
        XCTAssertEqual(held.physics.discAngle, before.discAngle)
        XCTAssertEqual(held.physics.discVelocity, before.discVelocity)
        XCTAssertEqual(held.physics.playbackRate, before.playbackRate)
        let next = held.step()
        XCTAssertEqual(next.discVelocity, before.discVelocity, accuracy: 1e-6 * reference, "still following the finger")
    }

    // MARK: Temps réel (CA 12)

    /// CA12 : pas de dénormaux persistants (disque tenu immobile à 2 ms, disque entraîné à l'arrêt).
    func testNoSubnormalStates() {
        let harness = PhysicsHarness()
        harness.physics.setResistance(0)
        harness.spinUp()
        let start = harness.time
        harness.schedule(from: start, to: start + 4, release: false) { _ in 0 }
        let output = harness.run(seconds: 3)
        XCTAssertFalse(output.rates.contains { $0.isSubnormal })
        XCTAssertEqual(harness.physics.discVelocity, 0)
        XCTAssertEqual(harness.physics.holdTrackingError, 0)

        let coupled = PhysicsHarness()
        coupled.spinUp()
        coupled.physics.setMotor(false)
        let braking = coupled.run(seconds: 3)
        XCTAssertFalse(braking.rates.contains { $0.isSubnormal })
        XCTAssertEqual(coupled.physics.discVelocity, 0)
        XCTAssertEqual(coupled.physics.platterVelocity, 0)
    }

    /// CA12 : intégration à chaque échantillon, indépendante du découpage en blocs (déterminisme).
    func testOutputDoesNotDependOnBlockSize() {
        var finals = [[Double]]()
        for block in [1, 37, 256, 512] {
            let harness = PhysicsHarness()
            harness.physics.setMotor(true)
            let start = harness.run(samples: 48_000, block: block)
            harness.physics.setMotor(false)
            let stop = harness.run(samples: 24_000, block: block)
            finals.append(start.positions + stop.positions + [harness.physics.platterAngle])
        }
        for other in finals.dropFirst() { XCTAssertEqual(other, finals[0]) }
    }

    func testInvalidInputsAreIgnored() {
        var physics = DeckPhysics(sampleRate: .nan)
        XCTAssertEqual(physics.sampleRate, 48_000)
        physics.setSampleRate(0)
        XCTAssertEqual(physics.sampleRate, 48_000)
        physics.setResistance(.infinity)
        XCTAssertEqual(physics.resistance, TurntableConstants.defaultResistance)
        physics.setResistance(2)
        XCTAssertEqual(physics.holdTimeConstant, 0.035, accuracy: 1e-15)
        physics.reset(duration: .nan)
        XCTAssertEqual(physics.durationSeconds, 0)
        let buffer = UnsafeMutablePointer<Double>.allocate(capacity: 1)
        defer { buffer.deallocate() }
        physics.process(frameCount: 0, positions: buffer, rates: buffer)
        physics.process(frameCount: -1, positions: buffer, rates: buffer)
        XCTAssertEqual(physics.positionSeconds, 0)
    }
}
