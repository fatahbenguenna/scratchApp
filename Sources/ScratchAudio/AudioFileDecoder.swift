import Foundation
import ScratchCore

/// Décodeur des fichiers audio du système (SF-02, SF-80 ; PRD 2.2 ; architecture §5.1, ADR-05).
///
/// **Squelette (story 2.2, James) : refuse tous les fichiers (`unsupportedFormat`).** À implémenter :
/// - `probe` : `AVURLAsset.load(.hasProtectedContent)` → `protectedContent` ; `AVAudioFile(forReading:)`
///   → `unsupportedFormat` si l'ouverture échoue ; `corrupted` si la longueur est nulle ou si les
///   dernières trames annoncées sont illisibles (fichier tronqué) ; durée → `LibraryError.checkDuration` ;
/// - `decode` : `AVAudioConverter` vers Float32 désentrelacé stéréo ; mono dupliqué, stéréo conservée,
///   multicanal réduit en stéréo sans saturation (6.15) ; fréquence native conservée jusqu'à 48 kHz,
///   convertie à 48 kHz au-delà ; remplissage direct de la mémoire du clip
///   (`AudioClip(title:sampleRate:frameCount:fill:)`) par blocs ; annulable ; pic mémoire ≤ 1,5 × le clip.
public struct AudioFileDecoder: AudioDecoding {
    /// Fréquence maximale conservée au décodage (ADR-05).
    public static let maximumClipSampleRate: Double = 48_000

    public init() {}

    public func probe(url: URL) async throws -> AudioFileInfo {
        throw LibraryError.unsupportedFormat
    }

    public func decode(url: URL, title: String) async throws -> AudioClip {
        throw LibraryError.unsupportedFormat
    }
}
