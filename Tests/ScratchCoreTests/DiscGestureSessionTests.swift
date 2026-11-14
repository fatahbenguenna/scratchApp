import Foundation
import XCTest
@testable import ScratchCore

/// Session de geste d'un disque (story 1.2) : contact propriétaire, échantillons regroupés et
/// prédits, commandes moteur ; de bout en bout avec `ScratchEngine` pour D-16 et la reprise rapide.
final class DiscGestureSessionTests: XCTestCase {
    private let degree = Double.pi / 180

    private func session(_ deck: DeckID = .a) -> DiscGestureSession {
        DiscGestureSession(deck: deck, centerX: 100, centerY: 100, vinylRadius: 80, grabRadius: 86)
    }

    /// Échantillon à 80 pt du centre, à `angle` depuis midi (sens horaire).
    private func sample(_ angle: Double, time: Double, predicted: Bool = false) -> ContactSample {
        ContactSample(x: 100 + 80 * sin(angle), y: 100 - 80 * cos(angle), time: time, isPredicted: predicted)
    }

    // AC3 — RM-60 (scénario « Deuxième doigt ignoré »)
    func testSecondContactIgnoredUntilRelease_RM60() {
        var disc = session()
        XCTAssertEqual(disc.began(contact: 1, at: sample(0, time: 1)), .touchBegan(.a, angle: 0, time: 1))
        XCTAssertNil(disc.began(contact: 2, at: sample(.pi, time: 1.01)))
        XCTAssertEqual(disc.moved(contact: 2, samples: [sample(.pi + 0.3, time: 1.02)]), [])
        XCTAssertNil(disc.ended(contact: 2, time: 1.03))
        XCTAssertEqual(disc.ended(contact: 1, time: 1.04), .touchEnded(.a, time: 1.04))
        XCTAssertNil(disc.ended(contact: 1, time: 1.05), "a single touchEnded")
        XCTAssertNotNil(disc.began(contact: 2, at: sample(.pi, time: 1.06)), "free again after the release")
    }

    // AC2 — RM-60 : départ hors du disque puis entrée : aucune commande ; sortie : saisie gardée.
    func testGrabOnlyOnStartAndLeavingKeepsTheGrab_RM60() {
        var disc = session()
        XCTAssertNil(disc.began(contact: 1, at: ContactSample(x: 195, y: 100, time: 1)))
        XCTAssertEqual(disc.moved(contact: 1, samples: [sample(.pi / 2, time: 1.01)]), [])
        XCTAssertNil(disc.ended(contact: 1, time: 1.02))

        XCTAssertNotNil(disc.began(contact: 3, at: sample(.pi / 2, time: 2)))
        let outside = ContactSample(x: 100, y: 300, time: 2.01)   // far below the disc
        XCTAssertEqual(disc.moved(contact: 3, samples: [outside]),
                       [.touchMoved(.a, angle: .pi, time: 2.01, predicted: false)], "angle still around the center")
    }

    // AC3 — SF-19, 6.8 : deux disques suivis indépendamment.
    func testTwoDiscsAreIndependent_SF19() {
        var discA = session(.a)
        var discB = DiscGestureSession(deck: .b, centerX: 400, centerY: 100, vinylRadius: 80, grabRadius: 86)
        XCTAssertNotNil(discA.began(contact: 1, at: sample(0, time: 1)))
        XCTAssertEqual(discB.began(contact: 2, at: ContactSample(x: 400, y: 20, time: 1.001)),
                       .touchBegan(.b, angle: 0, time: 1.001))
        XCTAssertEqual(discA.moved(contact: 1, samples: [sample(0.2, time: 1.01)]).count, 1)
        XCTAssertEqual(discB.moved(contact: 1, samples: [sample(0.4, time: 1.01)]), [], "contact 1 belongs to A")
        XCTAssertEqual(discB.ended(contact: 2, time: 1.02), .touchEnded(.b, time: 1.02))
        XCTAssertTrue(discA.isHolding)
    }

    // AC4 — RM-60 : annulation = relâchement, aucun état tenu ne subsiste.
    func testCancelIsARelease_RM60() {
        var disc = session()
        _ = disc.began(contact: 7, at: sample(0, time: 1))
        _ = disc.moved(contact: 7, samples: [sample(0.1, time: 1.02)])
        XCTAssertEqual(disc.cancelAll(time: 1.01), .touchEnded(.a, time: 1.02), "never earlier than the last sample")
        XCTAssertFalse(disc.isHolding)
        XCTAssertFalse(disc.tracker.isTracking)
        XCTAssertNil(disc.cancelAll(time: 1.03))
    }

    // AC6, AC9 — SF-78 : lots regroupés puis prédits, dans l'ordre, horodatés, platine portée.
    func testCoalescedSamplesAreOrderedAndTimed_SF78() {
        var disc = session(.b)
        _ = disc.began(contact: 1, at: sample(0, time: 10))
        let commands = disc.moved(contact: 1, samples: [
            sample(1 * degree, time: 10.004), sample(2 * degree, time: 10.008), sample(3 * degree, time: 10.008),
            sample(5 * degree, time: 10.016, predicted: true),
        ])
        XCTAssertEqual(commands.count, 3, "a non-increasing time is unfolded but not sent")
        guard commands.count == 3,
              case let .touchMoved(deck0, angle0, time0, predicted0) = commands[0],
              case let .touchMoved(_, angle1, time1, predicted1) = commands[1],
              case let .touchMoved(_, angle2, time2, predicted2) = commands[2] else { return XCTFail("\(commands)") }
        XCTAssertEqual(deck0, .b)
        XCTAssertEqual([time0, time1, time2], [10.004, 10.008, 10.016])
        XCTAssertEqual([predicted0, predicted1, predicted2], [false, false, true])
        XCTAssertEqual(angle0, 1 * degree, accuracy: 1e-9)
        XCTAssertEqual(angle1, 2 * degree, accuracy: 1e-9)
        XCTAssertEqual(angle2, 5 * degree, accuracy: 1e-9)
    }

