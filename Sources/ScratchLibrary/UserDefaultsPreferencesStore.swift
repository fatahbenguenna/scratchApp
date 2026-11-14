import Foundation

/// Préférences dans `UserDefaults` (5.3), sous la forme d'un document JSON unique (clé `key`).
///
/// **Squelette (story 3.4, Hugo) : renvoie les valeurs par défaut et n'enregistre rien.**
/// À implémenter : encodage JSON d'`AppPreferences` sous `key`, décodage tolérant puis
/// `sanitized()`, valeurs par défaut si la clé est absente ou illisible.
public final class UserDefaultsPreferencesStore: PreferencesStoring, @unchecked Sendable {
    /// Clé du document de préférences.
    public static let defaultKey = "app.scratchapp.preferences.v1"

    public let key: String
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard, key: String = UserDefaultsPreferencesStore.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> AppPreferences {
        .defaults
    }

    public func save(_ preferences: AppPreferences) {}
}
