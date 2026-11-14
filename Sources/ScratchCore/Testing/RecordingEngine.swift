/// Double de test d'`EngineControlling` : enregistre les commandes et renvoie l'instantané choisi
/// par le test ou l'aperçu. Pour développer et tester l'UI et l'`AppModel` sans moteur réel.
///
/// Fil de contrôle uniquement (non thread-safe).
public final class RecordingEngine: EngineControlling {
    /// Commandes reçues, dans l'ordre.
    public private(set) var sentCommands: [EngineCommand] = []
    /// Instantané renvoyé par `latestSnapshot()`.
    public var snapshot: EngineSnapshot
    /// Si `false`, `send` refuse les commandes (simule une file pleine).
    public var acceptsCommands = true
    public private(set) var drainCount = 0
    public private(set) var pumpCount = 0

    public init(snapshot: EngineSnapshot = .initial) {
        self.snapshot = snapshot
    }

    @discardableResult
    public func send(_ command: EngineCommand) -> Bool {
        guard acceptsCommands else { return false }
        sentCommands.append(command)
        return true
    }

    public func latestSnapshot() -> EngineSnapshot { snapshot }

    @discardableResult
    public func drainReleasedClips() -> Int {
        drainCount += 1
        return 0
    }

    public func pump() { pumpCount += 1 }

    /// Oublie les commandes enregistrées.
    public func clearSentCommands() { sentCommands.removeAll() }
}
