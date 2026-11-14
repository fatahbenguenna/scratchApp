import Foundation

/// Journal des mesures de décodage (story 2.2 CA 7, #61) : sortie standard, et
/// `ci-output/decode-metrics.log` quand ce dossier existe. Le rapport CI de la PR reprend ce fichier.
enum DecodeMetricsLog {
    /// Build de débogage (évalué à l'exécution).
    static let isDebugBuild: Bool = { _isDebugAssertConfiguration() }()
    static var configuration: String { isDebugBuild ? "debug" : "release" }

    static func write(_ line: String) {
        print(line)
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("ci-output")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { return }
        let file = directory.appendingPathComponent("decode-metrics.log")
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
