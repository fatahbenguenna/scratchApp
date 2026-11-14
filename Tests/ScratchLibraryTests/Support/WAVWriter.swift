import Foundation

/// WAV PCM 16 bits mono écrits par les tests (story 3.2, CA9) : en-tête RIFF minimal, échantillons
/// pseudo-aléatoires tirés de `seed` (deux graines différentes donnent deux empreintes différentes).
enum WAVWriter {
    static func data(seconds: Double, sampleRate: Int = 8_000, seed: UInt32 = 1) -> Data {
        let frames = Int((seconds * Double(sampleRate)).rounded())
        let dataSize = frames * 2
        var bytes = Data()
        bytes.reserveCapacity(44 + dataSize)
        func append(_ text: String) { bytes.append(contentsOf: Array(text.utf8)) }
        func append32(_ value: Int) { withUnsafeBytes(of: UInt32(value).littleEndian) { bytes.append(contentsOf: $0) } }
        func append16(_ value: Int) { withUnsafeBytes(of: UInt16(value).littleEndian) { bytes.append(contentsOf: $0) } }
        append("RIFF")
        append32(36 + dataSize)
        append("WAVE")
        append("fmt ")
        append32(16)
        append16(1) // PCM
        append16(1) // mono
        append32(sampleRate)
        append32(sampleRate * 2)
        append16(2)
        append16(16)
        append("data")
        append32(dataSize)
        var state = seed
        for _ in 0 ..< frames {
            state = state &* 1_664_525 &+ 1_013_904_223
            append16(Int(state >> 16))
        }
        return bytes
    }

    @discardableResult
    static func write(to url: URL, seconds: Double, sampleRate: Int = 8_000, seed: UInt32 = 1) throws -> URL {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data(seconds: seconds, sampleRate: sampleRate, seed: seed).write(to: url)
        return url
    }

    /// Durée d'un WAV écrit par `write`, lue dans son en-tête ; `nil` si ce n'en est pas un.
    static func duration(of data: Data) -> Double? {
        guard data.count >= 44,
              String(decoding: data[0 ..< 4], as: UTF8.self) == "RIFF",
              String(decoding: data[8 ..< 12], as: UTF8.self) == "WAVE"
        else { return nil }
        func read32(_ offset: Int) -> Int {
            data[offset ..< offset + 4].reversed().reduce(0) { $0 << 8 | Int($1) }
        }
        let byteRate = read32(28), dataSize = read32(40)
        guard byteRate > 0, data.count >= 44 + dataSize else { return nil }
        return Double(dataSize) / Double(byteRate)
    }
}
