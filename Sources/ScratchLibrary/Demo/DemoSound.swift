import ScratchCore

/// Son de démonstration intégré, généré par l'app (SF-76, E-08, PO-14, D-20 ; PRD 3.3).
///
/// **Synthèse.** Le son est calculé à la demande, en Swift pur, par `DemoSynthesizer` : un « stab »
/// à attaque franche à 0 s (accord de la majeur, partiels en phase, attaque de 0,5 ms), puis une
/// voix synthétique « ahh » (source glottique et trois formants de [a], vibrato) ; un second stab
/// (ré majeur) à 4 s, suivi d'une voix plus aiguë et d'un fondu de fin. Stéréo, 48 kHz, 8 s, crête
/// normalisée par un gain unique juste sous −1 dBFS (0,89).
///
/// **Libre de droits par construction.** Aucun échantillon, enregistrement ni fichier tiers n'est
/// utilisé : tout est produit par des oscillateurs et des filtres. Il n'y a donc aucune licence à
/// mentionner dans l'app (Q19 sans objet).
///
/// **Déterministe.** Deux appels donnent les mêmes échantillons bit à bit, sur toutes les
/// plateformes (opérations IEEE 754 de base seulement, aucun hasard).
///
/// **Usage.** Entrée `LibraryEntry.demo` en tête de la bibliothèque, sans fichier ni suppression
/// possible ; chargée seulement par l'intention « Charger la démo » (6.1), jamais automatiquement
/// (RM-01) ; réutilisée par le self-test (2.4).
public enum DemoSound {
    /// Titre affiché dans la bibliothèque et sur la platine.
    public static let title = "Son de démonstration"

    /// Durée du son de démonstration, en secondes.
    public static let duration: Double = 8.0

    /// Fréquence du clip généré.
    public static let sampleRate: Double = 48_000

    /// Génère le clip (environ 3 Mo, écrits directement dans la mémoire du clip). À appeler hors du
    /// fil principal si possible, jamais sur le fil audio ; l'`AppModel` le met en cache (RM-57).
    public static func makeClip() -> AudioClip {
        let frameCount = Int((duration * sampleRate).rounded())
        return AudioClip(title: title, sampleRate: sampleRate, frameCount: frameCount) { left, right in
            DemoSynthesizer.render(left: left, right: right, sampleRate: sampleRate)
        }
    }
}
