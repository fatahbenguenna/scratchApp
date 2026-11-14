import AVFoundation
import Foundation
import ScratchCore

/// Décodeur des fichiers audio du système (SF-02, SF-80 ; PRD 2.2 ; architecture §5.1, §5.2, ADR-05).
///
/// - **Formats** : WAV, AIFF, MP3, M4A (AAC, ALAC), et tout format que lit `AVAudioFile`.
/// - **Sonde** (`probe`), rapide et sans décodage complet. Elle vérifie dans l'ordre :
///   1. le fichier n'est pas vide ;
///   2. il n'est pas protégé (`protectedContent`) ;
///   3. un conteneur WAV ou AIFF annonce des données audio non vides, présentes en entier ;
///   4. il s'ouvre (`unsupportedFormat` sinon) ;
///   5. sa longueur n'est pas nulle ;
///   6. sa durée respecte SF-80 (`LibraryError.checkDuration`) ;
///   7. ses 0,1 dernières secondes sont lisibles.
///
///   Toute anomalie de contenu donne `corrupted`.
/// - **Décodage** (`decode`) : les mêmes contrôles, puis une lecture par blocs de 32 768 trames dans
///   un tampon réutilisé, écrite directement dans la mémoire du clip. Le pic mémoire reste proche de
///   la taille du clip.
///   - Canaux : voir `ChannelMixdown`.
///   - Fréquence : la fréquence native est conservée jusqu'à 48 kHz ; au-delà, `AVAudioConverter`
///     (qualité maximale) convertit à 48 kHz (D-21).
///   - Annulation : `Task.isCancelled` est vérifié entre deux blocs, et une `CancellationError` est
///     propagée.
///   - Fin de fichier : un manque de 0,1 s au plus est complété de zéros (longueur approximative
///     des MP3) ; au-delà, `corrupted`.
///
/// Type non isolé : ses méthodes s'exécutent sur le pool coopératif, jamais sur le fil audio. Le
/// fil principal ne doit pas les attendre de façon bloquante (l'`AppModel` les appelle dans une
/// tâche détachée).
public struct AudioFileDecoder: AudioDecoding {
    /// Fréquence maximale conservée au décodage (ADR-05).
    public static let maximumClipSampleRate: Double = 48_000

    /// Taille des blocs lus, en trames.
    static let blockFrameCount: AVAudioFrameCount = 32_768
    /// Fin de fichier lisible exigée par la sonde, et manque toléré en fin de décodage, en secondes.
    static let endTolerance = 0.1

    private let protectedContent: any ProtectedContentChecking

    public init() {
        self.init(protectedContent: AssetProtectedContentChecker())
    }

    /// Décodeur dont la détection du contenu protégé est injectée (tests).
    init(protectedContent: any ProtectedContentChecking) {
        self.protectedContent = protectedContent
    }

    public func probe(url: URL) async throws -> AudioFileInfo {
        let (file, info) = try await openValidated(url)
        try Self.checkEndIsReadable(file)
        return info
    }

    public func decode(url: URL, title: String) async throws -> AudioClip {
        let (file, _) = try await openValidated(url)
        try Task.checkCancellation()
        return try Self.decode(file, title: title)
    }

    // MARK: - Probe

