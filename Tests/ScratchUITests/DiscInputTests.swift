import ScratchCore
import XCTest
@testable import ScratchUI

/// Saisie du disque (story 4.3) : coordonnées, attribution des contacts, annulation, disque vide,
/// envoi synchrone, minuterie du trackpad, géométrie relue à chaque événement.
@MainActor
final class DiscInputTests: XCTestCase {
    private final class ManualScheduler {
        var pending: [(delay: Double, action: @MainActor () -> Void)] = []
    }

    private var now = 0.0
    private let engine = RecordingEngine()
    private let scheduler = ManualScheduler()

    /// Platine B chargée et son coordinateur, sur une surface de 200 × 200 (R = 92, saisie 98).
    private func makeInput(loaded: Bool = true) -> DiscInputCoordinator {
        let deck = DeckViewModel(deck: .b, engine: engine)
        if loaded {
            let clip = PreviewDeckIntents.syntheticClip(title: "test.wav", duration: 10)
            deck.apply(DeckSnapshot(clipID: clip.id, durationSeconds: 10))
        }
        let input = DiscInputCoordinator(deck: .b, releaseTimer: ScrollReleaseTimer { [scheduler] delay, action in
            scheduler.pending.append((delay, action))
        })
        input.model = deck
        input.clock = { [unowned self] in self.now }
        input.updateGeometry(width: 200, height: 200)
        retained.append(deck)
        return input
    }

    private var retained: [DeckViewModel] = []

    /// Échantillon à `radius` du centre (100, 100), à `angle` depuis midi, sens horaire.
    private func sample(_ angle: Double, radius: Double = 80, time: Double, predicted: Bool = false) -> ContactSample {
        ContactSample(x: 100 + radius * sin(angle), y: 100 - radius * cos(angle), time: time, isPredicted: predicted)
    }

    // AC10 — repère de la vue → repère du traqueur ; géométrie UX §5.1.
    func testViewToTrackerCoordinates_FlippedAndUnflipped() async {
        let flipped = DiscGeometry.trackerPoint(x: 10, y: 30, height: 100, isFlipped: true)
        XCTAssertEqual(flipped.x, 10)
        XCTAssertEqual(flipped.y, 30)
        let unflipped = DiscGeometry.trackerPoint(x: 10, y: 30, height: 100, isFlipped: false)
        XCTAssertEqual(unflipped.y, 70, "y up → y down")
        let mac = DiscGeometry(width: 396, height: 396)
        XCTAssertEqual(mac.vinylRadius, 182.16, accuracy: 1e-9)
        XCTAssertEqual(mac.grabRadius, 188.16, accuracy: 1e-9, "R + 6")
        XCTAssertEqual(DiscGeometry(width: 100, height: 120).grabRadius, 50, "capped at P / 2")
    }

    // AC2, AC10 — RM-60 : premier contact propriétaire, deuxième ignoré, un seul relâchement.
    func testContactAttributionAndSecondFingerIgnored_RM60() async {
        let input = makeInput()
        input.contactBegan(1, at: sample(0, time: 1))
        input.contactBegan(2, at: sample(.pi, time: 1.01))
        input.contactMoved(2, samples: [sample(.pi + 0.2, time: 1.02)])
        input.contactEnded(2, time: 1.03)
        input.contactEnded(1, time: 1.04)
        XCTAssertEqual(engine.sentCommands, [.touchBegan(.b, angle: 0, time: 1), .touchEnded(.b, time: 1.04)])
        input.contactBegan(3, at: ContactSample(x: 199, y: 199, time: 2))
        XCTAssertEqual(engine.sentCommands.count, 2, "a corner of the square is outside the grab zone")
    }

    // AC2, AC8 — RM-60 : l'annulation programmée relâche le contact et le défilement.
    func testCancelReleasesTheDisc_RM60() async {
        let input = makeInput()
        input.contactBegan(1, at: sample(0, time: 1))
        now = 1.5
        input.cancelAll()
        XCTAssertEqual(engine.sentCommands.last, .touchEnded(.b, time: 1.5))
        XCTAssertFalse(input.isHolding)
        input.scroll(x: 100, y: 20, deltaX: 0, deltaY: 0, phase: .began, time: 3)
        input.cancelAll(time: 3.01)
        guard case let .touchEnded(_, time) = engine.sentCommands.last else { return XCTFail() }
        XCTAssertEqual(time, 3.08, accuracy: 1e-9, "scroll released at its deadline")
        XCTAssertFalse(input.isHolding)
    }

