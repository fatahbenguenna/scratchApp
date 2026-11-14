import Foundation
import ScratchCore
import XCTest
@testable import ScratchLibrary

final class LibraryStoreTests: XCTestCase {
    /// Décodeur factice : la sonde et le décodage refusent tout (aucun fichier n'est importé ici).
    private struct RejectingDecoder: AudioDecoding {
        func probe(url: URL) async throws -> AudioFileInfo { throw LibraryError.unsupportedFormat }
        func decode(url: URL, title: String) async throws -> AudioClip { throw LibraryError.unsupportedFormat }
    }

    private func makeStore() -> LibraryStore {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        return LibraryStore(locations: LibraryLocations(documentsDirectory: root, supportDirectory: root),
                            decoder: RejectingDecoder())
    }

    /// SF-74 : la démo est en tête, sans fichier, et ne peut pas être supprimée.
    func testDemoIsFirstAndProtected_SF74() async throws {
        let store = makeStore()
        let entries = await store.entries
        XCTAssertEqual(entries.first?.id, LibraryEntry.demoID)
        XCTAssertEqual(entries.first?.title, DemoSound.title)
        do {
            try await store.delete(id: LibraryEntry.demoID)
            XCTFail("the demo must not be deletable")
        } catch {
            XCTAssertEqual(error as? LibraryError, .demoCannotBeDeleted)
        }
        do {
            _ = try await store.url(for: LibraryEntry.demoID)
            XCTFail("the demo has no local copy")
        } catch {
            XCTAssertEqual(error as? LibraryError, .notFound)
        }
    }

    func testDemoClipMatchesItsContract_SF76() {
        let clip = DemoSound.makeClip()
        XCTAssertEqual(clip.title, DemoSound.title)
        XCTAssertEqual(clip.sampleRate, DemoSound.sampleRate)
        XCTAssertEqual(clip.duration, DemoSound.duration, accuracy: 1 / DemoSound.sampleRate)
        XCTAssertTrue(clip.left.allSatisfy(\.isFinite))
    }
}
