/// Vue d'un clip pour le fil audio : identifiant, fréquence et pointeurs vers les échantillons, sans
/// référence à l'objet `AudioClip` (story 1.5 ; architecture §6.1 règles 1 et 4).
///
/// Construite sur le fil de contrôle par `send(.load)` et transportée par la file de commandes :
/// le rendu ne touche jamais l'objet, donc ne fait aucun comptage de références, même en débogage.
/// Type trivial (`_isPOD`). Valide tant que le moteur retient le clip, c'est-à-dire jusqu'à ce que
/// celui-ci revienne au fil de contrôle par la file de retour.
struct ClipView {
    let id: AudioClip.ID
    let sampleRate: Double
    let left: UnsafeBufferPointer<Float>
    let right: UnsafeBufferPointer<Float>

    init(_ clip: AudioClip) {
        id = clip.id
        sampleRate = clip.sampleRate
        left = clip.left
        right = clip.right
    }

    var frameCount: Int { left.count }

    /// Durée en secondes.
    var duration: Double { Double(left.count) / sampleRate }
}
