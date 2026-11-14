/// Son de démonstration intégré, généré par l'app (SF-76, E-08, PO-14).
///
/// **Squelette (story EP1, James) : clip silencieux de `duration` secondes.** À implémenter : un
/// générateur **déterministe** (mêmes échantillons à chaque appel, pour les tests et le self-test),
/// avec une attaque franche (« stab ») propice au scratch, sans ressource soumise à licence.
/// Il ne se charge jamais automatiquement (RM-01).
public enum DemoSound {
    /// Titre affiché dans la bibliothèque et sur la platine.
    public static let title = "Son de démonstration"

    /// Durée du son de démonstration, en secondes.
    public static let duration: Double = 8.0

    /// Fréquence native du clip généré.
    public static let sampleRate: Double = 48_000

    /// Génère le clip. Coûteux : à appeler hors du fil principal si possible, jamais sur le fil audio.
    public static func makeClip() -> AudioClip {
        let frameCount = Int((duration * sampleRate).rounded())
        return AudioClip(title: title, sampleRate: sampleRate, frameCount: frameCount) { _, _ in }
    }
}
