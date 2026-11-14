import Foundation
import ScratchCore
import ScratchLibrary

/// Décodage d'un fichier audio en `AudioClip` prêt pour le rendu (SF-80 ; architecture §5.3).
///
/// Implémentation : `AudioFileDecoder` (AVAudioFile + AVAudioConverter). Le décodage est long
/// (jusqu'à 10 minutes de son) : il s'exécute dans une tâche détachée, jamais sur le fil
/// principal ni sur le fil audio. Erreurs : `LibraryError` (`unsupportedFormat`,
/// `protectedContent`, `corrupted`, `tooLong`, `tooShort`).
public protocol AudioClipDecoding: Sendable {
    /// Décode `url` en stéréo Float32 désentrelacée, à la fréquence native plafonnée à 48 kHz.
    func decode(url: URL, title: String) async throws -> AudioClip
}

extension AudioClipDecoding {
    /// Décode `url` avec, pour titre, le nom du fichier sans extension.
    public func decode(url: URL) async throws -> AudioClip {
        try await decode(url: url, title: url.deletingPathExtension().lastPathComponent)
    }
}
