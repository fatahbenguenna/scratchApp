import Foundation

/// Caractéristiques d'un fichier audio lisible.
public struct AudioFileInfo: Equatable, Sendable {
    /// Durée en secondes.
    public var duration: Double
    /// Fréquence d'échantillonnage native, en Hz.
    public var sampleRate: Double
    /// Nombre de canaux du fichier (avant réduction en stéréo).
    public var channelCount: Int

    public init(duration: Double, sampleRate: Double, channelCount: Int) {
        self.duration = duration
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }
}

/// Vérifie qu'un fichier est un audio lisible avant de l'ajouter à la bibliothèque (SF-02, 5.3).
///
/// Implémenté dans ScratchAudio par `AudioFileDecoder` (AVFoundation) ; simulé dans les tests Linux.
/// Lève `LibraryError.unsupportedFormat`, `.protectedContent` ou `.corrupted`. Les durées limites
/// (SF-80) sont appliquées par la bibliothèque avec `LibraryError.checkDuration(_:)`.
public protocol AudioFileValidating: Sendable {
    func validate(url: URL) async throws -> AudioFileInfo
}
