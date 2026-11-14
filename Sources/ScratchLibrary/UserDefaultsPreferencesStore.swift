import Foundation

/// Préférences dans `UserDefaults` (5.3, SF-17, SF-24 ; architecture §8, ADR-11) : un document JSON
/// unique sous la clé `key`.
///
/// - Lecture : décodage tolérant d'`AppPreferences` (clé absente ou illisible → valeur par défaut),
///   puis `sanitized()` (valeur hors bornes → borne). Un document absent, illisible ou d'un autre
///   type donne les valeurs par défaut, sans erreur.
/// - Écriture : document borné, encodé d'un bloc. L'`AppModel` regroupe les écritures (0,5 s après
///   le dernier changement) et ne les fait jamais depuis le fil audio.
///
/// `UserDefaults` est sûr entre les fils.
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
        guard let data = defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(AppPreferences.self, from: data)
        else { return .defaults }
        return preferences.sanitized()
    }

    public func save(_ preferences: AppPreferences) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(preferences.sanitized()) else { return }
        defaults.set(data, forKey: key)
    }
}
