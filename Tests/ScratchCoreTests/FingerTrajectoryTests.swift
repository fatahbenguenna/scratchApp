import XCTest
@testable import ScratchCore

/// Reconstruction de la trajectoire du doigt (ADR-07, spec 5.1 point 4, SF-77, SF-78).
///
/// Simulation réaliste : touches horodatées à `touchRate`, livrées par lots à chaque image
/// (`displayRate`) avec un délai de chaîne et une gigue, vues par le fil audio au début de chaque
/// tampon de 256 trames à 48 kHz.
final class FingerTrajectoryTests: XCTestCase {
    private let sampleRate = 48_000.0
    private let blockFrames = 256

    private struct Delivery {
        var arrival: Double
        var events: [(time: Double, angle: Double)]
    }

    /// Générateur pseudo-aléatoire déterministe (LCG).
    private struct LCG {
        var state: UInt64 = 0x2545F4914F6CDD1D
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    private func deliveries(duration: Double, touchRate: Double, displayRate: Double,
                            pipeline: Double = 0.008, jitter: Double = 0.002,
                            finger: (Double) -> Double) -> [Delivery] {
        var generator = LCG()
        var result = [Delivery]()
        var nextTouch = 0.0013
        var frame = 0.0
        while frame < duration + 0.1 {
            var events = [(time: Double, angle: Double)]()
            while nextTouch <= frame - pipeline, nextTouch < duration {
                events.append((nextTouch, finger(nextTouch)))
                nextTouch += 1 / touchRate
            }
            if !events.isEmpty {
                result.append(Delivery(arrival: frame + generator.next() * jitter, events: events))
            }
            frame += 1 / displayRate
        }
        return result
    }

    /// Rejoue les lots comme le ferait le moteur et renvoie la cible échantillon par échantillon.
    private func playOut(_ deliveries: [Delivery], duration: Double, initialDelay: Double? = nil,
                         releaseAt releaseTime: Double? = nil) -> (targets: [Double], trajectory: FingerTrajectory) {
        var configuration = FingerTrajectory.Configuration()
        if let initialDelay { configuration.initialDelay = initialDelay }
        var trajectory = FingerTrajectory(sampleRate: sampleRate, configuration: configuration)
        let total = Int(duration * sampleRate)
        var targets = [Double](repeating: .nan, count: total)
        var next = 0
        var started = false
        var released = false
        var start = 0
        while start < total {
            let blockTime = Double(start) / sampleRate
            while next < deliveries.count, deliveries[next].arrival <= blockTime {
                for event in deliveries[next].events {
                    if started {
                        trajectory.append(angle: event.angle, time: event.time)
                    } else {
                        trajectory.begin(angle: event.angle, time: event.time)
                        started = true
                    }
                }
                next += 1
            }
            if let releaseTime, !released, next >= deliveries.count, blockTime >= releaseTime {
                trajectory.end(time: releaseTime)
                released = true
            }
            trajectory.prepareBlock()
            for index in start..<min(total, start + blockFrames) where started {
                targets[index] = trajectory.nextTarget()
            }
            start += blockFrames
        }
        return (targets, trajectory)
    }

    private func velocities(_ targets: [Double], from: Double, to: Double) -> [Double] {
        let first = Int(from * sampleRate)
        let last = Int(to * sampleRate)
        return (first..<last).map { (targets[$0 + 1] - targets[$0]) * sampleRate }
    }

    /// Vitesse de doigt constante (≈ 33⅓ RPM) : la vitesse reconstruite est continue et sans
    /// « trous » (pas de marches de vitesse), malgré des lots irréguliers. Affichage 120 Hz.
    func testConstantGestureGivesContinuousVelocityAt120Hz_SF77() {
        let omega = TurntableConstants.referenceAngularVelocity
        let input = deliveries(duration: 1.5, touchRate: 120, displayRate: 120) { omega * $0 }
        let (targets, trajectory) = playOut(input, duration: 1.5)
        let speeds = velocities(targets, from: 0.5, to: 1.4)
        let minimum = speeds.min()!
        let maximum = speeds.max()!
        XCTAssertGreaterThan(minimum, omega * 0.95, "no velocity hole (starvation) once settled")
        XCTAssertLessThan(maximum, omega * 1.05)
        let steps = zip(speeds.dropFirst(), speeds).map { abs($0 - $1) }
        XCTAssertLessThan(steps.max()!, omega * 0.01, "no velocity step above 1 % per sample")
        XCTAssertLessThanOrEqual(trajectory.delay, 0.020, "added latency stays ≤ 20 ms at 120 Hz")
    }

    /// Même essai avec un affichage à 60 Hz et des touches à 120 Hz : le retard s'adapte (famine
    /// au début), puis la vitesse reste continue.
    func testConstantGestureAdaptsDelayAt60Hz_SF78() {
        let omega = TurntableConstants.referenceAngularVelocity
        let input = deliveries(duration: 2.0, touchRate: 120, displayRate: 60) { omega * $0 }
        let (targets, trajectory) = playOut(input, duration: 2.0)
        let speeds = velocities(targets, from: 1.0, to: 1.9)
        XCTAssertGreaterThan(speeds.min()!, omega * 0.95)
        XCTAssertLessThan(speeds.max()!, omega * 1.05)
        XCTAssertGreaterThan(trajectory.delay, 0.012, "the delay grew to absorb 60 Hz delivery")
        XCTAssertLessThanOrEqual(trajectory.delay, trajectory.configuration.maximumDelay)
    }

