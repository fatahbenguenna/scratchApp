import XCTest
import ScratchCore
@testable import ScratchAudio

/// Politique de l'hôte audio (story 2.3 CA 9 ; architecture §7.3 ; D-04, D-35) : événements simulés
/// pour iOS et macOS.
final class AudioSystemPolicyTests: XCTestCase {
    private let iOS = AudioHostContext(platform: .iOS)
    private let macOS = AudioHostContext(platform: .macOS)

    private func actions(_ event: AudioSystemEvent, _ context: AudioHostContext) -> [AudioHostAction] {
        AudioSystemPolicy.actions(for: event, context: context)
    }

    /// Aucune action ne démarre jamais un moteur (RM-10) : la politique n'a pas d'action « moteur à
    /// START », et la reprise est toujours manuelle.
    private let allEvents: [AudioSystemEvent] = [
        .interruptionBegan, .interruptionEnded, .routeChanged(previousDeviceUnavailable: true),
        .routeChanged(previousDeviceUnavailable: false), .configurationChanged, .mediaServicesReset,
        .systemWillSleep, .systemDidWake,
    ]

    /// CA1 — SF-18, RM-56, RM-10 (scénario « Interruption avec un disque tenu ») : début → STOP des
    /// moteurs, sortie arrêtée, horloge de secours, avis ; fin → la sortie redémarre, rien d'autre.
    func testInterruptionStopsMotorsAndEndRestartsOutputOnly_SF18() {
        XCTAssertEqual(actions(.interruptionBegan, iOS),
                       [.stopAllMotors, .stopOutput, .startFallbackClock, .notify(.interrupted)])
        var interrupted = iOS
        interrupted.isInterrupted = true
        XCTAssertEqual(actions(.interruptionEnded, interrupted), [.rebuildGraph, .startOutput], "the output only, never the motors")
    }

    /// CA2, CA3 — D-04 (6.5 « Débrancher le casque », « Perdre le périphérique audio ») : la sortie
    /// est arrêtée et STOP appliqué (`pump`) **avant** que la nouvelle route ne rende, puis la sortie
    /// suit la nouvelle route.
    func testHeadphonesUnpluggedStopsBeforeTheSpeakerPlays_D04() {
        let result = actions(.routeChanged(previousDeviceUnavailable: true), iOS)
        XCTAssertEqual(result, [.stopOutput, .stopAllMotors, .applyPendingCommands, .notify(.outputDisconnected), .startOutput])
        let stop = result.firstIndex(of: .applyPendingCommands) ?? .max
        let start = result.firstIndex(of: .startOutput) ?? .min
        XCTAssertLessThan(stop, start, "STOP is applied before any output on the speaker")
    }

    /// CA4 — iOS : un changement de route sans disparition ne change pas les moteurs.
    func testOtherRouteChangeKeepsMotors() {
        XCTAssertEqual(actions(.routeChanged(previousDeviceUnavailable: false), iOS), [.refreshOutputName])
    }

    /// CA3, CA4 — D-04 (scénario « Changement de configuration sur Mac ») : ancien périphérique encore
    /// là → reconstruction et redémarrage, moteurs inchangés ; périphérique utilisé disparu → STOP.
    func testMacConfigurationChange_D04() {
        XCTAssertEqual(actions(.configurationChanged, macOS), [.rebuildGraph, .startOutput], "built-in output still there")
        var gone = macOS
        gone.usedDeviceStillPresent = false
        XCTAssertEqual(actions(.configurationChanged, gone),
                       [.stopOutput, .stopAllMotors, .applyPendingCommands, .notify(.outputDisconnected), .rebuildGraph, .startOutput],
                       "USB interface removed")
        XCTAssertEqual(actions(.configurationChanged, iOS), [.rebuildGraph, .startOutput], "iOS: new sample rate, motors kept")
    }

    /// Services média réinitialisés (iOS) : reconstruction complète de la session et du graphe, STOP.
    func testMediaServicesResetRebuildsEverything() {
        XCTAssertEqual(actions(.mediaServicesReset, iOS),
                       [.stopOutput, .stopAllMotors, .applyPendingCommands, .resetSession, .rebuildGraph, .startOutput])
    }

    /// CA5 — 0.3, RM-56 (6.5 « Mettre le Mac en veille ») : veille → STOP ; réveil → sortie relancée.
    func testSleepStopsMotorsAndWakeRestartsOutput() {
        XCTAssertEqual(actions(.systemWillSleep, macOS), [.stopOutput, .stopAllMotors, .applyPendingCommands])
        XCTAssertEqual(actions(.systemDidWake, macOS), [.startOutput])
    }