    private func openValidated(_ url: URL) async throws -> (AVAudioFile, AudioFileInfo) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value
        else { throw LibraryError.corrupted }
        guard size > 0 else { throw LibraryError.corrupted }
        if await protectedContent.isProtected(url) { throw LibraryError.protectedContent }
        try Task.checkCancellation()
        switch AudioContainerIntegrity.status(at: url, fileSize: size) {
        case .truncated, .empty: throw LibraryError.corrupted
        case .complete, .other: break
        }

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw LibraryError.unsupportedFormat
        }
        let format = file.fileFormat
        let sampleRate = format.sampleRate
        guard file.length > 0, sampleRate.isFinite, sampleRate > 0, format.channelCount > 0 else {
            throw LibraryError.corrupted
        }
        let duration = Double(file.length) / sampleRate
        try LibraryError.checkDuration(duration)
        return (file, AudioFileInfo(duration: duration, sampleRate: sampleRate, channelCount: Int(format.channelCount)))
    }

    /// Les dernières trames annoncées doivent être lisibles : sinon le fichier est tronqué.
    private static func checkEndIsReadable(_ file: AVAudioFile) throws {
        let format = file.processingFormat
        let window = max(1, min(file.length, AVAudioFramePosition((endTolerance * format.sampleRate).rounded())))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(window)) else {
            throw LibraryError.corrupted
        }
        do {
            file.framePosition = file.length - window
            try file.read(into: buffer, frameCount: AVAudioFrameCount(window))
        } catch {
            throw LibraryError.corrupted
        }
        guard buffer.frameLength > 0 else { throw LibraryError.corrupted }
    }

    // MARK: - Decoding

    private static func decode(_ file: AVAudioFile, title: String) throws -> AudioClip {
        let format = file.processingFormat
        let fileRate = format.sampleRate
        let mixdown = ChannelMixdown(
            channelCount: Int(format.channelCount),
            labels: ChannelMixdown.labels(of: format.channelLayout ?? file.fileFormat.channelLayout))
        guard let session = DecodingSession(file: file, mixdown: mixdown, blockFrameCount: blockFrameCount) else {
            throw LibraryError.corrupted
        }
        let converting = fileRate > maximumClipSampleRate
        let clipRate = converting ? maximumClipSampleRate : fileRate
        let frameCount = converting
            ? Int((Double(file.length) * clipRate / fileRate).rounded(.up))
            : Int(file.length)
        let tolerance = Int((endTolerance * clipRate).rounded())
        guard frameCount > 0 else { throw LibraryError.corrupted }
        file.framePosition = 0

        return try AudioClip(title: title, sampleRate: clipRate, frameCount: frameCount) { left, right in
            let written: Int
            if converting {
                written = try session.convert(into: left, right, frameCount: frameCount, outputRate: clipRate)
            } else {
                written = try session.copyBlocks(into: left, right, frameCount: frameCount)
            }
            // Missing frames stay at zero; more than the tolerance means the file ended early.
            if frameCount - written > tolerance { throw LibraryError.corrupted }
        }
    }
}

// MARK: - Decoding session

/// État d'un décodage : fichier, tampon de bloc réutilisé et conversion des canaux.
private final class DecodingSession {
    private let file: AVAudioFile
    private let block: AVAudioPCMBuffer
    private let mixdown: ChannelMixdown
    private(set) var sourceExhausted = false

    init?(file: AVAudioFile, mixdown: ChannelMixdown, blockFrameCount: AVAudioFrameCount) {
        guard let block = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: blockFrameCount) else {
            return nil
        }
        self.file = file
        self.block = block
        self.mixdown = mixdown
    }

    /// Lit au plus `maximum` trames dans le tampon de bloc. Renvoie 0 à la fin du fichier ou sur une
    /// erreur de lecture ; l'appelant juge alors du manque éventuel.
    private func readBlock(maximum: AVAudioFrameCount) -> Int {
        guard !sourceExhausted, file.framePosition < file.length, maximum > 0 else {
            sourceExhausted = true
            return 0
        }
        do {
            try file.read(into: block, frameCount: min(maximum, block.frameCapacity))
        } catch {
            sourceExhausted = true
            return 0
        }
        let count = Int(block.frameLength)
        if count == 0 { sourceExhausted = true }
        return count
    }

    /// Fréquence conservée : chaque bloc est converti en stéréo directement dans le clip.
    func copyBlocks(into left: UnsafeMutableBufferPointer<Float>, _ right: UnsafeMutableBufferPointer<Float>,
                    frameCount: Int) throws -> Int {
        guard let leftBase = left.baseAddress, let rightBase = right.baseAddress else { return 0 }
        var written = 0
        while written < frameCount {
            if Task.isCancelled { throw CancellationError() }
            let wanted = AVAudioFrameCount(min(frameCount - written, Int(block.frameCapacity)))
            let count = min(readBlock(maximum: wanted), frameCount - written)
            guard count > 0, let channels = block.floatChannelData else { break }
            mixdown.mix(channels, frames: count, left: leftBase + written, right: rightBase + written)
            written += count
        }
        return written
    }

    /// Au-delà de 48 kHz : chaque bloc est converti en stéréo, puis rééchantillonné par
    /// `AVAudioConverter` (qualité maximale) vers `outputRate`, et copié dans le clip.
    func convert(into left: UnsafeMutableBufferPointer<Float>, _ right: UnsafeMutableBufferPointer<Float>,
                 frameCount: Int, outputRate: Double) throws -> Int {
        let inputRate = file.processingFormat.sampleRate
        guard let leftBase = left.baseAddress, let rightBase = right.baseAddress,
              let stereoIn = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputRate, channels: 2,
                                           interleaved: false),
              let stereoOut = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: outputRate, channels: 2,
                                            interleaved: false),
              let converter = AVAudioConverter(from: stereoIn, to: stereoOut),
              let mixed = AVAudioPCMBuffer(pcmFormat: stereoIn, frameCapacity: block.frameCapacity),
              let output = AVAudioPCMBuffer(pcmFormat: stereoOut, frameCapacity: block.frameCapacity),
              let mixedChannels = mixed.floatChannelData,
              let outputChannels = output.floatChannelData
        else { throw LibraryError.corrupted }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering

        var written = 0
        while written < frameCount {
            if Task.isCancelled { throw CancellationError() }
            var conversionError: NSError?
            let status = converter.convert(to: output, error: &conversionError) { [self] requested, inputStatus in
                let count = self.readBlock(maximum: requested)
                guard count > 0, let channels = self.block.floatChannelData else {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                self.mixdown.mix(channels, frames: count, left: mixedChannels[0], right: mixedChannels[1])
                mixed.frameLength = AVAudioFrameCount(count)
                inputStatus.pointee = .haveData
                return mixed
            }
            if status == .error { throw LibraryError.corrupted }
            let count = min(Int(output.frameLength), frameCount - written)
            if count > 0 {
                (leftBase + written).update(from: outputChannels[0], count: count)
                (rightBase + written).update(from: outputChannels[1], count: count)
                written += count
            }
            if status == .endOfStream || (count == 0 && sourceExhausted) { break }
        }
        return written
    }
}

