import Foundation
import ScratchCore
import ScratchLibrary

/// Décodeur et validateur de fichiers audio du système (SF-02, SF-80 ; architecture §5.3, ADR-05).
///
/// **Squelette (story EP2, James) : refuse tous les fichiers (`unsupportedFormat`).** À implémenter :
/// - `AVURLAsset.load(.hasProtectedContent)` → `protectedContent` ;
/// - `AVAudioFile(forReading:)` → `unsupportedFormat` si l'ouverture échoue, `corrupted` si la
///   longueur est nulle ou si la lecture échoue avant la fin annoncée (fichier tronqué) ;
/// - durée → `LibraryError.checkDuration` ;
/// - `AVAudioConverter` vers Float32 désentrelacé stéréo : mono dupliqué, stéréo conservée,
///   multicanal réduit en stéréo sans saturation (matrice de réduction normalisée, 6.15) ;
///   fréquence native conservée jusqu'à 48 kHz, convertie à 48 kHz au-delà (ADR-05) ;
/// - remplissage direct de la mémoire du clip (`AudioClip(title:sampleRate:frameCount:fill:)`),
///   par blocs, sans copie intermédiaire du fichier entier ;
/// - `validate` : ouverture, protection, durée et lecture des dernières trames, sans décodage complet.
public struct AudioFileDecoder: AudioClipDecoding, AudioFileValidating {
    /// Fréquence maximale conservée au décodage (ADR-05).
    public static let maximumClipSampleRate: Double = 48_000

    public init() {}

    public func decode(url: URL, title: String) async throws -> AudioClip {
        throw LibraryError.unsupportedFormat
    }

    public func validate(url: URL) async throws -> AudioFileInfo {
        throw LibraryError.unsupportedFormat
    }
}
