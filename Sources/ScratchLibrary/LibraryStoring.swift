import Foundation

/// Bibliothèque locale des sons (SF-02, SF-74, SF-75, RM-47 à RM-49, RM-58 ; architecture §5.2, §8).
///
/// Implémentation de référence : `LibraryStore` (acteur). Toutes les opérations sont asynchrones et
/// sérialisées ; aucune ne doit être appelée depuis le fil audio.
public protocol LibraryStoring: Sendable {
    /// Entrées : le son de démonstration en tête, puis les imports du plus récent au plus ancien.
    var entries: [LibraryEntry] { get async }

    /// Copie `url` dans `Documents/Banque de sons/` et l'ajoute à l'index (SF-02).
    ///
    /// Étapes : accès au fichier source sans le modifier, copie dans un fichier temporaire,
    /// empreinte SHA-256, dédoublonnage (SF-75 : renvoie `.existing` et supprime la copie
    /// temporaire), validation (`AudioFileValidating`, `LibraryError.checkDuration`), déplacement
    /// atomique à la place finale avec suffixe anti-collision (SF-60), puis écriture atomique de
    /// l'index (5.3, RM-48). En cas d'échec, aucune copie incomplète ni entrée n'est conservée.
    func importFile(at url: URL) async throws -> ImportResult

    /// Supprime l'entrée et sa copie locale, jamais le fichier d'origine (RM-49).
    /// Lève `LibraryError.demoCannotBeDeleted` pour le son de démonstration, `.notFound` si l'entrée
    /// est inconnue.
    func delete(id: UUID) async throws

    /// URL de la copie locale, ou `nil` pour le son de démonstration et les entrées inconnues.
    func url(for id: UUID) async -> URL?
}
