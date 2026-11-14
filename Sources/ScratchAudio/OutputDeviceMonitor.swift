#if os(macOS)
import AppKit
import CoreAudio
import Foundation
import ScratchCore

/// Surveillance de la sortie audio sur macOS (story 2.3 ; SF-16, RM-56 ; D-04 ; architecture §7.3).
///
/// Traduit en `AudioSystemEvent`, sur le fil principal :
/// - un changement du périphérique de sortie par défaut ou de la liste des périphériques (branchement,
///   retrait d'une interface USB) → `configurationChanged`. Les notifications d'une même rafale sont
///   regroupées en un seul événement : il part `coalescingDelay` (50 ms) après la **dernière** notification
///   (délai relancé à chaque notification). L'hôte demande alors à
///   `isDeviceInUseStillPresent` si le périphérique qu'il utilisait existe encore (contexte de
///   `AudioSystemPolicy`) ;
/// - la mise en veille et le réveil (`NSWorkspace.shared.notificationCenter`) → `systemWillSleep`,
///   `systemDidWake`, transmis **de façon synchrone** pendant la notification : STOP précède la mise en
///   veille.
///
/// La sortie (`AVAudioEngineOutput`) fait passer `AVAudioEngineConfigurationChange` par le même
/// regroupement (`deviceConfigurationDidChange()`) : un changement de périphérique, qui produit les deux
/// sortes de notifications, ne donne qu'un `configurationChanged`. Elle fixe `deviceInUse` à chaque
/// démarrage.
///
/// Le nom, le type de transport et le tampon du périphérique relèvent de `OutputDevice` (story 2.1).
/// `start()` et `stop()` : fil principal ; `stop()` doit être appelé avant de libérer le moniteur.
@MainActor
public final class OutputDeviceMonitor {
    /// Délai de regroupement par défaut des notifications Core Audio d'une même rafale.
    public nonisolated static let defaultCoalescingDelay: UInt64 = 50_000_000 // 50 ms

    /// Délai de regroupement (ns), relancé à chaque notification.
    let coalescingDelay: UInt64

    /// Appelé sur le fil principal pour chaque événement.
    public var onEvent: ((AudioSystemEvent) -> Void)?
    /// Périphérique utilisé par l'hôte, fixé par celui-ci quand la sortie démarre.
    public var deviceInUse: AudioObjectID?
    /// Périphérique de sortie par défaut, à jour après chaque `configurationChanged`.
    public private(set) var defaultOutputDevice: AudioObjectID?
    /// Le moniteur écoute.
    public private(set) var isMonitoring = false

    private var listener: AudioObjectPropertyListenerBlock?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var configurationChangeGeneration = 0

    public init(coalescingDelay: UInt64 = OutputDeviceMonitor.defaultCoalescingDelay) {
        self.coalescingDelay = coalescingDelay
    }

    /// Le périphérique utilisé est toujours connecté (vrai s'il n'y en a pas : rien n'a été perdu).
    public var isDeviceInUseStillPresent: Bool {
        guard let deviceInUse else { return true }
        return Self.isDevicePresent(deviceInUse)
    }

    public func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        defaultOutputDevice = Self.currentDefaultOutputDevice()
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.deviceConfigurationDidChange() }
        }
        listener = block
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        }
        let center = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, AudioSystemEvent)] = [
            (NSWorkspace.willSleepNotification, .systemWillSleep),
            (NSWorkspace.didWakeNotification, .systemDidWake),
        ]
        workspaceObservers = pairs.map { name, event in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Delivered on the main queue: forward synchronously, before the system sleeps.
                MainActor.assumeIsolated { self?.onEvent?(event) }
            }
        }
    }

    public func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        if let listener {
            for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDevices] {
                var address = Self.address(selector)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener)
            }
        }
        listener = nil
        let center = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { center.removeObserver(observer) }
        workspaceObservers = []
    }

    /// Notification Core Audio (ou simulée par les tests) : un seul `configurationChanged` par rafale,
    /// `coalescingDelay` après la dernière notification.
    func deviceConfigurationDidChange() {
        configurationChangeGeneration += 1
        let generation = configurationChangeGeneration
        let delay = coalescingDelay
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, generation == self.configurationChangeGeneration else { return }
            self.defaultOutputDevice = Self.currentDefaultOutputDevice()
            self.onEvent?(.configurationChanged)
        }
    }

    // MARK: Core Audio

    /// Périphérique de sortie par défaut du système, ou `nil` s'il n'y en a pas (runner sans audio). Même
    /// requête que la sortie (`OutputDevice.defaultOutput()`) : l'hôte et le moniteur voient le même
    /// périphérique.
    public nonisolated static func currentDefaultOutputDevice() -> AudioObjectID? {
        OutputDevice.defaultOutput()?.id
    }

    /// Périphériques audio connectés.
    public nonisolated static func connectedDevices() -> [AudioObjectID] {
        var address = Self.address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return Array(devices.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// Le périphérique `device` est toujours connecté.
    public nonisolated static func isDevicePresent(_ device: AudioObjectID) -> Bool {
        connectedDevices().contains(device)
    }

    private nonisolated static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
#endif
