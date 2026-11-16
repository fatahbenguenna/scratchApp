import Foundation
#if canImport(Accelerate)
import Accelerate
#endif

/// Analyse des pics d'un son (story 4.6 CA 1 ; NFR4), hors du fil principal.
///
/// Un point par bloc de `sampleRate / 300` trames (≈ 300 points par seconde) : minimum et maximum
/// des deux canaux. Les extrema d'un bloc passent par Accelerate (`vDSP_minv`, `vDSP_maxv`) ; une
/// boucle simple prend le relais sans Accelerate (validation de la logique sous Linux).
/// 10 min de son analysées en moins d'une seconde sur Mac Apple Silicon (build release).
enum WaveformAnalyzer {
    static let targetPointsPerSecond = 300.0

    /// Échantillons à analyser : les canaux d'un `AudioClip`, lus sans copie. Le cache garde le clip
    /// en vie jusqu'à la fin de l'analyse (`WaveformCache`).
    struct Samples: @unchecked Sendable {
        let left: UnsafeBufferPointer<Float>
        let right: UnsafeBufferPointer<Float>
        let sampleRate: Double
    }

    /// Trames par point : 147 à 44,1 kHz, 160 à 48 kHz.
    static func blockSize(sampleRate: Double) -> Int {
        max(1, Int((sampleRate / targetPointsPerSecond).rounded()))
    }

    /// Pics du son, ou `nil` si l'analyse est annulée (`isCancelled`, consulté régulièrement) ou si
    /// le son est vide.
    static func analyze(_ samples: Samples, isCancelled: () -> Bool = { false }) -> WaveformPeaks? {
        let frames = min(samples.left.count, samples.right.count)
        guard frames > 0, samples.sampleRate > 0, samples.sampleRate.isFinite,
              let left = samples.left.baseAddress, let right = samples.right.baseAddress else { return nil }
        let block = blockSize(sampleRate: samples.sampleRate)
        let count = (frames + block - 1) / block
        var minimums = [Int16](repeating: 0, count: count)
        var maximums = [Int16](repeating: 0, count: count)
        let completed = minimums.withUnsafeMutableBufferPointer { lows in
            maximums.withUnsafeMutableBufferPointer { highs in
                for index in 0..<count {
                    if index & 2047 == 0, isCancelled() { return false }
                    let start = index * block
                    let range = extrema(left + start, right + start, count: min(block, frames - start))
                    lows[index] = WaveformPeaks.quantize(range.min)
                    highs[index] = WaveformPeaks.quantize(range.max)
                }
                return true
            }
        }
        guard completed, !isCancelled() else { return nil }
        return WaveformPeaks(pointsPerSecond: samples.sampleRate / Double(block),
                             duration: Double(frames) / samples.sampleRate,
                             minimums: minimums, maximums: maximums)
    }

    /// Minimum et maximum de `count` échantillons des deux canaux.
    static func extrema(_ left: UnsafePointer<Float>, _ right: UnsafePointer<Float>, count: Int)
        -> (min: Float, max: Float) {
        #if canImport(Accelerate)
        var leftMin: Float = 0, leftMax: Float = 0, rightMin: Float = 0, rightMax: Float = 0
        let length = vDSP_Length(count)
        vDSP_minv(left, 1, &leftMin, length)
        vDSP_maxv(left, 1, &leftMax, length)
        vDSP_minv(right, 1, &rightMin, length)
        vDSP_maxv(right, 1, &rightMax, length)
        return (min(leftMin, rightMin), max(leftMax, rightMax))
        #else
        var low = Float.infinity
        var high = -Float.infinity
        for offset in 0..<count {
            let l = left[offset], r = right[offset]
            low = min(low, min(l, r))
            high = max(high, max(l, r))
        }
        return (low, high)
        #endif
    }
}
