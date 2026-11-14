/// Événement du système audio, traduit des notifications AVAudioSession (iOS),
/// AVAudioEngineConfigurationChange (iOS, macOS) et NSWorkspace (veille, macOS). Politique :
/// architecture §7.3 (PRD 2.3, arbitrage IC-04).
public enum AudioSystemEvent: Equatable, Sendable {
    /// Début d'interruption (appel, Siri, alarme) → `stopAllMotors` (RM-56, SF-18).
    case interruptionBegan
    /// Fin d'interruption : la sortie redémarre, **jamais** les moteurs (RM-10).
    case interruptionEnded
    /// Changement de route. `previousDeviceUnavailable` : le périphérique utilisé a disparu
    /// (casque débranché, interface USB retirée) → `stopAllMotors` (6.5, arbitrage IC-04).
    case routeChanged(previousDeviceUnavailable: Bool)
    /// Configuration matérielle modifiée (fréquence, périphérique par défaut) : l'hôte reconstruit
    /// le graphe et envoie `outputSampleRate` ; sur Mac, sans STOP si l'ancien périphérique existe
    /// encore (arbitrage IC-04).
    case configurationChanged
    /// Services média réinitialisés (iOS) : reconstruction complète, moteurs à STOP.
    case mediaServicesReset
    /// Mise en veille du Mac → `stopAllMotors` (0.3, PRD 2.3 critère 5).
    case systemWillSleep
    /// Sortie de veille : la sortie redémarre, jamais les moteurs (RM-10).
    case systemDidWake
}