    // AC6 — SF-78 : une prédiction fausse n'entraîne aucune erreur cumulée.
    func testPredictedSamplesDoNotAccumulateError_SF78() {
        var disc = session()
        _ = disc.began(contact: 1, at: sample(0, time: 1))
        var angle = 0.0
        for index in 1...30 {
            let time = 1 + Double(index) / 120
            let commands = disc.moved(contact: 1, samples: [
                sample(Double(index) * degree, time: time),
                sample(Double(index) * degree + 2.5, time: time + 0.008, predicted: true),   // wildly wrong
            ])
            if case let .touchMoved(_, real, _, false) = commands.first { angle = real }
        }
        XCTAssertEqual(angle, 30 * degree, accuracy: 1e-9)
    }

    // AC6 — D-16 : décision du calibrage, le moteur ignore les touches prédites.
    func testPredictedTouchesAreIgnoredByTheEngine_D16() {
        let plain = ScratchEngine()
        let predicted = ScratchEngine()
        var disc = session()
        for engine in [plain, predicted] { engine.send(.load(.a, Self.silence())) }
        let began = disc.began(contact: 1, at: sample(0, time: 50))!
        plain.send(began)
        predicted.send(began)
        for index in 1...24 {
            let time = 50 + Double(index) / 120
            for command in disc.moved(contact: 1, samples: [
                sample(Double(index) * 3 * degree, time: time),
                sample(Double(index) * 3 * degree - 1, time: time + 0.008, predicted: true),
            ]) {
                if case .touchMoved(_, _, _, false) = command { plain.send(command) }
                predicted.send(command)
            }
            render(plain, seconds: 1.0 / 120)
            render(predicted, seconds: 1.0 / 120)
        }
        var withPredictions = predicted.latestSnapshot().decks.a
        var withoutPredictions = plain.latestSnapshot().decks.a
        XCTAssertGreaterThan(withoutPredictions.discAngle, 0.5, "the disc follows the real touches")
        withPredictions.clipID = nil   // two clips, two identifiers
        withoutPredictions.clipID = nil
        XCTAssertEqual(withPredictions, withoutPredictions)
    }

    // RM-60, commentaire de QA sur l'issue #20 : un contact posé pendant le rejeu du relâchement
    // précédent (≈ 14 à 21 ms) n'est pas perdu ; le disque suit le nouveau doigt depuis le point de
    // relâchement, sans saut.
    func testQuickRegrabDuringReleaseReplayKeepsTheDisc_RM60() {
        let engine = ScratchEngine()
        engine.send(.load(.a, Self.silence()))
        var disc = session()
        // First contact: +1 rad clockwise in 0.1 s, then lifted at t = 100.1 s.
        engine.send(disc.began(contact: 1, at: sample(.pi / 2, time: 100))!)
        for index in 1...12 {
            disc.moved(contact: 1, samples: [sample(.pi / 2 + Double(index) / 12, time: 100 + Double(index) / 120)])
                .forEach { engine.send($0) }
        }
        engine.send(disc.ended(contact: 1, time: 100.1)!)
        render(engine, seconds: 0.105)
        XCTAssertTrue(engine.latestSnapshot().decks.a.isHeld, "the release is still being replayed")

        // Second contact, elsewhere on the disc, 5 ms after the lift: resumes the gesture.
        let regrab = disc.began(contact: 2, at: sample(-2, time: 100.105))
        XCTAssertNotNil(regrab)
        engine.send(regrab!)
        render(engine, seconds: 0.03)
        XCTAssertTrue(engine.latestSnapshot().decks.a.isHeld, "still held after the first release time")
        for index in 1...12 {
            disc.moved(contact: 2, samples: [sample(-2 + Double(index) / 24, time: 100.105 + Double(index) / 120)])
                .forEach { engine.send($0) }
        }
        render(engine, seconds: 0.5)
        let deck = engine.latestSnapshot().decks.a
        XCTAssertTrue(deck.isHeld)
        XCTAssertEqual(deck.discAngle, 1.5, accuracy: 1e-3, "release point (+1 rad) then +0.5 rad, no jump")
    }

    // MARK: Moteur

    /// Son silencieux de 10 s : la tête ne bute pas pendant les essais.
    private static func silence() -> AudioClip {
        AudioClip(title: "silence", sampleRate: 48_000, frameCount: 480_000) { _, _ in }
    }

    private func render(_ engine: ScratchEngine, seconds: Double) {
        var left = [Float](repeating: 0, count: 256)
        var right = [Float](repeating: 0, count: 256)
        var remaining = Int((seconds * 48_000).rounded())
        while remaining > 0 {
            let frames = min(256, remaining)
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in
                    engine.render(frameCount: frames, left: l.baseAddress!, right: r.baseAddress!)
                }
            }
            remaining -= frames
        }
    }
}
