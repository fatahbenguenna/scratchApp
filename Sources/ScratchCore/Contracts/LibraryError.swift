/// Erreurs typées de l'import, du décodage et de la bibliothèque (PRD 5.3 points 5 et 6 ;
/// architecture §7.2).
///
/// Levées par `LibraryStoring` et `AudioDecoding`. `userMessage` donne le texte français affiché
/// (libellés de la spécification UX, §8.3).
public enum LibraryError: Error, Equatable, Sendable {
    /// Stockage libre insuffisant pour la copie (6.1).
    case insufficientStorage
    /// Fichier non décodable ou format non pris en charge (6.1).
    case unsupportedFormat
    /// Fichier protégé par DRM (6.1).
    case protectedContent
    /// Son plus long que 10 minutes (SF-80).
    case tooLong(duration: Double)
    /// Son plus court que 50 ms (SF-80).
    case tooShort(duration: Double)
    /// Fichier tronqué, vide ou illisible (6.1).
    case corrupted
    /// Échec d'écriture de la copie ou de l'index (RM-48). `reason` sert au diagnostic.
    case writeFailed(reason: String)
    /// Entrée inconnue, ou copie locale absente (RM-48).
    case notFound
    /// Le son de démonstration ne peut pas être supprimé (SF-74).
    case demoCannotBeDeleted

    /// Message affiché à l'utilisateur.
    public var userMessage: String {
        switch self {
        case .insufficientStorage:
            return "Espace de stockage insuffisant."
        case .unsupportedFormat:
            return "Ce format audio n'est pas pris en charge. Formats acceptés : WAV, AIFF, MP3, M4A (AAC, ALAC)."
        case .protectedContent:
            return "Les fichiers protégés (DRM) ne sont pas pris en charge."
        case .tooLong:
            return "Ce son est trop long : la durée maximale est de 10 minutes."
        case .tooShort:
            return "Ce son est trop court : la durée minimale est de 50 millisecondes."
        case .corrupted:
            return "Ce fichier est endommagé ou vide."
        case .writeFailed:
            return "La copie du son n'a pas pu être enregistrée."
        case .notFound:
            return "Ce son est introuvable dans la bibliothèque."
        case .demoCannotBeDeleted:
            return "Le son de démonstration ne peut pas être supprimé."
        }
    }

    /// Applique les durées limites de SF-80 (appelé par la sonde) : lève `tooShort` ou `tooLong`.
    public static func checkDuration(_ seconds: Double) throws {
        guard seconds.isFinite else { throw LibraryError.corrupted }
        if seconds < TurntableConstants.minimumDurationSeconds { throw LibraryError.tooShort(duration: seconds) }
        if seconds > TurntableConstants.maximumDurationSeconds { throw LibraryError.tooLong(duration: seconds) }
    }
}
