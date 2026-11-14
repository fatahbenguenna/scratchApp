import Dispatch
import XCTest
@testable import ScratchCore

final class SnapshotBufferTests: XCTestCase {
    func testReadReturnsInitialThenLatestValue() {
        let buffer = SnapshotBuffer(initialValue: 0)
        XCTAssertFalse(buffer.hasNewValue)
        XCTAssertEqual(buffer.read(), 0)
        buffer.write(1)
        XCTAssertTrue(buffer.hasNewValue)
        XCTAssertEqual(buffer.read(), 1)
        XCTAssertFalse(buffer.hasNewValue)
        XCTAssertEqual(buffer.read(), 1, "a read without a new write returns the same value")
        buffer.write(2)
        buffer.write(3)
        buffer.write(4)
        XCTAssertEqual(buffer.read(), 4, "only the latest value is visible")
    }

    struct Pair: Equatable {
        var first: Int
        var second: Int
        var third: Double
    }

    /// Un écrivain et un lecteur concurrents : jamais de valeur déchirée, valeurs croissantes.
    func testConcurrentReaderNeverSeesTornOrOlderValues() {
        let buffer = SnapshotBuffer(initialValue: Pair(first: 0, second: 0, third: 0))
        let writes = 300_000
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            for value in 1...writes {
                buffer.write(Pair(first: value, second: value * 2, third: Double(value) / 2))
            }
            group.leave()
        }
        var last = 0
        var torn = 0
        var regressions = 0
        while last < writes {
            let value = buffer.read()
            if value.second != value.first * 2 || value.third != Double(value.first) / 2 { torn += 1 }
            if value.first < last { regressions += 1 }
            last = max(last, value.first)
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success)
        XCTAssertEqual(torn, 0)
        XCTAssertEqual(regressions, 0)
        XCTAssertEqual(buffer.read().first, writes)
    }
}
