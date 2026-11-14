import Foundation

/// Bibliothèque locale des sons (SF-02, SF-74, SF-75, RM-47 à RM-49, RM-58 ; PRD 3.1, 3.2 ;
/// architecture §5.1, §8).
///
/// Implémentation : `LibraryStore` (acteur, ScratchLibrary, stories 3.1 et 3.2). Toutes les
/// opérations sont asynchrones et sérialisées ; aucune n'est appelée depuis le fil audio.
public protocol LibraryStoring: Sendable {
    /// Entrées : le son de démonstration en tête, puis les imports du plus récent au plus ancien.
    var entries: [LibraryEntry] { get async }

    /// Réconcilie l'index avec les copies de « Banque de sons » (RM-48, D-11) : retire toute entrée dont la
    /// copie est absente ou de taille différente, réécrit l'index, et renvoie les entrées retirées par cet
    /// appel (vide si rien n'a changé). Appelée par l'`AppModel` au lancement ; ne lève pas d'erreur.
    func reconcile() async -> [LibraryEntry]

    /// Copie `url` dans `Documents/Banque de sons/` et l'ajoute à l'index (SF-02).
    ///
    /// Étapes : accès au fichier source sans le modifier, copie dans un fichier temporaire,
    /// empreinte SHA-256, dédoublonnage (SF-75 : renvoie `.existing` et supprime la copie
    /// temporaire), sonde (`AudioDecoding.probe`, durées SF-80 comprises), déplacement
    /// atomique à la place finale avec suffixe anti-collision (SF-60), puis écriture atomique de
    /// l'index (5.3, RM-48). En cas d'échec, aucune copie incomplète ni entrée n'est conservée.
    func importFile(at url: URL) async throws -> ImportResult

    /// Supprime l'entrée et sa copie locale, jamais le fichier d'origine (RM-49).
    /// Lève `LibraryError.demoCannotBeDeleted` pour le son de démonstration, `.notFound` si l'entrée
    /// est inconnue.
    func delete(id: UUID) async throws

    /// URL de la copie locale, vérifiée avant chaque chargement : une copie absente ou de taille
    /// différente écarte l'entrée et lève `LibraryError.notFound` (RM-48, IC-10, D-11). L'entrée retirée
    /// n'est pas renvoyée par un `reconcile()` ultérieur : l'appelant la connaît déjà. Lève aussi
    /// `.notFound` pour le son de démonstration (pas de fichier) et pour une entrée inconnue.
    func url(for id: UUID) async throws -> URL
}
