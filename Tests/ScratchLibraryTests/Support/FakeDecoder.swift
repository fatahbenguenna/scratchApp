import Foundation
import ScratchCore
import ScratchLibrary

/// Décodeur factice scriptable (story 3.2, CA9).
///
/// Par défaut, la sonde lit l'en-tête des WAV de `WAVWriter`, puis applique `checkDuration`. Tout
/// autre contenu donne `unsupportedFormat`, et un fichier vide ou un WAV incomplet `corrupted` (comme `AudioFileDecoder`). Un script remplace ce
/// comportement pour un test. Les URL sondées sont enregistrées.
final class FakeDecoder: AudioDecoding, @unchecked Sendable {
    typealias Script = @Sendable (URL) async throws -> AudioFileInfo

    private let script: Script?
    private let lock = NSLock()
    private var recorded: [URL] = []

    init(script: Script? = nil) {
        self.script = script
    }

    /// URL passées à la sonde, dans l'ordre.
    var probedURLs: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func probe(url: URL) async throws -> AudioFileInfo {
        record(url)
        if let script { return try await script(url) }
        return try Self.wavInfo(at: url)
    }

    func decode(url: URL, title: String) async throws -> AudioClip {
        throw LibraryError.unsupportedFormat
    }

    static func wavInfo(at url: URL) throws -> AudioFileInfo {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { throw LibraryError.corrupted }
        guard data.count >= 12, String(decoding: data[0 ..< 4], as: UTF8.self) == "RIFF" else {
            throw LibraryError.unsupportedFormat
        }
        guard let duration = WAVWriter.duration(of: data) else { throw LibraryError.corrupted }
        try LibraryError.checkDuration(duration)
        return AudioFileInfo(duration: duration, sampleRate: 8_000, channelCount: 1)
    }

    private func record(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(url)
    }
}

/// Point de rendez-vous des sondes : chaque sonde attend que `count` sondes soient arrivées (ou
/// deux secondes), pour forcer deux imports à se chevaucher pendant la sonde.
actor ProbeRendezvous {
    private(set) var arrivals = 0

    func arrive(waitingFor count: Int) async {
        arrivals += 1
        let deadline = Date().addingTimeInterval(2)
        while arrivals < count, Date() < deadline {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }
}

/// Espace libre fixe (ou inconnu avec `nil`).
struct FixedCapacity: StorageCapacityProviding {
    let bytes: Int64?

    func availableCapacity(forWritingAt url: URL) -> Int64? { bytes }
}
