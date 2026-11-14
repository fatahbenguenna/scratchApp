/// Ce que l'UI et l'`AppModel` attendent du moteur (architecture §5.1).
///
/// `ScratchEngine` l'implémente ; `RecordingEngine` en est un double de test qui enregistre les
/// commandes et renvoie un instantané choisi par le test ou l'aperçu SwiftUI.
///
/// Toutes ces méthodes appartiennent au **fil de contrôle** (le fil principal dans l'app) : un seul
/// fil à la fois, jamais le fil audio.
public protocol EngineControlling: AnyObject {
    /// Envoie une commande. Renvoie `false` si la file est pleine (commande perdue, rien n'a changé).
    @discardableResult
    func send(_ command: EngineCommand) -> Bool

    /// Dernier instantané publié par le fil audio.
    func latestSnapshot() -> EngineSnapshot

    /// Libère, sur le fil appelant, les clips remplacés ou déchargés. À appeler à chaque image.
    /// Renvoie le nombre de clips rendus.
    @discardableResult
    func drainReleasedClips() -> Int

    /// Applique les commandes en attente et publie un instantané **sans produire d'audio ni
    /// avancer le temps**. À n'appeler que lorsque aucun fil audio n'appelle le rendu (hôte arrêté,
    /// sortie indisponible, tests, aperçus) : l'interface reste utilisable (SF-82).
    func pump()
}