    /// CA6 — SF-82, D-35 : sortie indisponible → horloge de secours et avis à la transition ; nouvel
    /// essai à chaque tic de 2 s et à chaque changement de route ou de configuration ; avis de
    /// sortie retrouvée avec son nom ; jamais de `pump` pendant que l'horloge de secours rend.
    func testUnavailableOutputRetries_SF82() {
        XCTAssertEqual(AudioSystemPolicy.retryInterval, 2)
        XCTAssertEqual(AudioSystemPolicy.actionsAfterStart(succeeded: false, outputName: "", context: macOS),
                       [.startFallbackClock, .notify(.outputUnavailable)])
        var unavailable = macOS
        unavailable.isOutputUnavailable = true
        XCTAssertEqual(AudioSystemPolicy.actionsAfterStart(succeeded: false, outputName: "", context: unavailable),
                       [.startFallbackClock], "no repeated banner on each failed retry")
        XCTAssertEqual(AudioSystemPolicy.actionsOnRetryTick(context: unavailable), [.startOutput])
        XCTAssertEqual(AudioSystemPolicy.actionsOnRetryTick(context: macOS), [], "no retry while running")
        XCTAssertEqual(actions(.routeChanged(previousDeviceUnavailable: false), unavailable), [.startOutput])
        XCTAssertEqual(actions(.configurationChanged, unavailable), [.rebuildGraph, .startOutput])
        XCTAssertEqual(actions(.routeChanged(previousDeviceUnavailable: true), unavailable),
                       [.stopAllMotors, .notify(.outputDisconnected), .startOutput])
        XCTAssertEqual(AudioSystemPolicy.actionsAfterStart(succeeded: true, outputName: "MPC Sample (USB)", context: unavailable),
                       [.refreshOutputName, .notify(.outputAvailable(name: "MPC Sample (USB)"))])
        XCTAssertEqual(AudioSystemPolicy.actionsAfterStart(succeeded: true, outputName: "Haut-parleur", context: macOS),
                       [.refreshOutputName], "no banner for an ordinary restart")
        for event in allEvents {
            XCTAssertFalse(actions(event, unavailable).contains(.applyPendingCommands),
                           "\(event): never pump while the fallback clock renders")
        }
    }

    /// SF-81 : suspendu (arrière-plan iOS), seule la sécurité des moteurs s'applique ; aucune sortie
    /// ne redémarre avant `resume()`.
    func testSuspendedHostOnlyStopsMotors_SF81() {
        var suspended = iOS
        suspended.isSuspended = true
        XCTAssertEqual(actions(.interruptionBegan, suspended), [.stopAllMotors])
        XCTAssertEqual(actions(.interruptionEnded, suspended), [])
        XCTAssertEqual(actions(.routeChanged(previousDeviceUnavailable: true), suspended), [.stopAllMotors])
        XCTAssertEqual(AudioSystemPolicy.actionsOnRetryTick(context: suspended), [])
        XCTAssertEqual(AudioSystemPolicy.actionsAfterStart(succeeded: true, outputName: "x", context: suspended), [])
        for event in allEvents {
            XCTAssertTrue(actions(event, suspended).allSatisfy { $0 == .stopAllMotors }, "\(event)")
        }
    }

    /// #96 : pendant une interruption iOS, l'horloge de secours rend : aucun `pump()` ; aucun
    /// redémarrage de la sortie ni nouvel essai avant `interruptionEnded` ; STOP sur une perte de
    /// sortie ou une réinitialisation ; aucun avis « indisponible » pendant l'appel.
    func testEventsDuringAnInterruption_96() {
        for unavailable in [false, true] {
            var interrupted = iOS
            interrupted.isInterrupted = true
            interrupted.isOutputUnavailable = unavailable
            XCTAssertTrue(interrupted.isFallbackRendering)
            for event in allEvents {
                let result = actions(event, interrupted)
                XCTAssertFalse(result.contains(.applyPendingCommands), "\(event): never pump while the fallback clock renders")
                XCTAssertEqual(result.contains(.startOutput), event == .interruptionEnded, "\(event): output restarts only at the end")
                XCTAssertFalse(result.contains(.notify(.outputUnavailable)), "\(event)")
                XCTAssertFalse(result.contains(.stopOutput), "\(event): the output is already stopped")
            }
            XCTAssertEqual(actions(.routeChanged(previousDeviceUnavailable: true), interrupted),
                           [.stopAllMotors, .notify(.outputDisconnected)], "headphones unplugged during a call")
            XCTAssertEqual(actions(.mediaServicesReset, interrupted), [.stopAllMotors, .resetSession, .rebuildGraph])
            XCTAssertEqual(actions(.configurationChanged, interrupted), [])
            XCTAssertEqual(actions(.interruptionEnded, interrupted), [.rebuildGraph, .startOutput],
                           "rebuilt on the current route (it may have changed during the call)")
            XCTAssertEqual(AudioSystemPolicy.actionsOnRetryTick(context: interrupted), [], "no retry during a call")
            XCTAssertEqual(AudioSystemPolicy.actionsAfterStart(succeeded: false, outputName: "", context: interrupted), [])
        }
    }

    /// Règle unique (§7.3) : STOP exactement pour les pertes de sortie, interruptions, réinitialisations
    /// et veilles, sur les deux plateformes ; la sortie redémarre toujours après un arrêt (sauf veille
    /// et suspension), et aucune action ne démarre un moteur.
    func testStopRuleIsConsistentAcrossPlatforms() {
        let stopping: Set<String> = ["interruptionBegan", "routeChanged(previousDeviceUnavailable: true)",
                                     "mediaServicesReset", "systemWillSleep"]
        for context in [iOS, macOS] {
            for event in allEvents {
                let result = actions(event, context)
                XCTAssertEqual(result.contains(.stopAllMotors), stopping.contains("\(event)"), "\(event) on \(context.platform)")
                if result.contains(.stopOutput), event != .systemWillSleep, event != .interruptionBegan {
                    XCTAssertTrue(result.contains(.startOutput), "\(event): the output comes back")
                }
            }
        }
    }

    /// CA8 — UX §8.5 : textes des bandeaux.
    func testNoticeMessages_UX8_5() {
        XCTAssertEqual(AudioHostNotice.interrupted.message, "Lecture interrompue par le système. Appuyez sur START pour reprendre.")
        XCTAssertEqual(AudioHostNotice.outputDisconnected.message, "Sortie audio déconnectée : les platines sont arrêtées.")
        XCTAssertEqual(AudioHostNotice.outputUnavailable.message, "Sortie audio indisponible. ScratchApp réessaiera automatiquement.")
        XCTAssertEqual(AudioHostNotice.outputAvailable(name: "Haut-parleur").message, "Sortie audio disponible : Haut-parleur.")
    }
}
