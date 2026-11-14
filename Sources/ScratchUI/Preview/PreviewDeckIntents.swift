import Foundation
import ScratchCore
import ScratchLibrary

/// Double d'aperçu de `DeckIntents` (story 4.1 CA 6) : charge un son synthétique, sans fichier ni
/// décodage, comme le fera l'`AppModel` en 6.1 (`.load`, puis `loadedClip` et `loadedEntry`).
///
/// « Importer » charge un son fictif « voix_funk.wav » de 3 min 45 s ; « Charger la démo » charge le
/// son de démonstration (`DemoSound`). La bibliothèque, les réglages et le Finder sont sans effet.
@MainActor
public final class PreviewDeckIntents: DeckIntents {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public func importFile(on deck: DeckID) {
        load(Self.syntheticClip(title: "voix_funk.wav", duration: 225), origin: .imported, on: deck)
    }

    public func loadDemo(on deck: DeckID) {
        load(DemoSound.makeClip(), origin: .demo, on: deck)
    }

    public func importDroppedFile(_ url: URL, on deck: DeckID) {
        load(Self.syntheticClip(title: url.lastPathComponent, duration: 30), origin: .imported, on: deck)
    }

    public func openLibrary() {}
    public func openSettings() {}
    public func revealLibraryInFinder() {}

    private func load(_ clip: AudioClip, origin: LibraryEntry.Origin, on deck: DeckID) {
        guard model.engine.send(.load(deck, clip)) else { return }
        let entry = origin == .demo
            ? LibraryEntry.demo(title: DemoSound.title, duration: clip.duration)
            : LibraryEntry(contentHash: "", fileName: clip.title, fileSize: 0, title: clip.title,
                           duration: clip.duration, importedAt: Date(), origin: origin)
        let deckModel = model.deck(deck)
        deckModel.loadedClip = clip
        deckModel.loadedEntry = entry
    }

    /// Clip à 100 Hz : le faux moteur ne joue rien, mais les échantillons dessinent une forme d'onde
    /// plausible (attaques toutes les demi-secondes, 4.6).
    nonisolated static func syntheticClip(title: String, duration: Double) -> AudioClip {
        AudioClip(title: title, sampleRate: 100, frameCount: max(1, Int(duration * 100))) { left, right in
            for index in left.indices {
                let time = Double(index) / 100
                let attack = exp(-time.truncatingRemainder(dividingBy: 0.5) / 0.12)
                let level = Float((0.15 + 0.75 * attack) * (0.7 + 0.3 * sin(time * 0.9)))
                let sample = index.isMultiple(of: 2) ? level : -level
                left[index] = sample
                right[index] = sample * 0.9
            }
        }
    }
}
