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
/// Les notifications d'interruption, de changement de route et de réinitialisation des services
/// média, traduites en `AudioSystemEvent`, relèvent de la story 2.3.
@MainActor
public final class AudioSessionController {
    /// Appelé sur le fil principal pour chaque événement du système audio (story 2.3).
    public var onEvent: ((AudioSystemEvent) -> Void)?

    public init() {}

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
