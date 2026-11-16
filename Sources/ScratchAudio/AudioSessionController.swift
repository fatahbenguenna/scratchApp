#if os(iOS)
import AVFoundation
import Foundation
import ScratchCore

/// Session audio iOS/iPadOS (SF-16, SF-18, SF-81, PO-09 ; PRD 2.1, 2.3 ; architecture §7.3).
///
/// Story 2.1 :
/// - catégorie `.playback`, sans mélange avec les autres apps ;
/// - fréquence préférée de 48 kHz et tampon préféré de 256 trames (≈ 5,3 ms) ;
/// - activation au démarrage de l'hôte ;
/// - nom de la route de sortie (UX §5.17) et valeurs obtenues (tampon, fréquence, latence).
///
/// Story 2.3 (T2) : les notifications d'interruption, de changement de route
/// (`AVAudioSession.routeChangeReasonKey`, `.oldDeviceUnavailable`) et de réinitialisation des services
/// média sont traduites en `AudioSystemEvent` (`AudioSessionEvents`) et transmises sur le fil principal,
/// entre `startObserving()` et `stopObserving()`.
@MainActor
public final class AudioSessionController {
    /// Appelé sur le fil principal pour chaque événement du système audio (story 2.3).
    public var onEvent: ((AudioSystemEvent) -> Void)?

    private var observers: [any NSObjectProtocol] = []

    public init() {
        assert(AVAudioSession.InterruptionType.began.rawValue == AudioSessionEvents.interruptionBegan
            && AVAudioSession.InterruptionType.ended.rawValue == AudioSessionEvents.interruptionEnded
            && AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue == AudioSessionEvents.oldDeviceUnavailable
            && AVAudioSession.RouteChangeReason.categoryChange.rawValue == AudioSessionEvents.categoryChange,
            "AudioSessionEvents constants must match the SDK raw values")
    }

    /// Écoute les notifications de la session. Elles sont reçues sur la file principale et transmises
    /// de façon synchrone : un retrait de casque arrête les moteurs sans attendre (CA 2).
    public func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: session,
                               queue: .main) { [weak self] notification in
                let info = notification.userInfo
                let type = info?[AVAudioSessionInterruptionTypeKey] as? UInt
                let reason = info?[AVAudioSessionInterruptionReasonKey] as? UInt
                let wasSuspended = info?[AudioSessionEvents.wasSuspendedKey] as? Bool
                MainActor.assumeIsolated {
                    self?.forward(AudioSessionEvents.event(interruptionType: type, reason: reason,
                                                           wasSuspended: wasSuspended))
                }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session,
                               queue: .main) { [weak self] notification in
                let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                MainActor.assumeIsolated { self?.forward(AudioSessionEvents.event(routeChangeReason: reason)) }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session,
                               queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.forward(.mediaServicesReset) }
            },
        ]
    }

    /// Cesse d'écouter les notifications de la session.
    public func stopObserving() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
    }

    private func forward(_ event: AudioSystemEvent?) {
        if let event { onEvent?(event) }
    }

    /// Configure et active la session : lecture, non mixable, 48 kHz et 256 trames préférés.
    public func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try? session.setPreferredSampleRate(48_000)
        try? session.setPreferredIOBufferDuration(Double(TurntableConstants.preferredBufferFrames) / 48_000)
        try session.setActive(true)
    }

    /// Désactive la session (passage en arrière-plan).
    public func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    /// Nom de la sortie courante (« Haut-parleur », « Casque », « AirPods Pro », « MPC (USB) »…).
    public var currentOutputName: String {
        guard let port = AVAudioSession.sharedInstance().currentRoute.outputs.first else { return "Sortie audio" }
        return OutputNaming.displayName(kind: Self.kind(of: port.portType), systemName: port.portName)
    }

    /// Fréquence matérielle obtenue.
    var sampleRate: Double { AVAudioSession.sharedInstance().sampleRate }

    /// Tampon obtenu, en trames.
    var bufferFrames: Int {
        let session = AVAudioSession.sharedInstance()
        return Int((session.ioBufferDuration * session.sampleRate).rounded())
    }

    /// Latence de sortie annoncée, en secondes.
    var outputLatency: Double { AVAudioSession.sharedInstance().outputLatency }

    static func kind(of port: AVAudioSession.Port) -> OutputPortKind {
        switch port {
        case .builtInSpeaker, .builtInReceiver: return .builtInSpeaker
        case .headphones: return .headphones
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: return .bluetooth
        case .usbAudio: return .usb
        case .HDMI: return .hdmi
        case .airPlay: return .airPlay
        default: return .other
        }
    }
}
#endif
