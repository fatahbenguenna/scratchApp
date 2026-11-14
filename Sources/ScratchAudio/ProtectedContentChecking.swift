import AVFoundation
import Foundation

/// Détection du contenu protégé (DRM) d'un fichier (6.1 « Importer un fichier protégé » ; R-11).
///
/// Injectable : les tests remplacent la détection réelle par un double, le contenu protégé réel ne
/// se vérifiant qu'en recette (6.3).
protocol ProtectedContentChecking: Sendable {
    /// `true` si le fichier est protégé. `false` s'il ne l'est pas ou si la détection échoue : la
    /// sonde décide alors (format non pris en charge, fichier endommagé).
    func isProtected(_ url: URL) async -> Bool
}

/// Détection par `AVURLAsset.hasProtectedContent`.
struct AssetProtectedContentChecker: ProtectedContentChecking {
    func isProtected(_ url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        return (try? await asset.load(.hasProtectedContent)) ?? false
    }
}
