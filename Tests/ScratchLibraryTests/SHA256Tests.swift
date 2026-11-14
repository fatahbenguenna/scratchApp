import Foundation
import XCTest
@testable import ScratchLibrary

/// SHA-256 portable en Swift pur (RM-58, ADR-09, D-43) : story 3.1, critère 5.
final class SHA256Tests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// CA5 — RM-58 : vecteurs officiels de FIPS 180-4 (exemples du NIST), en mémoire et par fichier.
    func testSHA256OfficialVectors_RM58() throws {
        let vectors: [(String, Data)] = [
            ("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", Data()),
            ("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", Data("abc".utf8)),
            ("248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1",
             Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
            ("cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1",
             Data(("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno"
                 + "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu").utf8)),
            ("cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0",
             Data(repeating: UInt8(ascii: "a"), count: 1_000_000)),
        ]
        for (index, (expected, message)) in vectors.enumerated() {
            XCTAssertEqual(ContentHasher.sha256Hex(of: message), expected, "vector \(index)")
            let file = temporaryDirectory.appendingPathComponent("vector-\(index).bin")
            try message.write(to: file)
            XCTAssertEqual(try ContentHasher.sha256Hex(ofFileAt: file), expected, "file vector \(index)")
        }
    }

    /// CA5 : un million de « a » fourni par morceaux de tailles irrégulières (calcul incrémental).
    func testMillionAInIrregularChunks_RM58() {
        var hasher = SHA256()
        let chunkSizes = [1, 63, 64, 65, 127, 1000, 4096, 9999]
        var remaining = 1_000_000
        var turn = 0
        while remaining > 0 {
            let size = min(chunkSizes[turn % chunkSizes.count], remaining)
            hasher.update(Data(repeating: UInt8(ascii: "a"), count: size))
            remaining -= size
            turn += 1
        }
        XCTAssertEqual(SHA256.hexString(hasher.finalize()),
                       "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    /// CA5 : frontières du rembourrage (55, 56, 63, 64, 119, 120 octets), valeurs de référence
    /// calculées par une implémentation indépendante (Python `hashlib`).
    func testPaddingBoundaries() {
        let expected: [Int: String] = [
            55: "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318",
            56: "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a",
            63: "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34",
            64: "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb",
            119: "31eba51c313a5c08226adf18d4a359cfdfd8d2e816b13f4af952f7ea6584dcfb",
            120: "2f3d335432c70b580af0e8e1b3674a7c020d683aa5f73aaaedfdc55af904c21c",
        ]
        for (length, digest) in expected {
            let message = Data(repeating: UInt8(ascii: "a"), count: length)
            XCTAssertEqual(ContentHasher.sha256Hex(of: message), digest, "\(length) bytes")
            // Byte by byte: every split point goes through the pending buffer.
            var hasher = SHA256()
            for byte in message { hasher.update([byte]) }
            XCTAssertEqual(SHA256.hexString(hasher.finalize()), digest, "\(length) bytes, one at a time")
        }
    }

    /// CA5 : `finalize()` ne consomme pas l'état ; l'empreinte est en hexadécimal minuscule.
    func testFinalizeIsRepeatableAndLowercase() {
        var hasher = SHA256()
        hasher.update(Data("ab".utf8))
        XCTAssertEqual(hasher.finalize(), hasher.finalize())
        hasher.update(Data("c".utf8))
        let hex = SHA256.hexString(hasher.finalize())
        XCTAssertEqual(hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(hex.count, 64)
        XCTAssertTrue(hex.allSatisfy { "0123456789abcdef".contains($0) })
    }

    /// CA5 : lecture en flux par blocs de 1 Mio ; 1 Mio − 1, 1 Mio et 1 Mio + 1 octets donnent la
    /// même empreinte par fichier et en mémoire, égale à la référence (Python `hashlib`).
    func testFileHashMatchesInMemoryHashAcrossBlockBoundaries() throws {
        XCTAssertEqual(ContentHasher.readChunkSize, 1_048_576)
        let expected: [Int: String] = [
            1_048_575: "4ddf525d0f1482ae9ed8ff016e61988dfab2707743585ac310be210689ddb8d6",
            1_048_576: "06b7bbfb7824aa03382051691630eb26de85102d1b08a81e907ec0744cd8a286",
            1_048_577: "0d09f3eabb5c78e5d435c41e3b3755f1c4d038657f739d0be0083c24e71235df",
        ]
        for (length, digest) in expected {
            var bytes = [UInt8](repeating: 0, count: length)
            for i in 0 ..< length { bytes[i] = UInt8(truncatingIfNeeded: i &* 31 &+ 7) }
            let data = Data(bytes)
            let file = temporaryDirectory.appendingPathComponent("pattern-\(length).bin")
            try data.write(to: file)
            XCTAssertEqual(ContentHasher.sha256Hex(of: data), digest, "memory, \(length) bytes")
            XCTAssertEqual(try ContentHasher.sha256Hex(ofFileAt: file), digest, "file, \(length) bytes")
        }
    }

    func testMissingFileThrows() {
        let missing = temporaryDirectory.appendingPathComponent("absent.wav")
        XCTAssertThrowsError(try ContentHasher.sha256Hex(ofFileAt: missing))
    }
}
