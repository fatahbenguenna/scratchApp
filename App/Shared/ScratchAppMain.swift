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
    #if os(macOS)
    /// Clavier de la fenêtre principale, partagé par `RootView` et les menus (story 5.1) : un seul.
    private let keyboard: KeyboardController
    #endif

    init() {
        // Mode auto-test hors ligne pour la CI : `ScratchApp --selftest` (sortie JSON, code de retour).
        if CommandLine.arguments.contains("--selftest") {
            Self.runSelfTestAndExit()
        }
        let model = Self.makeModel(launchOptions: Self.launchOptions())
        self.model = model
        #if os(macOS)
        keyboard = KeyboardController(model: model)
        // Quitting right after a settings change must not lose it (#97).
        _ = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                   queue: .main) { [model] _ in
            MainActor.assumeIsolated { model.willTerminate() }
        }
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        // Une seule fenêtre principale, sans « Nouvelle fenêtre » ; sa zone de contenu mesure au moins
        // 960 × 600 points et sa fermeture quitte l'app (D-38).
        Window("ScratchApp", id: "main") {
            AppRootView(model: model, keyboard: keyboard)
        }
        .defaultSize(width: 1200, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            ScratchCommands(model: model, intents: model, keyboard: keyboard)
        }

        // Réglages (⌘,), un seul panneau (3.4, UX §5.20).
        Settings {
            SettingsView(model: model)
        }

        // Aide des raccourcis (5.1), ouverte par le menu Aide et par les Réglages : touches de la
        // disposition active, celles du contrôleur clavier.
        KeyboardHelpWindow(names: keyboard.names)
        #else
        WindowGroup("ScratchApp") {
            AppRootView(model: model)
        }
        #endif
    }

    /// Composition réelle (stories 6.1 CA 1 et 6.2 CA 1 ; architecture §2.3) : moteur, hôte audio,
    /// bibliothèque dans le bac à sable de l'app, décodeur AVFoundation, préférences, et issue de la
    /// lecture de l'index (D-49).
    ///
    /// L'`AppModel` reçoit le moteur derrière un `DisplayWakingEngine` : chaque commande réveille la
    /// boucle d'affichage, qui se suspend au repos (le correctif #57 est fusionné, D-52). L'hôte rend
    /// le vrai moteur ; il démarre à la fin de `AppModel.launch()`.
    @MainActor
    private static func makeModel(launchOptions: LaunchOptions) -> AppModel {
        let engine = ScratchEngine()
        let host = AudioEngineHost(engine: engine)
        let decoder = AudioFileDecoder()
        let locations = libraryLocations()
        let library = LibraryStore(locations: locations, decoder: decoder)
        return AppModel(engine: DisplayWakingEngine(wrapping: engine), host: host, library: library,
                        preferences: UserDefaultsPreferencesStore(), decoder: decoder,
                        indexRecovery: { await library.indexRecovery },
                        libraryFolder: locations.soundBankDirectory, launchOptions: launchOptions)
    }

    /// Arguments de lancement. `--demo-scene` (capture de la CI) n'est lu que dans les builds Debug :
    /// une app publiée ne charge ni ne joue jamais rien d'elle-même (RM-01, RM-10).
    private static func launchOptions() -> LaunchOptions {
        #if DEBUG
        return LaunchOptions(arguments: CommandLine.arguments)
        #else
        return LaunchOptions()
        #endif
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
/// Quitter l'application à la fermeture de la dernière fenêtre (spec v2.0 — SF-81). La fermeture de
/// la fenêtre principale quitte aussi l'app quand une autre fenêtre reste ouverte (`AppRootView`).
final class ScratchAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#endif
