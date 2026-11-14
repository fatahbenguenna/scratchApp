import Foundation
import XCTest
@testable import ScratchCore

/// Interpolation Hermite 4 points (story 1.3, T1 ; SF-77, RM-09).
final class HermiteInterpolatorTests: XCTestCase {
    private func buffers(_ values: [Float]) -> (left: UnsafeBufferPointer<Float>, right: UnsafeBufferPointer<Float>, release: () -> Void) {
        let left = UnsafeMutableBufferPointer<Float>.allocate(capacity: values.count)
        let right = UnsafeMutableBufferPointer<Float>.allocate(capacity: values.count)
        _ = left.initialize(from: values)
        _ = right.initialize(from: values.map { -$0 })
        return (UnsafeBufferPointer(left), UnsafeBufferPointer(right), { left.deallocate(); right.deallocate() })
    }

    func testIntegerPositionsReturnTheSamples() {
        let values: [Float] = [0.3, -0.7, 0.25, 0.9, -0.1, 0.6]
        let (left, right, release) = buffers(values)
        defer { release() }
        for (index, value) in values.enumerated() {
            let sample = HermiteInterpolator.sample(left: left, right: right, at: Double(index))
            XCTAssertEqual(sample.left, value)
            XCTAssertEqual(sample.right, -value)
        }
    }

    /// Les tangentes centrées sont exactes pour un polynôme de degré 2 : la cubique le reproduit.
    func testReproducesQuadraticsExactly() {
        let values: [Float] = (0..<16).map { (index: Int) -> Float in
            let x = Double(index)
            return Float(0.01 * x * x - 0.1 * x + 0.2)
        }
        let (left, right, release) = buffers(values)
        defer { release() }
        for x in stride(from: 1.0, through: 13.0, by: 0.125) {
            let expected = 0.01 * x * x - 0.1 * x + 0.2
            XCTAssertEqual(Double(HermiteInterpolator.sample(left: left, right: right, at: x).left), expected, accuracy: 1e-6)
        }
    }

    /// RM-09 : les voisins hors du clip valent 0 (silence virtuel) et ne sont jamais lus.
    func testNeighboursOutsideTheClipAreVirtualZeros() {
        let values: [Float] = [1, 1, 1, 1]
        let (left, right, release) = buffers(values)
        defer { release() }
        XCTAssertEqual(HermiteInterpolator.sample(left: left, right: right, at: -0.5).left,
                       HermiteInterpolator.value(0, 0, 1, 1, t: 0.5))
        XCTAssertEqual(HermiteInterpolator.sample(left: left, right: right, at: 3.5).left,
                       HermiteInterpolator.value(1, 1, 0, 0, t: 0.5))
        XCTAssertEqual(HermiteInterpolator.sample(left: left, right: right, at: 0.5).left,
                       HermiteInterpolator.value(0, 1, 1, 1, t: 0.5))
        for x in [-2.0, -5, 5, 4.999_9 + 0.000_2, 1e9, -1e9] {
            XCTAssertEqual(HermiteInterpolator.sample(left: left, right: right, at: x).left, 0, "x = \(x)")
        }
    }

    func testKernelIsSymmetric() {
        // Phase nulle : lire à t et à 1 − t entre des voisins miroirs donne la même valeur.
        for t in stride(from: Float(0), through: 1, by: 0.1) {
            XCTAssertEqual(HermiteInterpolator.value(0.1, 0.5, -0.3, 0.8, t: t),
                           HermiteInterpolator.value(0.8, -0.3, 0.5, 0.1, t: 1 - t), accuracy: 1e-6)
        }
    }
}
