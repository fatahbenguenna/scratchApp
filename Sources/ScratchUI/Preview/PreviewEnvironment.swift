import Foundation
import ScratchAudio
import ScratchCore
import ScratchLibrary

/// Environnement d'aperçu : faux moteur (derrière le relais de réveil), `AppModel` sans hôte audio,
/// bibliothèque factice, préférences en mémoire et `PreviewDeckIntents` (story 4.1 CA 8).
///
/// Utilisé par `RootView()` jusqu'à ce que 6.1 injecte le vrai modèle, et par les aperçus SwiftUI.
@MainActor
struct PreviewEnvironment {
    enum Scenario {
        /// Premier lancement : platines vides, moteurs arrêtés (6.1 « Premier lancement sans fichier »).
        case empty
        /// Démo sur A en lecture, son fictif sur B à l'arrêt, platine B en cours d'import.
        case playing
    }

    let engine: FakeEngine
    let model: AppModel
    let intents: PreviewDeckIntents

    init(scenario: Scenario = .empty) {
        engine = FakeEngine()
        model = AppModel(engine: DisplayWakingEngine(wrapping: engine), host: nil, library: PreviewLibrary(),
                         preferences: InMemoryPreferencesStore(), decoder: AudioFileDecoder())
        intents = PreviewDeckIntents(model: model)
        if scenario == .playing {
            intents.loadDemo(on: .a)
            intents.importFile(on: .b)
            model.tick()
            model.deckA.setMotor(true)
            model.deckB.activity = .importing(fileName: "beat_90.wav")
        }
        model.tick()
    }
}

/// Bibliothèque factice : le son de démonstration seul, aucun import.
private struct PreviewLibrary: LibraryStoring {
    var entries: [LibraryEntry] {
        get async { [LibraryEntry.demo(title: DemoSound.title, duration: DemoSound.duration)] }
    }

    func importFile(at url: URL) async throws -> ImportResult { throw LibraryError.unsupportedFormat }
    func delete(id: UUID) async throws { throw LibraryError.demoCannotBeDeleted }
    func url(for id: UUID) async throws -> URL { throw LibraryError.notFound }
}
