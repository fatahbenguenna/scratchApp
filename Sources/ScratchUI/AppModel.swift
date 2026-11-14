import Foundation
import Observation
import ScratchAudio
import ScratchCore
import ScratchLibrary

/// Demande de confirmation avant de remplacer le son d'une platine active (SF-15, 6.5).
public struct ReplacementRequest: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let deck: DeckID
    /// Entrée qui serait chargée (déjà dans la bibliothèque : un refus la laisse disponible).
    public let entry: LibraryEntry

    public init(id: UUID = UUID(), deck: DeckID, entry: LibraryEntry) {
        self.id = id
        self.deck = deck
        self.entry = entry
    }
}

/// Demande de confirmation avant de supprimer un son de la bibliothèque (SF-74, 6.13).
public struct DeletionRequest: Equatable, Identifiable, Sendable {
    public var id: UUID { entry.id }
    public let entry: LibraryEntry
    /// Platines sur lesquelles ce son est chargé (affiché dans la confirmation, 6.13).
    public let loadedOn: [DeckID]

    public init(entry: LibraryEntry, loadedOn: [DeckID]) {
        self.entry = entry
        self.loadedOn = loadedOn
    }
}

/// Modèle racine de l'application : compose le moteur, l'hôte audio, la bibliothèque et les
/// préférences, et expose les modèles de présentation (architecture §3, §5.4).
///
/// Fil principal uniquement. `tick()` est appelé une fois par image d'affichage.
///
/// **Squelette partiel (story EP6, Hugo).** `tick()` et la composition sont en place ; les
/// intentions de chargement, d'import et de suppression sont à implémenter.
@MainActor
@Observable
public final class AppModel {
    public let deckA: DeckViewModel
    public let deckB: DeckViewModel
    public let mixer: MixerViewModel

    /// Sons de la bibliothèque, démonstration en tête (SF-74).
    public private(set) var libraryEntries: [LibraryEntry] = []
    /// État de la sortie audio (SF-82 : « Sortie audio indisponible »).
    public private(set) var outputStatus: AudioOutputStatus = .stopped
    /// Dernière erreur à afficher (import, chargement, suppression), effacée par `dismissError()`.
    public private(set) var lastError: LibraryError?
    /// Confirmation de remplacement en attente (SF-15).
    public private(set) var pendingReplacement: ReplacementRequest?
    /// Confirmation de suppression en attente (SF-74).
    public private(set) var pendingDeletion: DeletionRequest?

    public let engine: any EngineControlling
    private let host: (any AudioOutputHosting)?
    private let library: any LibraryStoring
    private let preferences: any PreferencesStoring
    private let decoder: any AudioClipDecoding

    public init(
        engine: any EngineControlling,
        host: (any AudioOutputHosting)?,
        library: any LibraryStoring,
        preferences: any PreferencesStoring,
        decoder: any AudioClipDecoding
    ) {
        self.engine = engine
        self.host = host
        self.library = library
        self.preferences = preferences
        self.decoder = decoder
        self.deckA = DeckViewModel(deck: .a, engine: engine)
        self.deckB = DeckViewModel(deck: .b, engine: engine)
        self.mixer = MixerViewModel(engine: engine)
    }

    public func deck(_ id: DeckID) -> DeckViewModel {
        switch id {
        case .a: return deckA
        case .b: return deckB
        }
    }

    /// Une image d'affichage : applique les commandes si aucun fil audio ne tourne, lit
    /// l'instantané, met à jour les modèles de présentation et libère les clips rendus.
    public func tick() {
        if host?.isRenderingAudio != true { engine.pump() }
        let snapshot = engine.latestSnapshot()
        deckA.apply(snapshot.decks.a)
        deckB.apply(snapshot.decks.b)
        mixer.apply(snapshot.mixer)
        engine.drainReleasedClips()
        if let host, outputStatus != host.status { outputStatus = host.status }
    }

    public func dismissError() { lastError = nil }

    // MARK: Cycle de vie (squelette, story EP6)

    /// Lancement : préférences → moteur (sans lecture, RM-10), bibliothèque, démarrage de la sortie.
    public func launch() async {}

    /// iOS : arrière-plan (SF-81, RM-56).
    public func enterBackground() {}

    /// iOS : retour au premier plan (aucune reprise automatique, RM-10).
    public func enterForeground() {}

    /// Enregistre les préférences à partir de l'instantané courant (SF-17).
    public func savePreferences() {}

    // MARK: Sons (squelette, story EP6)

    /// Charge le son de démonstration sur `deck` (SF-76), selon SF-15.
    public func loadDemo(on deck: DeckID) async {}

    /// Importe `url` (sélecteur de documents ou glisser-déposer) puis le charge sur `deck`
    /// (SF-02, SF-73, SF-75), selon SF-15.
    public func importFile(at url: URL, to deck: DeckID) async {}

    /// Charge une entrée de la bibliothèque sur `deck` (SF-74), selon SF-15.
    public func load(_ entry: LibraryEntry, on deck: DeckID) async {}

    /// Confirme ou refuse le remplacement en attente (SF-15).
    public func confirmReplacement() async {}
    public func cancelReplacement() {}

    /// Demande la suppression d'une entrée (confirmation, 6.13).
    public func requestDeletion(of entry: LibraryEntry) {}
    public func confirmDeletion() async {}
    public func cancelDeletion() {}
}
