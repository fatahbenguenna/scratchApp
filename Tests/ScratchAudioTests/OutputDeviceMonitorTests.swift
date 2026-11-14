#if os(macOS)
import AppKit
import CoreAudio
import XCTest
import ScratchCore
@testable import ScratchAudio

/// Surveillance de la sortie sur macOS (story 2.3 ; CA 3 à 5). Les runners de CI n'ont pas toujours
/// de périphérique audio : les événements sont simulés (notifications de veille, rafale de
/// notifications Core Audio).
@MainActor
final class OutputDeviceMonitorTests: XCTestCase {
    /// CA5 — 0.3, RM-56 : mise en veille et réveil traduits en `systemWillSleep` et `systemDidWake`.
    func testSleepAndWakeAreTranslated() async {
        let monitor = OutputDeviceMonitor()
        var events: [AudioSystemEvent] = []
        monitor.onEvent = { events.append($0) }
        monitor.start()
        defer { monitor.stop() }
        let center = NSWorkspace.shared.notificationCenter
        center.post(name: NSWorkspace.willSleepNotification, object: NSWorkspace.shared)
        center.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
        for _ in 0..<50 where events.count < 2 { try? await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(events, [.systemWillSleep, .systemDidWake])
    }

    /// CA3, CA4 : une rafale de notifications Core Audio (défaut et liste des périphériques) donne un
    /// seul `configurationChanged`.
    func testDeviceNotificationsAreCoalesced() async {
        let monitor = OutputDeviceMonitor()
        var events: [AudioSystemEvent] = []
        monitor.onEvent = { events.append($0) }
        monitor.deviceConfigurationDidChange()
        monitor.deviceConfigurationDidChange()
        monitor.deviceConfigurationDidChange()
        for _ in 0..<50 where events.isEmpty { try? await Task.sleep(nanoseconds: 10_000_000) }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(events, [.configurationChanged])
        XCTAssertEqual(monitor.defaultOutputDevice, OutputDeviceMonitor.currentDefaultOutputDevice())
    }

    /// Recommandation de la gate (#88) : une rafale plus longue que le délai de regroupement, avec des
    /// notifications plus rapprochées que ce délai, donne un seul événement, parti après la dernière
    /// (délai relancé ; une fenêtre fixe en donnerait deux). Les écarts réels sont mesurés : si le runner
    /// les étire au-delà du délai, la vérification est sautée plutôt que fausse.
    func testLongBurstGivesASingleEvent() async throws {
        let delay = 0.3
        let monitor = OutputDeviceMonitor(coalescingDelay: UInt64(delay * 1e9))
        var eventTimes: [Date] = []
        monitor.onEvent = { _ in eventTimes.append(Date()) }
        var callTimes: [Date] = []
        for index in 0..<3 {
            if index > 0 { try? await Task.sleep(nanoseconds: 200_000_000) }
            callTimes.append(Date())
            monitor.deviceConfigurationDidChange()
        }
        let gaps = zip(callTimes.dropFirst(), callTimes).map { $0.timeIntervalSince($1) }
        let span = callTimes.last!.timeIntervalSince(callTimes.first!)
        for _ in 0..<200 where eventTimes.isEmpty { try? await Task.sleep(nanoseconds: 20_000_000) }
        try? await Task.sleep(nanoseconds: 400_000_000)
        guard gaps.allSatisfy({ $0 < delay }) else {
            throw XCTSkip("runner too loaded: notification gaps \(gaps) exceed the \(delay) s delay")
        }
        XCTAssertGreaterThan(span, delay, "the burst is longer than the delay")
        XCTAssertEqual(eventTimes.count, 1, "a single event for the whole burst")
        if let event = eventTimes.first {
            XCTAssertGreaterThanOrEqual(event.timeIntervalSince(callTimes.last!), delay * 0.9, "sent after the last notification")
        }
    }

    /// CA3 — D-04 : présence du périphérique utilisé (contexte de la politique) ; un identifiant
    /// inconnu n'est pas présent ; sans périphérique utilisé, rien n'est perdu.
    func testDevicePresence_D04() {
        let monitor = OutputDeviceMonitor()
        XCTAssertTrue(monitor.isDeviceInUseStillPresent, "no device in use: nothing lost")
        monitor.deviceInUse = AudioObjectID(987_654)
        XCTAssertFalse(monitor.isDeviceInUseStillPresent, "a removed device is reported gone")
        if let current = OutputDeviceMonitor.currentDefaultOutputDevice() {
            monitor.deviceInUse = current
            XCTAssertTrue(monitor.isDeviceInUseStillPresent)
            XCTAssertTrue(OutputDeviceMonitor.connectedDevices().contains(current))
        }
    }

    /// Démarrer deux fois est sans effet ; après `stop()`, plus aucun événement.
    func testStopRemovesObservers() async {
        let monitor = OutputDeviceMonitor()
        var events: [AudioSystemEvent] = []
        monitor.onEvent = { events.append($0) }
        monitor.start()
        monitor.start()
        XCTAssertTrue(monitor.isMonitoring)
        monitor.stop()
        XCTAssertFalse(monitor.isMonitoring)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: NSWorkspace.shared)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(events, [])
    }
}
#endif
