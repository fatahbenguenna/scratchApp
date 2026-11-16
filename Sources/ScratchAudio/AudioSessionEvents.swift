import ScratchCore

/// Traduction des notifications `AVAudioSession` (iOS) en `AudioSystemEvent` (story 2.3 T2 ;
/// architecture §7.3), en logique pure : `AudioSessionController` lui passe les valeurs brutes des
/// notifications, et les tests la vérifient sur macOS, où `AVAudioSession` n'existe pas.
///
/// Les constantes reprennent les valeurs brutes du SDK ; `AudioSessionController` vérifie leur
/// concordance (assertion en Debug), sauf pour le motif `appWasSuspended` et la clé `wasSuspended`,
/// obsolètes dans le SDK : les nommer produirait un avertissement.
enum AudioSessionEvents {
    /// `AVAudioSession.InterruptionType.began`.
    static let interruptionBegan: UInt = 1
    /// `AVAudioSession.InterruptionType.ended`.
    static let interruptionEnded: UInt = 0
    /// `AVAudioSession.InterruptionReason.appWasSuspended` (iOS 14.5, obsolète depuis iOS 16) : le système a
    /// désactivé la session pendant que l'app était suspendue.
    static let appWasSuspended: UInt = 1
    /// Valeur de la clé `AVAudioSessionInterruptionWasSuspendedKey` (avant iOS 14.5, obsolète) : même sens.
    static let wasSuspendedKey = "AVAudioSessionInterruptionWasSuspendedKey"
    /// `AVAudioSession.RouteChangeReason.oldDeviceUnavailable` : casque débranché, interface retirée.
    static let oldDeviceUnavailable: UInt = 2
    /// `AVAudioSession.RouteChangeReason.categoryChange` : provoqué par l'activation de la session
    /// par l'hôte lui-même.
    static let categoryChange: UInt = 3

    /// `AVAudioSession.interruptionNotification` → début ou fin d'interruption (CA 1).
    ///
    /// Un début d'interruption « app suspendue » (motif `appWasSuspended`, ou `wasSuspended` vrai) est
    /// ignoré (#121). iOS l'envoie avec retard, quand l'app tourne de nouveau, et sans fin d'interruption :
    /// aucune interruption n'est en cours. Le prendre pour une vraie interruption laisserait l'hôte muet
    /// après `resume()`.
    static func event(interruptionType: UInt?, reason: UInt? = nil, wasSuspended: Bool? = nil) -> AudioSystemEvent? {
        guard let interruptionType else { return nil }
        switch interruptionType {
        case interruptionBegan:
            if reason == appWasSuspended || wasSuspended == true { return nil }
            return .interruptionBegan
        case interruptionEnded:
            return .interruptionEnded
        default:
            return nil
        }
    }

    /// `AVAudioSession.routeChangeNotification` → changement de route (CA 2 à 4, 7). Le changement de
    /// catégorie est ignoré : l'hôte le provoque à chaque activation de la session, et le prendre pour
    /// un changement de route relancerait un essai en boucle quand la sortie est indisponible.
    static func event(routeChangeReason: UInt?) -> AudioSystemEvent? {
        switch routeChangeReason ?? 0 {
        case oldDeviceUnavailable: return .routeChanged(previousDeviceUnavailable: true)
        case categoryChange: return nil
        default: return .routeChanged(previousDeviceUnavailable: false)
        }
    }
}
