import Foundation
import ScratchCore

/// Décodeur factice des tests de l'`AppModel` (story 6.1, CA 9).
///
/// La sonde lit l'en-tête des WAV de `TestWAV`, sauf si un script la remplace par une erreur. Le
/// décodage rend un clip synthétique de la bonne durée (100 trames par seconde) avec le titre
/// fourni. Il peut être retenu par une porte, pour observer l'état « Chargement… ».
final class FakeDecoder: AudioDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private var probeFailure: LibraryError?
    private var decodeFailure: LibraryError?
    private var holdsDecoding = false
    private var decodedURLs: [URL] = []
    private var decodingStarted = false

    /// La prochaine sonde lèvera `error` (une seule fois).
    func failNextProbe(with error: LibraryError) {
        locked { probeFailure = error }
    }

    /// Les décodages lèveront `error`.
    func failDecoding(with error: LibraryError?) {
        locked { decodeFailure = error }
    }

    /// Retient les décodages jusqu'à `releaseDecoding()`.
    func holdDecoding() {
        locked { holdsDecoding = true }
    }

    func releaseDecoding() {
        locked { holdsDecoding = false }
    }

    var decoded: [URL] { locked { decodedURLs } }
    var hasStartedDecoding: Bool { locked { decodingStarted } }

    func probe(url: URL) async throws -> AudioFileInfo {
        if let error = locked({ () -> LibraryError? in
            defer { probeFailure = nil }
            return probeFailure
        }) {
            throw error
        }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { throw LibraryError.corrupted }
        guard let duration = TestWAV.duration(of: data) else { throw LibraryError.unsupportedFormat }
        try LibraryError.checkDuration(duration)
        return AudioFileInfo(duration: duration, sampleRate: 8_000, channelCount: 1)
    }

    func decode(url: URL, title: String) async throws -> AudioClip {
        locked {
            decodedURLs.append(url)
            decodingStarted = true
        }
        while locked({ holdsDecoding }) {
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        if let error = locked({ decodeFailure }) { throw error }
        let duration = (try? Data(contentsOf: url)).flatMap(TestWAV.duration(of:)) ?? 1
        return AudioClip(title: title, sampleRate: 100, frameCount: max(1, Int(duration * 100))) { _, _ in }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

/// WAV PCM 16 bits mono minimal : `seed` change le contenu (empreinte SHA-256 distincte).
enum TestWAV {
    static func data(seconds: Double, seed: UInt32 = 1) -> Data {
        let sampleRate = 8_000
        let frames = Int((seconds * Double(sampleRate)).rounded())
        var bytes = Data()
        func append(_ text: String) { bytes.append(contentsOf: Array(text.utf8)) }
        func append32(_ value: Int) { withUnsafeBytes(of: UInt32(value).littleEndian) { bytes.append(contentsOf: $0) } }
        func append16(_ value: Int) { withUnsafeBytes(of: UInt16(truncatingIfNeeded: value).littleEndian) { bytes.append(contentsOf: $0) } }
        append("RIFF"); append32(36 + frames * 2); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1); append32(sampleRate); append32(sampleRate * 2)
        append16(2); append16(16)
        append("data"); append32(frames * 2)
        var state = seed
        for _ in 0 ..< frames {
            state = state &* 1_664_525 &+ 1_013_904_223
            append16(Int(state >> 16))
        }
        return bytes
    }

    static func duration(of data: Data) -> Double? {
        guard data.count >= 44, String(decoding: data.prefix(4), as: UTF8.self) == "RIFF" else { return nil }
        func read32(_ offset: Int) -> Int {
            data[data.startIndex + offset ..< data.startIndex + offset + 4].reversed().reduce(0) { $0 << 8 | Int($1) }
        }
        let byteRate = read32(28), dataSize = read32(40)
        guard byteRate > 0, data.count >= 44 + dataSize else { return nil }
        return Double(dataSize) / Double(byteRate)
    }
}
