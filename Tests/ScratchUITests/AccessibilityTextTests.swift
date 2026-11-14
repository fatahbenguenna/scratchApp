import ScratchCore
import XCTest
@testable import ScratchUI

/// Textes parlés, ajustements et annonces de l'écran principal (story 5.3 ; SF-83 ; UX §8.6, §11.2).
@MainActor
final class AccessibilityTextTests: XCTestCase {
    private let engine = RecordingEngine()

    private func loadedDeck(position: Double = 12.34, cue: Double? = 4, motorOn: Bool = true) -> DeckViewModel {
        let deck = DeckViewModel(deck: .a, engine: engine, waveformCache: WaveformCache { _, _ in nil })
        let clip = PreviewDeckIntents.syntheticClip(title: "voix_funk.wav", duration: 225)
        deck.apply(DeckSnapshot(clipID: clip.id, durationSeconds: 225, positionSeconds: position, motorOn: motorOn,
                                pitch: 0.053, cueSeconds: cue))
        return deck
    }

    // AC1 — 6.16 « Libellés VoiceOver » : la valeur de chaque commande (UX §11.2).
    func testSpokenValuesForEveryControl_SF83() async {
        let deck = loadedDeck()
        XCTAssertEqual(deck.headerAccessibilityValue, "position 12,3 secondes sur 3 minutes 45 secondes")
        XCTAssertEqual(deck.discAccessibilityValue, "en rotation, 33 tours un tiers, position 12,3 secondes")
        XCTAssertEqual(deck.overviewAccessibilityValue,
                       "position 12,3 secondes sur 3 minutes 45 secondes, CUE à 4 secondes")
        XCTAssertEqual(deck.startStopAccessibilityLabel, "STOP, platine A")
        XCTAssertEqual(deck.startStopAccessibilityValue, "moteur en marche")
        XCTAssertEqual(deck.cueAccessibilityValue, "CUE à 4 secondes")
        XCTAssertEqual(deck.pitchText, "+5,3\u{00A0}%")
        XCTAssertEqual(deck.resistanceText, "50\u{00A0}%")
        XCTAssertEqual(AccessibilityText.cue(nil), "aucun CUE, retour au début")
        XCTAssertEqual(AccessibilityText.time(72.34), "1 minute 12,3 secondes")
        XCTAssertEqual(AccessibilityText.time(-1.2), "moins 1,2 seconde")

        let mixer = MixerViewModel(engine: engine)
        XCTAssertEqual(mixer.lineFaderText(.a), "100\u{00A0}%")
        XCTAssertEqual(mixer.crossfaderAccessibilityValue, "50\u{00A0}%, centre")
        XCTAssertEqual(mixer.curveAccessibilityValue, "coupure franche")
        XCTAssertEqual(AccessibilityText.curve(0), "douce")
        XCTAssertEqual(AccessibilityText.curve(0.6), "60\u{00A0}%")
        XCTAssertEqual(AccessibilityText.toggle(mixer.hamster), "désactivé")
        XCTAssertEqual(SaturationState().accessibilityValue, "aucune")
        XCTAssertEqual(VUMeterBallistics().accessibilityValue, "silence")
    }

    // AC2 — 6.16 « Régler le pitch par les actions d'accessibilité » et les autres pas de l'UX §11.2.
    func testAdjustableStepsAndAnnouncements_6_16() async {
        let deck = loadedDeck(position: 100)
        deck.nudgePitch(steps: 1)
        XCTAssertEqual(deck.pitchText, "+5,4\u{00A0}%", "+0,1 %, the new value is spoken")
        deck.nudgeResistance(steps: -1)
        XCTAssertEqual(deck.resistanceText, "45\u{00A0}%")
        deck.nudgeNeedle(steps: 1)
        XCTAssertEqual(engine.sentCommands.last, .seek(.a, seconds: 111.25), "+5 % of the duration")

        let mixer = MixerViewModel(engine: engine)
        mixer.nudgeLineFader(.b, steps: -1)
        XCTAssertEqual(mixer.lineFaderText(.b), "95\u{00A0}%")
        mixer.nudgeCrossfader(steps: 1)
        XCTAssertEqual(mixer.crossfaderAccessibilityValue, "55\u{00A0}%")
        mixer.moveCrossfaderToA()
        XCTAssertEqual(mixer.crossfaderAccessibilityValue, "butée gauche, voie A")
        mixer.nudgeCrossfaderCurve(steps: -4)
        XCTAssertEqual(mixer.curveAccessibilityValue, "60\u{00A0}%")
        XCTAssertEqual(AdjustableFocus.steps(for: .up, shift: false), 1)
        XCTAssertEqual(AdjustableFocus.steps(for: .left, shift: true), -10)
    }

    // AC1 — UX §8.6 : son chargé, SET CUE, START sur platine vide, platine vidée.
    func testDeckAnnouncements_UX8_6() async {
        let deck = DeckViewModel(deck: .a, engine: engine, waveformCache: WaveformCache { _, _ in nil })
        let clip = PreviewDeckIntents.syntheticClip(title: "voix_funk.wav", duration: 225)
        deck.loadedClip = clip
        deck.apply(DeckSnapshot(clipID: clip.id, durationSeconds: 225))
        XCTAssertEqual(deck.eventAnnouncement,
                       "Platine A\u{00A0}: «\u{00A0}voix_funk.wav\u{00A0}» chargé, 3 minutes 45 secondes.")
        XCTAssertEqual(deck.eventAnnouncementCount, 1)
        deck.apply(DeckSnapshot(clipID: clip.id, durationSeconds: 225, positionSeconds: 1))
        XCTAssertEqual(deck.eventAnnouncementCount, 1, "announced once")
        deck.apply(DeckSnapshot.initial)
        XCTAssertEqual(deck.eventAnnouncement, "Platine A vidée.")
        XCTAssertEqual(deck.eventAnnouncementCount, 2)
        XCTAssertEqual(deck.emptyStartAnnouncement,
                       "Aucun son chargé sur la platine A. Importez un fichier ou chargez la démo.")
        XCTAssertEqual(AccessibilityText.setCue(at: 12.34), "Point CUE mémorisé à 12,3 secondes")
    }
}
