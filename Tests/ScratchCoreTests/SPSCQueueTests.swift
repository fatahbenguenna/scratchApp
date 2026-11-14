import Dispatch
import XCTest
@testable import ScratchCore

final class SPSCQueueTests: XCTestCase {
    func testCapacityIsRoundedUpToAPowerOfTwo() {
        XCTAssertEqual(SPSCQueue<Int>(minimumCapacity: 1).capacity, 2)
        XCTAssertEqual(SPSCQueue<Int>(minimumCapacity: 5).capacity, 8)
        XCTAssertEqual(SPSCQueue<Int>(minimumCapacity: 1024).capacity, 1024)
    }

    func testFIFOOrderFullAndEmpty() {
        let queue = SPSCQueue<Int>(minimumCapacity: 4)
        XCTAssertNil(queue.pop())
        XCTAssertTrue(queue.isEmpty)
        for value in 1...4 { XCTAssertTrue(queue.push(value)) }
        XCTAssertFalse(queue.push(5), "a full queue rejects the element")
        XCTAssertEqual(queue.availableCapacity, 0)
        XCTAssertEqual(queue.approximateCount, 4)
        XCTAssertEqual(queue.pop(), 1)
        XCTAssertTrue(queue.push(5))
        XCTAssertEqual([queue.pop(), queue.pop(), queue.pop(), queue.pop()], [2, 3, 4, 5])
        XCTAssertNil(queue.pop())
        XCTAssertEqual(queue.availableCapacity, 4)
    }

    func testWrapAroundManyTimes() {
        let queue = SPSCQueue<Int>(minimumCapacity: 8)
        var expected = 0
        for value in 0..<10_000 {
            XCTAssertTrue(queue.push(value))
            if value % 3 == 2 {
                while let popped = queue.pop() {
                    XCTAssertEqual(popped, expected)
                    expected += 1
                }
            }
        }
        while let popped = queue.pop() {
            XCTAssertEqual(popped, expected)
            expected += 1
        }
        XCTAssertEqual(expected, 10_000)
    }

    func testRemainingNonTrivialElementsAreReleasedOnDeinit() {
        final class Token {}
        weak var weakToken: Token?
        do {
            let queue = SPSCQueue<Token>(minimumCapacity: 4)
            let token = Token()
            weakToken = token
            queue.push(token)
        }
        XCTAssertNil(weakToken)
    }

    /// Un producteur et un consommateur sur deux fils : ordre conservé, rien de perdu ni dupliqué.
    func testConcurrentProducerConsumerPreservesOrder() {
        let queue = SPSCQueue<Int>(minimumCapacity: 64)
        let total = 200_000
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            var next = 0
            while next < total {
                if queue.push(next) { next += 1 }
            }
            group.leave()
        }
        // Consumer on the test thread.
        var received = [Int]()
        received.reserveCapacity(total)
        while received.count < total {
            if let value = queue.pop() { received.append(value) }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 30), .success)
        XCTAssertEqual(received.count, total)
        XCTAssertEqual(received, Array(0..<total))
    }
}
