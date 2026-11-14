import ScratchCore
import XCTest
@testable import ScratchUI

/// Table de mixage (story 4.2) : commandes, libellés, lettres, repères, SAT, badge, saisie du
/// crossfader, valeurs VoiceOver.
@MainActor
final class MixerViewModelTests: XCTestCase {
    // AC1, AC6 — SF-65 : chaque position part vers le moteur à l'appel, bornée.
    func testFaderAndCrossfaderSendCommands_SF65() async {
        let engine = RecordingEngine()
        let mixer = MixerViewModel(engine: engine)
        XCTAssertEqual(mixer.lineFaders, DeckPair(repeating: 1), "100 % by default")
        XCTAssertEqual(mixer.crossfader, 0.5, "centered by default")
        mixer.setLineFader(.a, 0.35)
        mixer.setCrossfader(0)
        mixer.setCrossfader(1.4)
        XCTAssertEqual(engine.sentCommands, [.lineFader(.a, 0.35), .crossfader(0), .crossfader(1)])
        XCTAssertEqual(mixer.lineFaderText(.a), "35\u{00A0}%")
    }

    // AC1 — UX §5.12 : saisie relative dans la zone du bouton, sous le doigt ailleurs.
    func testCrossfaderGripIsRelativeOnTheKnobAndJumpsElsewhere() async {
        var grip = CrossfaderGrip(course: 200)
        XCTAssertEqual(grip.begin(at: 10, value: 0), 0, "10 pt off the knob: no jump, a closed channel stays closed")
        XCTAssertEqual(grip.position(at: 60), 0.25, accuracy: 1e-12, "then follows the finger relatively")
        XCTAssertEqual(grip.begin(at: 150, value: 0), 0.75, accuracy: 1e-12, "elsewhere: the knob jumps under the finger")
        XCTAssertEqual(grip.position(at: 400), 1, "bounded at the stop")
        XCTAssertEqual(grip.position(at: -30), 0)
    }

    // AC2 — SF-66, SF-67, D-02 : libellés de courbe, lettres échangées par le hamster, repères.
    func testCurveLabelsAndHamsterLetters_SF66_SF67() async {
        let mixer = MixerViewModel(engine: RecordingEngine())
        XCTAssertEqual(mixer.curveText, "Coupure franche", "hard cut by default")
        XCTAssertEqual(mixer.cutInWidth ?? 0, 0.03, accuracy: 1e-12, "cut-in marks at 3 % of the stops")
        mixer.setCrossfaderCurve(0.6)
        XCTAssertEqual(mixer.curveText, "60\u{00A0}%")
        XCTAssertNil(mixer.cutInWidth, "w > 0.2: no marks")
        mixer.setCrossfaderCurve(0)
        XCTAssertEqual(mixer.curveText, "Douce")
        XCTAssertFalse(mixer.hamster, "off by default")
        XCTAssertEqual([mixer.leftDeck, mixer.rightDeck], [.a, .b])
        mixer.setCrossfader(0.2)
        mixer.setHamster(true)
        XCTAssertEqual([mixer.leftDeck, mixer.rightDeck], [.b, .a], "letters swap")
        XCTAssertEqual(mixer.crossfader, 0.2, "the knob does not move")
    }

    // AC7 — SF-83, UX §5.12, §11.2.
    func testCrossfaderAccessibilityValues_SF83() async {
        let mixer = MixerViewModel(engine: RecordingEngine())
        XCTAssertEqual(mixer.crossfaderAccessibilityValue, "50\u{00A0}%, centre")
        mixer.setCrossfader(0)
        XCTAssertEqual(mixer.crossfaderAccessibilityValue, "butée gauche, voie A")
        mixer.setHamster(true)
        XCTAssertEqual(mixer.crossfaderAccessibilityValue, "butée gauche, voie B")
        mixer.setCrossfader(1)
        XCTAssertEqual(mixer.crossfaderAccessibilityValue, "butée droite, voie A")
        mixer.setCrossfader(0.3)
        XCTAssertEqual(mixer.crossfaderAccessibilityValue, "30\u{00A0}%")
        mixer.nudgeCrossfader(steps: 1)
        XCTAssertEqual(mixer.crossfader, 0.35, accuracy: 1e-12, "adjustable by 5 % steps")
    }

    // AC3 — D-13, 6.8 : limiteur dès 1 dB, écrêtage prioritaire, maintien 1 s.
    func testSaturationStates_D13() async {
        var sat = SaturationState()
        var mixer = MixerSnapshot.initial
        sat.update(mixer, at: 0)
        XCTAssertEqual(sat.level, .none)
        XCTAssertEqual(sat.accessibilityValue, "aucune")
        mixer.limiterReduction = 0.9
        sat.update(mixer, at: 0.1)
        XCTAssertEqual(sat.level, .none, "below 1 dB")
        mixer.limiterReduction = 1.0
        sat.update(mixer, at: 0.2)
        XCTAssertEqual(sat.accessibilityValue, "limiteur actif")
        mixer.outputPeak = 1.0
        sat.update(mixer, at: 0.3)
        XCTAssertEqual(sat.level, .clipping)
        mixer = .initial
        sat.update(mixer, at: 1.29)
        XCTAssertEqual(sat.level, .clipping, "held for 1 s")
        sat.update(mixer, at: 1.3)
        XCTAssertEqual(sat.level, .none)
    }

    // AC4 — SF-16, SF-82, D-35 : libellés et icônes du badge.
    func testOutputBadgeLabels_SF16_SF82() async {
        func running(_ name: String) -> AudioOutputStatus {
            .running(AudioOutputInfo(name: name, sampleRate: 48_000, bufferFrames: 256, outputLatency: 0.005))
        }
        XCTAssertEqual(OutputBadge.label(for: running("Haut-parleur")), "Haut-parleur")
        XCTAssertEqual(OutputBadge.symbol(for: running("Haut-parleur")), "speaker.wave.2")
        XCTAssertEqual(OutputBadge.symbol(for: running("MPC Sample (USB)")), "cable.connector")
        XCTAssertEqual(OutputBadge.symbol(for: running("AirPods Pro")), "headphones")
        XCTAssertEqual(OutputBadge.symbol(for: running("Salon (AirPlay)")), "airplayaudio")
        let unavailable = AudioOutputStatus.unavailable(reason: "no device")
        XCTAssertEqual(OutputBadge.label(for: unavailable), "Sortie audio indisponible")
        XCTAssertEqual(OutputBadge.symbol(for: unavailable), "speaker.slash")
        XCTAssertTrue(OutputBadge.isUnavailable(unavailable))
        XCTAssertFalse(OutputBadge.isUnavailable(.starting))
        XCTAssertEqual(OutputBadge.label(for: .starting), "Démarrage de la sortie audio\u{2026}")
        XCTAssertEqual(OutputBadge.label(for: .stopped), "Sortie audio arrêtée")
    }
}
