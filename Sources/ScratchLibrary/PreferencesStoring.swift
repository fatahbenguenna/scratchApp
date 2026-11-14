import Foundation

/// Lecture et écriture des préférences (SF-17 ; architecture §8). Rapide et synchrone : appelable
/// depuis le fil principal, jamais depuis le fil audio.
public protocol PreferencesStoring: Sendable {
    /// Préférences enregistrées, bornées (`sanitized()`), ou les valeurs par défaut si rien n'est
    /// enregistré ou si le document est illisible. Ne lève jamais d'erreur.
    func load() -> AppPreferences
    /// Enregistre les préférences. Un échec est ignoré (journalisé) : il ne doit pas gêner le jeu.
    func save(_ preferences: AppPreferences)
}

/// Préférences en mémoire, pour les tests et les aperçus SwiftUI.
public final class InMemoryPreferencesStore: PreferencesStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: AppPreferences?

    public init(_ preferences: AppPreferences? = nil) {
        stored = preferences
    }

    public func load() -> AppPreferences {
        lock.lock()
        defer { lock.unlock() }
        return (stored ?? .defaults).sanitized()
    }

    public func save(_ preferences: AppPreferences) {
        lock.lock()
        defer { lock.unlock() }
        stored = preferences
    }
}
