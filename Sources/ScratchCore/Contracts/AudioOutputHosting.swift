/// Hôte de la sortie audio vu par l'`AppModel` (PRD 2.1 ; architecture §3.3, §5.1, §7.3).
///
/// Implémentation : `AudioEngineHost` (ScratchAudio, AVAudioEngine, stories 2.1 et 2.3). Un double de
/// test ou un hôte simulé (aperçus SwiftUI) peut le remplacer. Fil principal uniquement.
///
/// Tant qu'il est démarré et non suspendu, l'hôte fait **toujours** tourner le rendu du moteur : sur
/// la sortie matérielle, ou, si elle est indisponible, sur son horloge de secours (rendu silencieux
/// au rythme du temps réel, SF-82). Un seul des deux à la fois.
@MainActor
public protocol AudioOutputHosting: AnyObject {
    /// État observable de la sortie (SF-16, SF-82).
    var status: AudioOutputStatus { get }

    /// `true` dès qu'un fil (sortie matérielle ou horloge de secours) peut appeler
    /// `ScratchEngine.render`, jusqu'au retour de `stop()` ou de `suspend()`. Tant que c'est `false`,
    /// l'`AppModel` peut appeler `ScratchEngine.pump()`.
    var isRenderingAudio: Bool { get }

    /// Démarre la sortie. Ne lève pas d'erreur : un échec passe à `.unavailable`, lance l'horloge de
    /// secours et réessaie automatiquement (SF-82).
    func start()

    /// Arrête la sortie et l'horloge de secours (synchrone : plus aucun rendu après le retour).
    func stop()

    /// iOS : arrière-plan. `stopAllMotors`, sortie coupée, horloge de secours arrêtée, positions
    /// conservées (SF-81, RM-56).
    func suspend()

    /// iOS : retour au premier plan. La sortie (ou l'horloge de secours) redémarre, jamais les
    /// moteurs (RM-10).
    func resume()
}
