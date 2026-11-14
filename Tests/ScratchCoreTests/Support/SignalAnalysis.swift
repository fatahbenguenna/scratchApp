import Foundation

/// Outils d'analyse des signaux de test (story 1.3, T5 ; réutilisés par 1.4 et 1.5).
///
/// Convention des niveaux : dBFS rapportés à une sinusoïde pleine échelle (AES17) : une sinusoïde
/// d'amplitude 1 vaut 0 dBFS, une valeur efficace `rms` vaut `20 log10(rms × √2)` dBFS.
enum SignalAnalysis {
    /// Plancher des niveaux en dB (signal nul).
    static let floorDB = -400.0

    static func rms<C: Collection>(_ samples: C) -> Double where C.Element == Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        return (sum / Double(samples.count)).squareRoot()
    }

    static func peak<C: Collection>(_ samples: C) -> Double where C.Element == Float {
        samples.reduce(0.0) { max($0, abs(Double($1))) }
    }

    /// Niveau efficace en dBFS (sinusoïde pleine échelle = 0 dBFS).
    static func levelDBFS<C: Collection>(_ samples: C) -> Double where C.Element == Float {
        decibels(rms(samples) * 2.0.squareRoot())
    }

    /// Crête en dBFS.
    static func peakDBFS<C: Collection>(_ samples: C) -> Double where C.Element == Float {
        decibels(peak(samples))
    }

    static func decibels(_ ratio: Double) -> Double {
        ratio > 0 ? 20 * log10(ratio) : floorDB
    }

    /// Plus grande différence entre deux échantillons consécutifs (détecteur de clic).
    static func maximumStep<C: Collection>(_ samples: C) -> Double where C.Element == Float {
        var largest = 0.0
        var previous: Float?
        for sample in samples {
            if let previous { largest = max(largest, abs(Double(sample) - Double(previous))) }
            previous = sample
        }
        return largest
    }

    static func containsNonFinite<C: Collection>(_ samples: C) -> Bool where C.Element == Float {
        samples.contains { !$0.isFinite }
    }

    // MARK: Spectre

    /// Fenêtre de Blackman de `count` points.
    static func blackman(_ count: Int) -> [Double] {
        guard count > 1 else { return [1] }
        return (0..<count).map { n in
            let x = 2 * Double.pi * Double(n) / Double(count - 1)
            return 0.42 - 0.5 * cos(x) + 0.08 * cos(2 * x)
        }
    }

    /// Amplitude d'une composante de fréquence `frequency` (DFT fenêtrée de Blackman en un point) :
    /// une sinusoïde d'amplitude A à cette fréquence donne A.
    static func toneAmplitude(_ samples: [Float], frequency: Double, sampleRate: Double) -> Double {
        let window = blackman(samples.count)
        let omega = 2 * Double.pi * frequency / sampleRate
        var real = 0.0
        var imaginary = 0.0
        var windowSum = 0.0
        for (n, sample) in samples.enumerated() {
            let w = window[n] * Double(sample)
            real += w * cos(omega * Double(n))
            imaginary -= w * sin(omega * Double(n))
            windowSum += window[n]
        }
        return 2 * (real * real + imaginary * imaginary).squareRoot() / windowSum
    }

    /// Niveau (dBFS, convention sinusoïde) du contenu au-delà de `frequency`, par FFT fenêtrée de
    /// Blackman sur les 2^k premiers échantillons (Parseval, normalisé par l'énergie de la fenêtre).
    static func levelAbove(_ frequency: Double, in samples: [Float], sampleRate: Double) -> Double {
        var size = 1
        while size * 2 <= samples.count { size *= 2 }
        let window = blackman(size)
        var real = (0..<size).map { Double(samples[$0]) * window[$0] }
        var imaginary = [Double](repeating: 0, count: size)
        fft(&real, &imaginary)
        let windowEnergy = window.reduce(0) { $0 + $1 * $1 }
        let firstBin = Int((frequency / sampleRate * Double(size)).rounded(.up))
        var power = 0.0
        if firstBin < size / 2 {
            for k in firstBin..<(size / 2) { power += 2 * (real[k] * real[k] + imaginary[k] * imaginary[k]) }
        }
        let meanSquare = power / (Double(size) * windowEnergy)
        return decibels((meanSquare * 2).squareRoot())
    }

    /// FFT complexe en place, radix 2 (taille puissance de 2).
    static func fft(_ real: inout [Double], _ imaginary: inout [Double]) {
        let n = real.count
        precondition(n > 0 && n & (n - 1) == 0 && imaginary.count == n, "FFT size must be a power of two")
        var j = 0
        for i in 1..<n {
            var bit = n >> 1
            while j & bit != 0 {
                j ^= bit
                bit >>= 1
            }
            j |= bit
            if i < j {
                real.swapAt(i, j)
                imaginary.swapAt(i, j)
            }
        }
        var length = 2
        while length <= n {
            let angle = -2 * Double.pi / Double(length)
            let stepReal = cos(angle)
            let stepImaginary = sin(angle)
            var start = 0
            while start < n {
                var wReal = 1.0
                var wImaginary = 0.0
                for k in 0..<(length / 2) {
                    let a = start + k
                    let b = a + length / 2
                    let tReal = real[b] * wReal - imaginary[b] * wImaginary
                    let tImaginary = real[b] * wImaginary + imaginary[b] * wReal
                    real[b] = real[a] - tReal
                    imaginary[b] = imaginary[a] - tImaginary
                    real[a] += tReal
                    imaginary[a] += tImaginary
                    let nextReal = wReal * stepReal - wImaginary * stepImaginary
                    wImaginary = wReal * stepImaginary + wImaginary * stepReal
                    wReal = nextReal
                }
                start += length
            }
            length <<= 1
        }
    }

    // MARK: Fréquence

    /// Fréquence d'un signal périodique par comptage des passages par zéro montants, instants
    /// interpolés linéairement (précision ≪ 0,1 % sur une seconde de sinusoïde pure).
    static func zeroCrossingFrequency(_ samples: [Float], sampleRate: Double) -> Double {
        var crossings = [Double]()
        for n in 1..<samples.count where samples[n - 1] < 0 && samples[n] >= 0 {
            let a = Double(samples[n - 1])
            let b = Double(samples[n])
            crossings.append(Double(n - 1) + a / (a - b))
        }
        guard let first = crossings.first, let last = crossings.last, crossings.count > 1 else { return 0 }
        return Double(crossings.count - 1) / ((last - first) / sampleRate)
    }
}
