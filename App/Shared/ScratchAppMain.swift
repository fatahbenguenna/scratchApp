import SwiftUI
import ScratchAudio
import ScratchUI
#if canImport(AppKit)
import AppKit
#endif

@main
struct ScratchAppMain: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(ScratchAppDelegate.self) private var appDelegate
    #endif

    init() {
        // Mode auto-test hors ligne pour la CI : `ScratchApp --selftest` (sortie JSON, code de retour).
        if CommandLine.arguments.contains("--selftest") {
            Self.runSelfTestAndExit()
        }
    }

    var body: some Scene {
        WindowGroup("ScratchApp") {
            RootView()
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 760)
        #endif
    }

    private static func runSelfTestAndExit() -> Never {
        do {
            let report = try SelfTest.run()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let json = (try? encoder.encode(report)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            print(json)
            exit(report.passed ? 0 : 1)
        } catch {
            FileHandle.standardError.write(Data("Self-test en échec : \(error)\n".utf8))
            exit(2)
        }
    }
}

#if os(macOS)
/// Quitter l'application à la fermeture de la dernière fenêtre (spec v2.0 — SF-81).
final class ScratchAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif
