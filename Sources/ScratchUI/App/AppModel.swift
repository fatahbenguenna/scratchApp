import Foundation
import Observation
import ScratchAudio
import ScratchCore
import ScratchLibrary

/// Modèle racine de l'application : compose le moteur, l'hôte audio, la bibliothèque, le décodeur et
/// les préférences par leurs protocoles, et expose les modèles de présentation (PRD 6.1 critère 1 ;
/// architecture §2.3, §5.2).
///
/// Fil principal uniquement. `tick()` est appelé une fois par image d'affichage.
///
/// **Squelette (story 6.1, Hugo).** La composition et `tick()` sont en place. Le parcours de
/// chargement, les confirmations (SF-15, SF-74), les erreurs et le cycle de vie sont à ajouter en 6.1
/// et 6.2 ; les intentions de l'interface implémentent le protocole défini par Léa en 4.1.
@MainActor
@Observable
public final class AppModel {
    public let deckA: DeckViewModel
    public let deckB: DeckViewModel
    public let mixer: MixerViewModel

    /// État de la sortie audio (SF-16, SF-82 : nom, état, fréquence, tampon effectif).
    public private(set) var outputStatus: AudioOutputStatus = .stopped

    public let engine: any EngineControlling
    public let host: (any AudioOutputHosting)?
    public let library: any LibraryStoring
    public let preferences: any PreferencesStoring
    public let decoder: any AudioDecoding

    public init(
        engine: any EngineControlling,
        host: (any AudioOutputHosting)?,
        library: any LibraryStoring,
        preferences: any PreferencesStoring,
        decoder: any AudioDecoding
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

    /// Une image d'affichage : applique les commandes si aucun fil ne rend (pas d'hôte, hôte arrêté
    /// ou suspendu), lit l'instantané, met à jour les modèles de présentation et libère les clips
    /// rendus par le moteur.
    public func tick() {
        if host?.isRenderingAudio != true { engine.pump() }
        let snapshot = engine.latestSnapshot()
        deckA.apply(snapshot.decks.a)
        deckB.apply(snapshot.decks.b)
        mixer.apply(snapshot.mixer)
        engine.drainReleasedClips()
        if let host, outputStatus != host.status { outputStatus = host.status }
    }
}