    // AC2 — un disque vide n'est saisissable ni au doigt ni au trackpad.
    func testEmptyDeckIsNotGrabbable() async {
        let input = makeInput(loaded: false)
        input.contactBegan(1, at: sample(0, time: 1))
        input.scroll(x: 100, y: 20, deltaX: 0, deltaY: 0, phase: .began, time: 2)
        input.scroll(x: 100, y: 20, deltaX: 8, deltaY: 0, phase: .changed, time: 2.01)
        XCTAssertEqual(engine.sentCommands, [])
        XCTAssertFalse(input.isGrabbable(x: 100, y: 20))
    }

    // AC1, AC6 — SF-78 : regroupées puis prédites, horodatages exacts, envoi dans l'appel même.
    func testCommandsAreSentSynchronouslyWithTimestamps_SF78() async {
        let input = makeInput()
        input.contactBegan(1, at: sample(0, time: 10))
        input.contactMoved(1, samples: [sample(0.01, time: 10.004), sample(0.02, time: 10.008),
                                        sample(0.05, time: 10.016, predicted: true)])
        let moves = engine.sentCommands.dropFirst()
        XCTAssertEqual(moves.count, 3, "sent before returning, without any interface refresh")
        guard moves.count == 3 else { return }
        let times = moves.compactMap { command -> Double? in
            if case let .touchMoved(_, _, time, _) = command { return time }
            return nil
        }
        let predicted = moves.compactMap { command -> Bool? in
            if case let .touchMoved(_, _, _, predicted) = command { return predicted }
            return nil
        }
        XCTAssertEqual(times, [10.004, 10.008, 10.016])
        XCTAssertEqual(predicted, [false, false, true])
    }

    // AC4 — SF-79 : minuterie réarmée à chaque événement, relâchement daté de dernier + 80 ms.
    func testScrollReleaseTimerFiresAt80ms_SF79() async {
        let input = makeInput()
        now = 10
        input.scroll(x: 100, y: 20, deltaX: 0, deltaY: 0, phase: .began, time: 10)
        now = 10.05
        input.scroll(x: 100, y: 20, deltaX: 8, deltaY: 0, phase: .changed, time: 10.05)
        XCTAssertEqual(scheduler.pending.map(\.delay).last ?? 0, 0.08, accuracy: 1e-9)
        now = 10.12
        scheduler.pending.first?.action()
        XCTAssertTrue(input.isHolding, "a superseded deadline does nothing")
        now = 10.13
        scheduler.pending.last?.action()
        XCTAssertFalse(input.isHolding)
        guard case let .touchEnded(deck, time) = engine.sentCommands.last else { return XCTFail() }
        XCTAssertEqual(deck, .b)
        XCTAssertEqual(time, 10.13, accuracy: 1e-9)
    }

    // AC5 — 6.14 : la géométrie relue en cours de geste ne crée aucun saut d'angle.
    func testGeometryIsReadOnEveryEvent_6_14() async {
        let input = makeInput()
        input.contactBegan(1, at: sample(.pi / 2, time: 1))
        input.contactMoved(1, samples: [sample(.pi / 2 + 0.1, time: 1.01)])
        // The window grows: the surface is now 300 × 300 (center 150, 150), the pointer has not moved.
        input.updateGeometry(width: 300, height: 300)
        let last = sample(.pi / 2 + 0.1, time: 0)
        let lastRaw = atan2(last.x - 150, 150 - last.y)
        let next = ContactSample(x: 150 + 120 * sin(lastRaw + 0.05), y: 150 - 120 * cos(lastRaw + 0.05), time: 1.02)
        input.contactMoved(1, samples: [next])
        let angles = engine.sentCommands.compactMap { command -> Double? in
            if case let .touchMoved(_, angle, _, _) = command { return angle }
            return nil
        }
        XCTAssertEqual(angles.count, 2)
        XCTAssertEqual((angles.last ?? 0) - (angles.first ?? 0), 0.05, accuracy: 1e-9, "no jump, tracking continues")
    }

    // AC4 — D-24 : les deltas d'AppKit sont ramenés au déplacement des doigts.
    func testScrollDeltasFollowTheFingers_D24() async {
        let natural = DiscGeometry.fingerDelta(scrollingDeltaX: 3, scrollingDeltaY: -2, invertedFromDevice: true)
        XCTAssertEqual(natural.dx, 3)
        XCTAssertEqual(natural.dy, -2)
        let classic = DiscGeometry.fingerDelta(scrollingDeltaX: 3, scrollingDeltaY: -2, invertedFromDevice: false)
        XCTAssertEqual(classic.dx, -3)
        XCTAssertEqual(classic.dy, 2)
    }
}
