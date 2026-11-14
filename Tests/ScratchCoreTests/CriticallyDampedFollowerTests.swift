import Foundation
import XCTest
@testable import ScratchCore

/// Filtre du disque tenu (story 1.1, T1 ; spec 5.1 point 3, SF-22, SF-23, RM-12).
final class CriticallyDampedFollowerTests: XCTestCase {
    private let dt = 1 / 48_000.0

    /// Réponse indicielle exacte : θ(t) = 1 − (1 + t/τ) e^(−t/τ), sans dépassement (5.1 point 3).
    func testStepResponseMatchesAnalyticSolutionWithoutOvershoot() {
        for tau in [0.002, 0.0185, 0.035] {
            var follower = CriticallyDampedFollower()
            let coefficients = CriticallyDampedFollower.Coefficients(timeConstant: tau, dt: dt)
            var previous = 0.0
            for n in 1...Int(0.5 * 48_000) {
                follower.step(target: 1, coefficients: coefficients)
                let t = Double(n) * dt
                let expected = 1 - (1 + t / tau) * exp(-t / tau)
                if abs(follower.angle - expected) > 1e-12 {
                    XCTFail("τ = \(tau): θ(\(t)) = \(follower.angle), expected \(expected)")
                    return
                }
                XCTAssertGreaterThanOrEqual(follower.angle, previous, "monotonic, no overshoot")
                XCTAssertLessThanOrEqual(follower.angle, 1)
                previous = follower.angle
            }
            for _ in 0..<Int(2.0 / dt) { follower.step(target: 1, coefficients: coefficients) }
            XCTAssertEqual(follower.angle, 1, "fixed target reached exactly (rest snap)")
            XCTAssertEqual(follower.velocity, 0)
        }
    }

    /// Cible en rampe : la vitesse rejoint celle de la cible et le retard tend vers 2τ.
    func testRampIsTrackedWithTwoTauLag() {
        let tau = 0.0185
        let speed = 2 * TurntableConstants.referenceAngularVelocity
        var follower = CriticallyDampedFollower()
        let coefficients = CriticallyDampedFollower.Coefficients(timeConstant: tau, dt: dt)
        var target = 0.0
        for _ in 0..<Int(0.5 * 48_000) {
            target += speed * dt
            follower.step(target: target, coefficients: coefficients)
        }
        // Zero-order hold: the sampled speed sits (h/τ)²/12 below the mean speed (≈ 1e-7 here) and the
        // held target leads the ramp by half a sample, so the lag is 2τ − h/2.
        let h = dt / tau
        XCTAssertEqual(follower.velocity, speed * (1 - h * h / 12), accuracy: speed * 1e-9)
        XCTAssertEqual(target - follower.angle, speed * (2 * tau - dt / 2), accuracy: speed * dt * 0.01)
    }

    /// RM-12 : doigt immobile après une rampe à 2 × ωref : |ω| ≤ 10⁻³ × ωref au plus 10 τ après
    /// l'immobilisation (`ω(t) = v (1 + t/τ) e^(−t/τ)`), puis exactement 0.
    func testVelocityVanishesAfterTargetStops_RM12() {
        let reference = TurntableConstants.referenceAngularVelocity
        for tau in [0.002, 0.0185, 0.035] {
            var follower = CriticallyDampedFollower()
            let coefficients = CriticallyDampedFollower.Coefficients(timeConstant: tau, dt: dt)
            var target = 0.0
            for _ in 0..<Int(0.5 * 48_000) {
                target += 2 * reference * dt
                follower.step(target: target, coefficients: coefficients)
            }
            for _ in 0..<Int(10 * tau / dt) { follower.step(target: target, coefficients: coefficients) }
            XCTAssertLessThanOrEqual(abs(follower.velocity), 1e-3 * reference, "τ = \(tau)")
            for _ in 0..<Int(2.0 / dt) { follower.step(target: target, coefficients: coefficients) }
            XCTAssertEqual(follower.velocity, 0, "τ = \(tau): exact rest, no subnormal tail")
            XCTAssertEqual(follower.angle, target)
        }
    }

    /// Saisie d'un disque en rotation (vitesse initiale v₀, cible fixe) : x(t) = v₀ t e^(−t/τ),
    /// crête v₀ τ / e, puis retour sur la cible (aller-retour attendu du modèle, story 1.1).
    func testInitialVelocityOvershootsByV0TauOverEAndReturns() {
        let tau = 0.035
        let v0 = TurntableConstants.referenceAngularVelocity
        var follower = CriticallyDampedFollower()
        follower.reset(angle: 5, velocity: v0)
        let coefficients = CriticallyDampedFollower.Coefficients(timeConstant: tau, dt: dt)
        var peak = 0.0
        for _ in 0..<Int(1.0 / dt) {
            follower.step(target: 5, coefficients: coefficients)
            peak = max(peak, follower.angle - 5)
        }
        XCTAssertEqual(peak, v0 * tau / M_E, accuracy: v0 * tau / M_E * 1e-4)
        XCTAssertEqual(follower.angle, 5, accuracy: 1e-9)
    }

    /// SF-23 : changer τ entre deux pas ne modifie pas l'état ; le pas suivant reste borné par la
    /// dynamique du nouveau τ (aucune marche d'angle ni de vitesse).
    func testTimeConstantChangeKeepsStateContinuous_SF23() {
        var follower = CriticallyDampedFollower()
        var target = 0.0
        let speed = 5.0
        for _ in 0..<4_800 {
            target += speed * dt
            follower.step(target: target, timeConstant: 0.035, dt: dt)
        }
        let angle = follower.angle
        let velocity = follower.velocity
        let error = angle - target
        target += speed * dt
        follower.step(target: target, timeConstant: 0.002, dt: dt)
        let acceleration = abs(angle - target) / (0.002 * 0.002) + 2 * abs(velocity) / 0.002
        XCTAssertLessThanOrEqual(abs(follower.velocity - velocity), acceleration * dt * 1.05)
        XCTAssertLessThanOrEqual(abs(follower.angle - angle), (abs(velocity) + acceleration * dt) * dt * 1.05)
        XCTAssertLessThan(abs(follower.angle - angle), abs(error) / 10, "no snap onto the target")
    }

    func testZeroOrInvalidTimeConstantAlignsImmediately() {
        for tau in [0.0, -1.0, .nan, .infinity] {
            var follower = CriticallyDampedFollower(angle: 1, velocity: 3)
            follower.step(target: 2, timeConstant: tau, dt: dt)
            XCTAssertEqual(follower.angle, 2, "τ = \(tau)")
            XCTAssertEqual(follower.velocity, 0, "τ = \(tau)")
        }
    }

    func testShiftAndVelocityLimit() {
        var follower = CriticallyDampedFollower(angle: 1, velocity: 2)
        follower.shift(by: 0.5)
        XCTAssertEqual(follower.angle, 1.5)
        XCTAssertEqual(follower.velocity, 2)

        follower.reset(angle: 0, velocity: 0)
        follower.step(target: 10, timeConstant: 0.002, dt: 0.001)
        XCTAssertGreaterThan(follower.velocity, 50)
        follower.limitVelocity(to: 50, previousAngle: 0, dt: 0.001)
        XCTAssertEqual(follower.velocity, 50)
        XCTAssertLessThanOrEqual(follower.angle, 0.05 + 1e-15)
    }
}
