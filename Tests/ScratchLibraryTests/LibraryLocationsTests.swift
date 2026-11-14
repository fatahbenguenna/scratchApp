import XCTest
@testable import ScratchLibrary

final class LibraryLocationsTests: XCTestCase {
    func testLayoutMatchesSpec() {
        let root = URL(fileURLWithPath: "/tmp/scratchapp-tests", isDirectory: true)
        let locations = LibraryLocations(documentsDirectory: root.appendingPathComponent("Documents"),
                                         supportDirectory: root.appendingPathComponent("Support"))
        XCTAssertEqual(locations.soundBankDirectory.lastPathComponent, "Banque de sons")
        XCTAssertEqual(locations.recordingsDirectory.lastPathComponent, "Enregistrements")
        XCTAssertEqual(locations.libraryIndexURL.lastPathComponent, "library.json")
        // 3.2 : temporaries live next to the index, on the same volume as the sound bank.
        XCTAssertEqual(locations.importsDirectory.lastPathComponent, "Imports")
        XCTAssertEqual(locations.importsDirectory.deletingLastPathComponent().lastPathComponent, "Support")
    }
}
