import XCTest
@testable import ScratchCore

final class AudioClipTests: XCTestCase {
    func testStereoClipKeepsChannelsAndComputesDuration() {
        let clip = AudioClip(title: "boucle", sampleRate: 44_100, left: [0.1, 0.2, 0.3], right: [-0.1, -0.2, -0.3])
        XCTAssertEqual(clip.title, "boucle")
        XCTAssertEqual(clip.frameCount, 3)
        XCTAssertEqual(clip.duration, 3.0 / 44_100, accuracy: 1e-15)
        XCTAssertEqual(Array(clip.left), [0.1, 0.2, 0.3])
        XCTAssertEqual(Array(clip.right), [-0.1, -0.2, -0.3])
    }

    /// SF-80 : le mono est dupliqué sur les deux canaux.
    func testMonoIsDuplicatedOnBothChannels_SF80() {
        let clip = AudioClip(title: "mono", sampleRate: 48_000, mono: [0.5, -0.5])
        XCTAssertEqual(Array(clip.left), Array(clip.right))
    }

    func testIdentifiersAreUniqueAndIncreasing() {
        let first = AudioClip(title: "a", sampleRate: 48_000, mono: [0])
        let second = AudioClip(title: "b", sampleRate: 48_000, mono: [0])
        XCTAssertLessThan(first.id, second.id)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first, first)
    }

    func testFillInitializerWritesInPlaceAndCleansUpOnError() throws {
        struct Failure: Error {}
        let clip = AudioClip(title: "rampe", sampleRate: 48_000, frameCount: 4) { left, right in
            for index in 0..<4 {
                left[index] = Float(index)
                right[index] = -Float(index)
            }
        }
        XCTAssertEqual(Array(clip.left), [0, 1, 2, 3])
        XCTAssertEqual(Array(clip.right), [0, -1, -2, -3])
        XCTAssertThrowsError(try AudioClip(title: "échec", sampleRate: 48_000, frameCount: 4) { _, _ in throw Failure() })
    }

    func testBuffersAreStableForTheLifetimeOfTheClip() {
        let clip = AudioClip(title: "stable", sampleRate: 48_000, mono: [1, 2, 3])
        let address = clip.left.baseAddress
        _ = clip.duration
        XCTAssertEqual(clip.left.baseAddress, address)
        XCTAssertEqual(clip.right.baseAddress, clip.left.baseAddress.map { $0 + 3 })
    }
}
