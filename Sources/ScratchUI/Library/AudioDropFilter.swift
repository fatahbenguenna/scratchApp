import Foundation
import UniformTypeIdentifiers

/// Motif de refus d'un dépôt sur une platine, affiché dès le survol (UX §5.9 ; spec 6.13, D-27).
enum AudioDropRejection: Equatable, Sendable {
    /// Type non audio, ou audio d'un format non pris en charge.
    case unsupportedFormat
    /// Plusieurs fichiers à la fois (D-27).
    case multipleFiles
    /// Un import ou un chargement est déjà en cours sur cette platine.
    case importInProgress

    var message: String {
        switch self {
        case .unsupportedFormat: return "Format non pris en charge"
        case .multipleFiles: return "Un seul fichier à la fois"
        case .importInProgress: return "Import en cours…"
        }
    }
}

/// Décision prise au survol, sans lire le contenu des fichiers.
enum AudioDropDecision: Equatable, Sendable {
    case accept
    case reject(AudioDropRejection)
    /// Un seul fichier, connu seulement par son URL (glisser depuis le Finder) : son type se lit dans
    /// l'extension, une fois l'URL obtenue.
    case resolveFileURL
}

/// Filtre des dépôts (story 5.2, logique pure) : un seul fichier, WAV, AIFF, MP3 ou M4A (SF-02,
/// SF-73), jamais pendant un import sur la platine.
enum AudioDropFilter {
    /// Types acceptés, communs au sélecteur et au dépôt : WAV, AIFF, MP3, M4A (AAC ou ALAC).
    static let acceptedTypes: [UTType] = [.wav, .aiff, .mp3, .mpeg4Audio]

    /// - Parameter itemTypes: identifiants de type déclarés par chaque élément déposé.
    static func evaluate(itemTypes: [[String]], isBusy: Bool) -> AudioDropDecision {
        if isBusy { return .reject(.importInProgress) }
        guard let identifiers = itemTypes.first else { return .reject(.unsupportedFormat) }
        if itemTypes.count > 1 { return .reject(.multipleFiles) }
        if audioType(in: identifiers) != nil { return .accept }
        if identifiers.contains(where: { UTType($0)?.conforms(to: .fileURL) == true }) { return .resolveFileURL }
        return .reject(.unsupportedFormat)
    }

    /// Premier type déclaré qui est un format audio accepté.
    static func audioType(in identifiers: [String]) -> UTType? {
        for identifier in identifiers {
            guard let type = UTType(identifier) else { continue }
            if acceptedTypes.contains(where: { type.conforms(to: $0) }) { return type }
        }
        return nil
    }

    /// Fichier accepté d'après son extension (glisser depuis le Finder).
    static func isAcceptedFile(_ url: URL) -> Bool {
        guard !url.pathExtension.isEmpty, let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return acceptedTypes.contains(where: { type.conforms(to: $0) })
    }
}
