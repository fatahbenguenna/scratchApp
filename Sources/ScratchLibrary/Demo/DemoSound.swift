import ScratchCore

/// Son de démonstration intégré, généré par l'app (SF-76, E-08, PO-14 ; PRD 3.3).
///
/// **Squelette (story 3.3, Hugo) : clip silencieux de `duration` secondes.** À implémenter : un
/// générateur procédural **déterministe** en Swift pur (mêmes échantillons à chaque appel), stéréo,
/// 48 kHz, 6 à 10 s, attaque franche à 0 s (« stab ») puis voix synthétique « ahh », crête ≤ −1 dBFS,
/// généré en 250 ms au plus, sans ressource soumise à licence. Réutilisé par le self-test (2.4).
/// Il ne se charge jamais automatiquement (RM-01).
public enum DemoSound {
    /// Titre affiché dans la bibliothèque et sur la platine.
    public static let title = "Son de démonstration"

    /// Durée du son de démonstration, en secondes.
    public static let duration: Double = 8.0

    /// Fréquence du clip généré.
    public static let sampleRate: Double = 48_000

    /// Génère le clip. À appeler hors du fil principal si possible, jamais sur le fil audio.
    public static func makeClip() -> AudioClip {
        let frameCount = Int((duration * sampleRate).rounded())
        return AudioClip(title: title, sampleRate: sampleRate, frameCount: frameCount) { _, _ in }
    }
}
