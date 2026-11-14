import Foundation
import ScratchCore
import XCTest
@testable import ScratchLibrary

/// Index `library.json` (5.3, NFR12) : story 3.1, critères 2, 3 et 7.
final class LibraryIndexTests: XCTestCase {
    private var sandbox: LibrarySandbox!

    override func setUpWithError() throws {
        sandbox = try LibrarySandbox()
    }

    override func tearDownWithError() throws {
        sandbox.remove()
    }

    private var index: LibraryIndex { LibraryIndex(url: sandbox.locations.libraryIndexURL) }

    /// CA2 — 5.3 : `{"version": 1, "entries": [...]}`, dates ISO 8601, démo jamais écrite,
    /// écriture atomique sans fichier temporaire laissé, y compris en remplacement.
    func testIndexFormatIsVersionedAndAtomic() throws {
        let entry = sandbox.entry(fileName: "voix_funk.wav", size: 123_456,
                                  importedAt: Date(timeIntervalSince1970: 1_794_000_000))
        try index.save([.demo(title: DemoSound.title, duration: DemoSound.duration), entry])
        try index.save([.demo(title: DemoSound.title, duration: DemoSound.duration), entry])

        let document = try sandbox.readIndexDocument()
        XCTAssertEqual(Set(document.keys), ["version", "entries"])
        XCTAssertEqual(document["version"] as? Int, 1)
        let entries = try XCTUnwrap(document["entries"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1, "the demo is never written")
        XCTAssertEqual(entries.first?["id"] as? String, entry.id.uuidString)
        XCTAssertEqual(entries.first?["importedAt"] as? String, "2026-11-06T21:20:00Z")
        XCTAssertEqual(entries.first?["origin"] as? String, "imported")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: sandbox.locations.supportDirectory.path)
        XCTAssertEqual(leftovers, ["library.json"], "no temporary file is left behind")
        XCTAssertEqual(index.load(), LibraryIndex.LoadResult(entries: [entry], setAsideURL: nil))
    }

    /// CA2 : le dossier Application Support/ScratchApp est créé au besoin.
    func testSaveCreatesTheSupportDirectory() throws {
        try FileManager.default.removeItem(at: sandbox.locations.supportDirectory)
        try index.save([sandbox.entry(fileName: "a.wav", size: 1)])
        XCTAssertEqual(index.load().entries.count, 1)
    }

    func testMissingIndexIsEmptyAndNothingIsSetAside() {
        XCTAssertEqual(index.load(), LibraryIndex.LoadResult(entries: [], setAsideURL: nil))
    }

    /// CA3 — NFR12 : document illisible, version inconnue ou absente, `entries` invalide → déplacé
    /// vers `library.json.corrupt`, puis `_2`, `_3`… sans écraser un document déjà mis de côté.
    func testUnreadableOrUnknownDocumentsAreSetAsideWithoutOverwriting_NFR12() throws {
        let documents = [
            "{ pas du JSON",
            #"{"version": 2, "entries": []}"#,
            #"{"entries": []}"#,
            #"{"version": 1, "entries": {}}"#,
            "",
        ]
        let directory = sandbox.locations.supportDirectory
        for (number, contents) in documents.enumerated() {
            try sandbox.writeRawIndex(contents)
            let result = index.load()
            let expectedName = number == 0 ? "library.json.corrupt" : "library.json.corrupt_\(number + 1)"
            XCTAssertEqual(result.entries, [], contents)
            XCTAssertEqual(result.setAsideURL?.lastPathComponent, expectedName, contents)
            XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.locations.libraryIndexURL.path))
        }
        for (number, contents) in documents.enumerated() {
            let name = number == 0 ? "library.json.corrupt" : "library.json.corrupt_\(number + 1)"
            let saved = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            XCTAssertEqual(saved, contents, "set-aside documents are kept as they were")
        }
    }

    /// CA3, CA7 : une entrée illisible, en double ou se présentant comme la démo est ignorée ; les
    /// autres sont conservées avec leur identifiant, et le document d'origine est copié de côté.
    func testInvalidEntriesAreSkippedAndTheOriginalIsKept() throws {
        let valid = sandbox.entry(fileName: "a.wav", size: 10)
        let validJSON = String(decoding: try LibraryIndex.makeEncoder().encode(valid), as: UTF8.self)
        let demoJSON = String(decoding: try LibraryIndex.makeEncoder().encode(
            LibraryEntry.demo(title: DemoSound.title, duration: DemoSound.duration)), as: UTF8.self)
        let contents = #"{"version": 1, "entries": [\#(validJSON), {"id": "x"}, 42, \#(validJSON), \#(demoJSON)]}"#
        try sandbox.writeRawIndex(contents)

        let result = index.load()
        XCTAssertEqual(result.entries, [valid])
        XCTAssertEqual(result.setAsideURL?.lastPathComponent, "library.json.corrupt")
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(result.setAsideURL), encoding: .utf8), contents)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sandbox.locations.libraryIndexURL.path))
    }

    /// CA7 — RM-58 : l'aller-retour conserve chaque entrée à l'identique (dates à la seconde).
    func testRoundTripPreservesEntries_RM58() throws {
        let entries = [
            sandbox.entry(fileName: "a.wav", size: 1, importedAt: Date(timeIntervalSince1970: 1_794_000_000)),
            sandbox.entry(fileName: "b c é.m4a", size: 2, importedAt: Date(timeIntervalSince1970: 1_794_000_001)),
        ]
        try index.save(entries)
        XCTAssertEqual(index.load().entries, entries)
    }

    /// CA2 : un index impossible à écrire lève `writeFailed`.
    func testSaveFailureThrowsWriteFailed() throws {
        let blocked = sandbox.root.appendingPathComponent("blocked")
        try Data("file, not a directory".utf8).write(to: blocked)
        let unwritable = LibraryIndex(url: blocked.appendingPathComponent("library.json"))
        XCTAssertThrowsError(try unwritable.save([])) { error in
            guard case .writeFailed = error as? LibraryError else { return XCTFail("\(error)") }
        }
    }
}
