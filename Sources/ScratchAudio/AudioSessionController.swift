#if os(iOS)
import Foundation
import ScratchCore

/// Session audio iOS/iPadOS (SF-16, SF-18, SF-81, PO-09 ; PRD 2.1, 2.3 ; architecture §7.3).
///
/// **Squelette (story 2.3, James) : n'active rien.** À implémenter :
/// - catégorie `.playback`, sans mélange avec les autres apps, tampon préféré 5,3 ms ;
/// - notifications d'interruption, de changement de route (`oldDeviceUnavailable`) et de
///   réinitialisation des services média, traduites en `AudioSystemEvent` sur le fil principal ;
/// - nom de la route de sortie courante.
@MainActor
public final class AudioSessionController {
    /// Appelé sur le fil principal pour chaque événement du système audio.
    public var onEvent: ((AudioSystemEvent) -> Void)?

    public init() {}

    /// Configure et active la session.
    public func activate() throws {}

    /// Désactive la session (passage en arrière-plan).
    public func deactivate() {}

    /// Nom de la sortie courante (« Haut-parleur », « Casque »…).
    public var currentOutputName: String { "" }
}
#endif