// MARK: - Container integrity

/// Contrôle des conteneurs PCM non compressés (RIFF/WAVE, AIFF/AIFC) : le bloc de données audio
/// annoncé doit être non vide et tenir dans le fichier. Un fichier tronqué ou vide est ainsi refusé
/// (`corrupted`), que le système tolère ou non la troncature.
enum AudioContainerIntegrity {
    enum Status: Equatable {
        /// Pas un WAV ni un AIFF (ou taille inconnue) : le système décide.
        case other
        /// Données audio annoncées présentes en entier.
        case complete
        /// Bloc de données audio vide.
        case empty
        /// Données annoncées au-delà de la fin du fichier, ou bloc de données introuvable.
        case truncated
    }

    static func status(at url: URL, fileSize: UInt64) -> Status {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .other }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 12), header.count == 12 else { return .other }
        let littleEndian: Bool
        let dataChunk: String
        switch (fourCC(header, at: 0), fourCC(header, at: 8)) {
        case ("RIFF", "WAVE"):
            littleEndian = true
            dataChunk = "data"
        case ("FORM", "AIFF"), ("FORM", "AIFC"):
            littleEndian = false
            dataChunk = "SSND"
        default:
            return .other
        }
        var offset: UInt64 = 12
        for _ in 0 ..< 1_024 {
            guard offset + 8 <= fileSize else { return .truncated }
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let chunk = try? handle.read(upToCount: 8), chunk.count == 8
            else { return .truncated }
            let size = UInt64(uint32(chunk, at: 4, littleEndian: littleEndian))
            if fourCC(chunk, at: 0) == dataChunk {
                // 0xFFFFFFFF: size unknown (stream or RF64-style writer): let the system decide.
                if size == 0xFFFF_FFFF { return .other }
                // AIFF: the SSND chunk starts with 8 bytes of offset and block size.
                if size <= (littleEndian ? 0 : 8) { return .empty }
                return offset + 8 + size > fileSize ? .truncated : .complete
            }
            offset += 8 + size + (size & 1)
        }
        return .other
    }

    private static func fourCC(_ data: Data, at offset: Int) -> String {
        let start = data.startIndex + offset
        return String(decoding: data[start ..< start + 4], as: UTF8.self)
    }

    private static func uint32(_ data: Data, at offset: Int, littleEndian: Bool) -> UInt32 {
        let start = data.startIndex + offset
        let bytes = data[start ..< start + 4].map(UInt32.init)
        return littleEndian
            ? bytes[0] | bytes[1] << 8 | bytes[2] << 16 | bytes[3] << 24
            : bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3]
    }
}
