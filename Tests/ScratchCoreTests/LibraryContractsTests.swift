import XCTest
@testable import ScratchCore

final class LibraryEntryTests: XCTestCase {
    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Format persistant de `library.json` (5.3) : les clés JSON sont figées.
    func testJSONFormatIsStable_RM58() throws {
        let entry = LibraryEntry(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            contentHash: String(repeating: "ab", count: 32),
            fileName: "voix_funk.wav",
            fileSize: 123_456,
            title: "voix_funk",
            duration: 3.5,
            importedAt: Date(timeIntervalSince1970: 1_794_000_000),
            origin: .imported
        )
        let json = String(decoding: try encoder().encode(entry), as: UTF8.self)
        XCTAssertEqual(json, #"{"contentHash":"\#(String(repeating: "ab", count: 32))","duration":3.5,"fileName":"voix_funk.wav","fileSize":123456,"id":"11111111-2222-3333-4444-555555555555","importedAt":"2026-11-06T21:20:00Z","origin":"imported","title":"voix_funk"}"#)
        XCTAssertEqual(try decoder().decode(LibraryEntry.self, from: Data(json.utf8)), entry)
    }

    /// SF-74 : le son de démonstration a un identifiant fixe et ne peut pas être supprimé.
    func testDemoEntry_SF74() {
        let demo = LibraryEntry.demo(title: "Démo", duration: 8)
        XCTAssertEqual(demo.id, LibraryEntry.demoID)
        XCTAssertEqual(demo.origin, .demo)
        XCTAssertFalse(demo.isDeletable)
        XCTAssertTrue(demo.fileName.isEmpty)
        XCTAssertEqual(demo.fileSize, 0)
    }

    func testOriginRawValuesAreStable() {
        XCTAssertEqual(LibraryEntry.Origin.allCases.map(\.rawValue), ["imported", "demo", "microphone", "mix"])
    }

    func testImportResultExposesEntry_SF75() {
        let entry = LibraryEntry.demo(title: "Démo", duration: 8)
        XCTAssertTrue(ImportResult.added(entry).isNew)
        XCTAssertFalse(ImportResult.existing(entry).isNew)
        XCTAssertEqual(ImportResult.existing(entry).entry, entry)
    }
}

final class LibraryErrorTests: XCTestCase {
    /// SF-80 : durée minimale 50 ms, maximale 10 minutes.
    func testDurationLimits_SF80() {
        XCTAssertNoThrow(try LibraryError.checkDuration(0.05))
        XCTAssertNoThrow(try LibraryError.checkDuration(600))
        XCTAssertThrowsError(try LibraryError.checkDuration(0.049)) {
            XCTAssertEqual($0 as? LibraryError, .tooShort(duration: 0.049))
        }
        XCTAssertThrowsError(try LibraryError.checkDuration(25 * 60)) {
            XCTAssertEqual($0 as? LibraryError, .tooLong(duration: 1500))
        }
        XCTAssertThrowsError(try LibraryError.checkDuration(.nan)) {
            XCTAssertEqual($0 as? LibraryError, .corrupted)
        }
    }

    func testEveryErrorHasAFrenchUserMessage() {
        let errors: [LibraryError] = [
            .insufficientStorage, .unsupportedFormat, .protectedContent, .tooLong(duration: 1500),
            .tooShort(duration: 0.01), .corrupted, .writeFailed(reason: "disk"), .notFound, .demoCannotBeDeleted,
        ]
        for error in errors { XCTAssertFalse(error.userMessage.isEmpty, "\(error)") }
        XCTAssertEqual(LibraryError.insufficientStorage.userMessage, "Espace de stockage insuffisant.") // 6.1
        XCTAssertTrue(LibraryError.tooLong(duration: 1500).userMessage.contains("10 minutes")) // 6.1
    }
}
