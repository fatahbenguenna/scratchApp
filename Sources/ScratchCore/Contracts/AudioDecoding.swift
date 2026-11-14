import Foundation

/// Caractéristiques d'un fichier audio lisible, données par la sonde.
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

/// Décodage des fichiers audio (SF-02, SF-80 ; PRD 5.3 point 5 ; architecture §5.1).
///
/// Défini dans le cœur pour que la bibliothèque et l'`AppModel` soient testables avec un décodeur
/// factice, y compris sous Linux. Implémentation réelle : `AudioFileDecoder` (ScratchAudio,
/// AVFoundation, story 2.2). Aucune méthode n'est appelée depuis le fil principal ni le fil audio :
/// tâche détachée uniquement.
///
/// Erreurs : `LibraryError.unsupportedFormat`, `.protectedContent`, `.corrupted`, `.tooLong`, `.tooShort`.
public protocol AudioDecoding: Sendable {
    /// Sonde rapide, sans décodage complet : format lisible, contenu non protégé, fichier non vide
    /// ni tronqué, durée dans les limites de SF-80 (`LibraryError.checkDuration`).
    func probe(url: URL) async throws -> AudioFileInfo

    /// Décodage complet en `AudioClip` stéréo Float32 désentrelacé, à la fréquence native plafonnée à
    /// 48 kHz (ADR-05) ; mono dupliqué, multicanal réduit en stéréo sans saturation (SF-80).
    func decode(url: URL, title: String) async throws -> AudioClip
}

extension AudioDecoding {
    /// Décode `url` avec, pour titre, le nom du fichier sans extension.
    public func decode(url: URL) async throws -> AudioClip {
        try await decode(url: url, title: url.deletingPathExtension().lastPathComponent)
    }
}