    /// Profils d'appareils (touches 120/240 Hz, affichage 60/120 Hz, gigue 2/5 ms) : après
    /// adaptation, aucune famine et une vitesse à ±5 % ; retard borné.
    func testDeviceProfilesSettleWithoutStarvation_SF78() {
        let omega = TurntableConstants.referenceAngularVelocity
        for touchRate in [120.0, 240.0] {
            for displayRate in [60.0, 120.0] {
                for jitter in [0.002, 0.005] {
                    let input = deliveries(duration: 3.0, touchRate: touchRate, displayRate: displayRate,
                                           jitter: jitter) { omega * $0 }
                    let (targets, trajectory) = playOut(input, duration: 3.0)
                    let speeds = velocities(targets, from: 1.5, to: 2.9)
                    let profile = "touch \(touchRate) Hz, display \(displayRate) Hz, jitter \(jitter) s"
                    XCTAssertGreaterThan(speeds.min()!, omega * 0.95, profile)
                    XCTAssertLessThan(speeds.max()!, omega * 1.05, profile)
                    XCTAssertLessThanOrEqual(trajectory.delay, displayRate >= 120 ? 0.020 : 0.030, profile)
                }
            }
        }
    }

    /// Doigt immobilisé : la cible converge exactement vers l'angle final et la vitesse devient
    /// nulle (RM-12 : un doigt fixe immobilise le disque).
    func testFingerStopConvergesToFinalAngleWithZeroVelocity_RM12() {
        let omega = TurntableConstants.referenceAngularVelocity
        let stopTime = 0.4
        let input = deliveries(duration: 1.0, touchRate: 120, displayRate: 120) { min($0, stopTime) * omega }
        let (targets, _) = playOut(input, duration: 1.0)
        let final = stopTime * omega
        XCTAssertEqual(targets[Int(0.8 * sampleRate)], final, accuracy: 1e-9)
        XCTAssertTrue(velocities(targets, from: 0.8, to: 0.99).allSatisfy { abs($0) < 1e-9 })
    }

    /// Baby scratch (8 allers-retours par seconde sur un quart de tour) : la cible suit le geste
    /// et revient au point de départ ; l'erreur résiduelle est la latence de rejeu, pas une dérive.
    func testBabyScratchFollowsGestureAndReturnsToStart() {
        let amplitude = Double.pi / 4
        let finger: (Double) -> Double = { amplitude * sin(2 * Double.pi * 8 * $0) }
        let input = deliveries(duration: 1.0, touchRate: 120, displayRate: 120, finger: finger)
        let (targets, trajectory) = playOut(input, duration: 1.0)
        let delay = trajectory.delay
        var worst = 0.0
        for index in stride(from: Int(0.4 * sampleRate), to: Int(0.9 * sampleRate), by: 7) {
            let t = Double(index) / sampleRate
            // Compare with the finger shifted by the playout delay plus the delivery pipeline span.
            let best = stride(from: 0.0, through: 0.04, by: 0.0005).map { abs(targets[index] - finger(t - $0)) }.min()!
            worst = max(worst, best)
        }
        // 10 ms of sound at 33⅓ RPM ≈ 0.035 rad (6.3 : retour au point de départ à ±10 ms près).
        XCTAssertLessThan(worst, 0.035)
        XCTAssertGreaterThan(delay, 0)
    }

    /// Le relâchement est rejoué avec le même retard : le disque reste tenu jusqu'à la fin du geste.
    func testReleaseIsPlayedOutAfterTheLastMovement() {
        let omega = TurntableConstants.referenceAngularVelocity
        let input = deliveries(duration: 0.5, touchRate: 120, displayRate: 120) { omega * $0 }
        let (targets, trajectory) = playOut(input, duration: 0.8, releaseAt: 0.55)
        XCTAssertFalse(trajectory.isActive, "released once the playhead reached the end time")
        let lastEvent = input.last!.events.last!
        XCTAssertEqual(targets.last!, lastEvent.angle, accuracy: 1e-9, "the whole gesture was played")
    }

    func testNonMonotonicAndNonFiniteEventsAreIgnored() {
        var trajectory = FingerTrajectory(sampleRate: sampleRate)
        trajectory.begin(angle: 0, time: 10)
        trajectory.append(angle: 1, time: 10.01)
        trajectory.append(angle: 5, time: 10.005)
        trajectory.append(angle: .nan, time: 10.02)
        trajectory.append(angle: 2, time: .infinity)
        trajectory.prepareBlock()
        var last = 0.0
        for _ in 0..<Int(0.1 * sampleRate) { last = trajectory.nextTarget() }
        XCTAssertEqual(last, 1, accuracy: 1e-12)
    }
}
