import Darwin
import Foundation

/// Empreinte mémoire du processus (`phys_footprint`, la mesure du Moniteur d'activité et de
/// `footprint`), en octets ; 0 si le système ne répond pas.
enum MemoryFootprint {
    static func current() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    /// En mégaoctets (10⁶ octets, comme le budget de D-21).
    static func megabytes(_ bytes: UInt64) -> Double { Double(bytes) / 1_000_000 }
    static func megabytes(_ bytes: Int64) -> Double { Double(bytes) / 1_000_000 }

    /// Pic d'empreinte pendant `body`, relevé toutes les 0,5 ms par un fil d'échantillonnage.
    @MainActor
    static func peak<T>(during body: () async throws -> T) async rethrows -> (value: T, peak: UInt64) {
        let sampler = PeakSampler()
        let thread = Thread { sampler.run() }
        thread.start()
        defer { sampler.stop() }
        let value = try await body()
        sampler.stop()
        return (value, sampler.peak)
    }
}

/// Fil qui relève le maximum de l'empreinte jusqu'à `stop()`.
private final class PeakSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var maximum: UInt64 = 0
    private var running = true

    var peak: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return max(maximum, MemoryFootprint.current())
    }

    func stop() {
        lock.lock()
        running = false
        lock.unlock()
    }

    func run() {
        while true {
            let sample = MemoryFootprint.current()
            lock.lock()
            maximum = max(maximum, sample)
            let keepGoing = running
            lock.unlock()
            guard keepGoing else { return }
            usleep(500)
        }
    }
}

/// Mesure publiée dans le rapport de la PR : sortie standard, et `ci-output/render-metrics.log`
/// quand ce dossier existe (le rapport CI reprend ce fichier).
enum MeasurementLog {
    static let isDebugBuild: Bool = { _isDebugAssertConfiguration() }()
    static var configuration: String { isDebugBuild ? "debug" : "release" }

    static func write(_ line: String) {
        print(line)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("ci-output")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        let file = directory.appendingPathComponent("render-metrics.log")
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
    }
}
