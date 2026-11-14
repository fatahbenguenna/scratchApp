import SwiftUI
import ScratchAudio
import ScratchCore
import ScratchLibrary
import ScratchUI
#if canImport(AppKit)
import AppKit
#endif

@main
struct ScratchAppMain: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(ScratchAppDelegate.self) private var appDelegate
    #endif

    private let model: AppModel

    init() {
        // Mode auto-test hors ligne pour la CI : `ScratchApp --selftest` (sortie JSON, code de retour).
        if CommandLine.arguments.contains("--selftest") {
            Self.runSelfTestAndExit()
        }
        model = Self.makeModel()
    }

    var body: some Scene {
        WindowGroup("ScratchApp") {
            AppRootView(model: model)
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 760)
        #endif
    }

    /// Composition réelle (story 6.1 CA 1 ; architecture §2.3) : moteur, hôte audio, bibliothèque dans
    /// le bac à sable de l'app, décodeur AVFoundation, préférences, et issue de la lecture de l'index
    /// (D-49).
    ///
    /// L'hôte audio n'est pas encore démarré : son cycle de vie (démarrage, arrière-plan, veille)
    /// relève de la story 6.2, qui attend le correctif #57 (D-52). D'ici là, `AppModel.tick()` pompe
    /// le moteur à chaque image, et aucun `DisplayWakingEngine` n'est branché sur un moteur rendu
    /// par un hôte.
    @MainActor
    private static func makeModel() -> AppModel {
        let engine = ScratchEngine()
        let host = AudioEngineHost(engine: engine)
        let decoder = AudioFileDecoder()
        let locations = libraryLocations()
        let library = LibraryStore(locations: locations, decoder: decoder)
        return AppModel(engine: engine, host: host, library: library, preferences: UserDefaultsPreferencesStore(),
                        decoder: decoder, indexRecovery: { await library.indexRecovery },
                        libraryFolder: locations.soundBankDirectory)
    }

    /// Emplacements standard ; en cas d'échec du système, un dossier temporaire garde l'app utilisable
    /// (bibliothèque non persistante, signalée dans la console).
    private static func libraryLocations() -> LibraryLocations {
        do {
            return try LibraryLocations.standard()
        } catch {
            FileHandle.standardError.write(Data("Bibliothèque : emplacements standard indisponibles (\(error)).\n".utf8))
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("ScratchApp", isDirectory: true)
            return LibraryLocations(documentsDirectory: root.appendingPathComponent("Documents", isDirectory: true),
                                    supportDirectory: root.appendingPathComponent("Support", isDirectory: true))
        }
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
