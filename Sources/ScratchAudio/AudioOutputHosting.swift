/// Hôte de la sortie audio vu par l'`AppModel` (architecture §5.3).
///
/// Implémentation : `AudioEngineHost` (AVAudioEngine). Un double de test ou un hôte simulé
/// (aperçus SwiftUI) peut le remplacer. Fil principal uniquement.
@MainActor
public protocol AudioOutputHosting: AnyObject {
    /// État observable de la sortie (SF-82).
    var status: AudioOutputStatus { get }

    /// `true` dès qu'un fil audio peut appeler `ScratchEngine.render`, jusqu'au retour de `stop()`.
    /// Tant que c'est `false`, l'`AppModel` peut appeler `ScratchEngine.pump()`.
    var isRenderingAudio: Bool { get }

    /// Démarre la sortie. Ne lève pas d'erreur : un échec passe à `.unavailable` et l'hôte réessaie.
    func start()

    /// Arrête la sortie (synchrone : plus aucun rendu après le retour).
    func stop()

    /// iOS : passage en arrière-plan → `stopAllMotors`, sortie coupée, positions conservées (SF-81).
    func suspendForBackground()

    /// iOS : retour au premier plan → la sortie redémarre, jamais les moteurs (RM-10).
    func resumeFromBackground()
}
