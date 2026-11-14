import Foundation
import Observation
#if os(macOS)
import AppKit
#endif
import ScratchAudio
import ScratchCore
import ScratchLibrary

/// Modèle racine de l'application. Il compose le moteur, l'hôte audio, la bibliothèque, le décodeur
/// et les préférences par leurs protocoles, et expose les modèles de présentation (PRD 6.1 ;
/// architecture §2.3, §4.1, §5.2). Il implémente les intentions de l'interface (`DeckIntents`, 4.1).
///
/// **Parcours de chargement** (story 6.1, architecture §4.1) :
/// 1. import : accès à portée de sécurité ouvert seulement pendant la copie, puis
///    `library.importFile(at:)` ;
/// 2. règle de remplacement (SF-15, D-40). Elle est évaluée à la fin de la copie : une platine
///    chargée et active demande une confirmation ; une platine à l'arrêt ou vide est remplacée
///    directement ;
/// 3. `library.url(for:)` puis décodage dans une tâche détachée, ou clip de démonstration en cache,
///    partagé par A et B (RM-57) ;
/// 4. `send(.load)`, puis `loadedEntry` et `loadedClip`.
///
/// Toute erreur affiche l'alerte française de l'UX §8.3, n'envoie aucune commande et laisse la
/// platine intacte (RM-48). Au lancement, `launch()` réconcilie la bibliothèque et affiche un bandeau
/// (D-11, D-49).
///
/// Fil principal uniquement. `tick()` est appelé une fois par image d'affichage. Le cycle de vie
/// (préférences, arrière-plan, hôte audio) relève de 3.4 et de 6.2.
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

    /// Bandeau courant (UX §5.21, §8.5).
    public let toasts: ToastCenter
    /// Entrées de la bibliothèque, démo en tête, mises à jour après chaque import, chaque retrait et
    /// au lancement (3.5).
    public private(set) var libraryEntries: [LibraryEntry] = []
    /// Sélecteur de fichiers présenté (lié à `fileImporter`).
    public var isImportPickerPresented = false
    /// Platine pour laquelle le sélecteur est ouvert (« Importer sur la platine A »).
    public private(set) var importPickerDeck: DeckID?
    /// Erreurs en attente ; la première est affichée (`alert`).
    public private(set) var alerts: [AppAlert] = []
    /// Confirmations de remplacement en attente ; la première est affichée (`confirmation`).
    public private(set) var confirmations: [ReplacementConfirmation] = []
    /// Feuille Bibliothèque présentée (3.5 ; ⌘L, bouton « Bibliothèque »).
    public var isLibraryPresented = false
    /// Confirmation de suppression affichée (3.5, UX §8.4).
    public private(set) var deletionConfirmation: DeletionConfirmation?
    /// Dossier `Documents/Banque de sons`, ouvert par « Afficher la bibliothèque dans le Finder ».
    public let libraryFolder: URL?

    private let indexRecovery: @Sendable () async -> LibraryIndexRecovery
    @ObservationIgnored private var hasLaunched = false
    @ObservationIgnored private var demoClipTask: Task<AudioClip, Never>?

    /// Durées du moteur et rattrapage de la feutrine affichés par l'écran Réglages (3.4) : valeur
    /// commandée tant que l'instantané ne la confirme pas (#57).
    public private(set) var motorTimings = MotorTimings.defaults
    /// Écran Réglages présenté (iOS : feuille ; Mac : fenêtre Réglages ouverte par la vue).
    public var isSettingsPresented = false
    @ObservationIgnored var commandedTimings = CommandedValue<MotorTimings>()
    @ObservationIgnored var preferencesTracker = PreferencesTracker()
    @ObservationIgnored var pendingPreferences: AppPreferences?
    @ObservationIgnored var preferencesSaveTask: Task<Void, Never>?
    /// Délai de regroupement des écritures de préférences (0,5 s ; réduit par les tests).
    @ObservationIgnored var preferencesSaveDelay = 0.5
    /// Horloge monotone, en secondes (injectable par les tests).
    @ObservationIgnored var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }

    /// - Parameters:
    ///   - indexRecovery: issue de la lecture de l'index au lancement (D-49). `ScratchAppMain` la lit
    ///     sur `LibraryStore` ; les doubles de test la fournissent directement.
    ///   - libraryFolder: dossier des copies, ouvert dans le Finder (3.5, Mac).
    public init(
        engine: any EngineControlling,
        host: (any AudioOutputHosting)?,
        library: any LibraryStoring,
        preferences: any PreferencesStoring,
        decoder: any AudioDecoding,
        indexRecovery: @escaping @Sendable () async -> LibraryIndexRecovery = { .none },
        libraryFolder: URL? = nil
    ) {
        self.libraryFolder = libraryFolder
        self.engine = engine
        self.host = host
        self.library = library
        self.preferences = preferences
        self.decoder = decoder
        self.indexRecovery = indexRecovery
        self.toasts = ToastCenter()
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

    /// Erreur affichée (UX §8.3).
    public var alert: AppAlert? { alerts.first }
    /// Confirmation affichée (UX §8.4).
    public var confirmation: ReplacementConfirmation? { confirmations.first }

    /// Une image d'affichage : applique les commandes si aucun fil ne rend (pas d'hôte, hôte arrêté
    /// ou suspendu), lit l'instantané, met à jour les modèles de présentation et libère les clips
    /// rendus par le moteur.
    public func tick() {
        if host?.isRenderingAudio != true { engine.pump() }
        let snapshot = engine.latestSnapshot()
        deckA.apply(snapshot.decks.a)
        deckB.apply(snapshot.decks.b)
        mixer.apply(snapshot.mixer)
        let timings = commandedTimings.resolve(snapshot.motorTimings, at: clock())
        if motorTimings != timings { motorTimings = timings }
        trackPreferences(in: snapshot)
        engine.drainReleasedClips()
        if let host, outputStatus != host.status { outputStatus = host.status }
    }

    // MARK: - Lancement (CA 5, CA 10)

    /// Au premier appel : préférences appliquées au moteur, sans lecture (3.4, RM-10), purge des
    /// copies de dépôts interrompus (5.2), lecture de l'index, réconciliation (D-11), liste à jour et
    /// bandeau unique. Un index illisible ou partiellement illisible prime sur les entrées retirées
    /// (D-49).
    public func launch() async {
        guard !hasLaunched else { return }
        hasLaunched = true
        applyPreferences()
        DroppedFileLoader.purgeStaging()
        let recovery = await indexRecovery()
        let removed = await library.reconcile()
        await refreshLibrary()
        if let text = BannerText.launch(recovery: recovery, removed: removed) { toasts.show(text) }
    }

    /// Relit la liste de la bibliothèque.
    public func refreshLibrary() async {
        libraryEntries = await library.entries
    }

    // MARK: - Import (CA 2 à 5)

    /// Sélecteur fermé avec un fichier choisi, ou en échec. L'annulation ne change rien (CA 4).
    @discardableResult
    public func finishImportPicking(_ result: Result<URL, any Error>) -> Task<Void, Never>? {
        isImportPickerPresented = false
        guard let deck = importPickerDeck else { return nil }
        importPickerDeck = nil
        switch result {
        case let .success(url):
            return Task { await self.importAndLoad(url, on: deck) }
        case let .failure(error):
            if (error as? CocoaError)?.code != .userCancelled { alerts.append(.pickerFailure) }
            return nil
        }
    }

    /// Sélecteur annulé : rien ne change (6.1 « Annuler l'importation »).
    public func cancelImportPicking() {
        isImportPickerPresented = false
        importPickerDeck = nil
    }

    /// Importe `url` dans la bibliothèque, puis le charge sur `deck` (SF-02, SF-03, SF-75). Sans effet
    /// si la platine importe ou charge déjà un son (« Importer » est alors désactivé).
    public func importAndLoad(_ url: URL, on deck: DeckID) async {
        let model = self.deck(deck)
        guard model.activity == .idle else { return }
        let name = url.lastPathComponent
        model.activity = .importing(fileName: name)
        let result: ImportResult
        do {
            result = try await Self.copy(url, into: library)
        } catch {
            model.activity = .idle
            report(error, name: name)
            return
        }
        model.activity = .idle
        await refreshLibrary()
        await requestLoad(result.entry, on: deck, reason: result.isNew ? .imported : .duplicate)
    }

    /// Accès à portée de sécurité ouvert seulement pendant la copie (SF-02, architecture §8 règle 1).
    private nonisolated static func copy(_ url: URL, into library: any LibraryStoring) async throws -> ImportResult {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try await library.importFile(at: url)
    }

    /// Fichier déposé (5.2) : importé puis chargé comme un fichier choisi. La copie temporaire d'un
    /// dépôt depuis Fichiers (iPad) est supprimée ensuite ; un fichier du Finder n'est jamais touché.
    public func importDroppedFileAndWait(_ url: URL, on deck: DeckID) async {
        await importAndLoad(url, on: deck)
        DroppedFileLoader.removeStaged(url)
    }

    // MARK: - Chargement (CA 3, 5, 6, 7, 8)

    /// Charge `entry` sur `deck` selon les règles de remplacement (SF-15, D-40) : utilisé par
    /// l'écran Bibliothèque (3.5) et le glisser-déposer (5.2).
    public func load(_ entry: LibraryEntry, on deck: DeckID) async {
        guard self.deck(deck).activity == .idle else { return }
        await requestLoad(entry, on: deck, reason: entry.origin == .demo ? .demo : .library)
    }

    /// « Charger sur A » ou « Charger sur B » depuis l'écran Bibliothèque (3.5) : mêmes règles que
    /// `load(_:on:)`. La feuille se ferme une fois le son chargé ; elle reste ouverte après un refus
    /// de remplacement ou une erreur.
    public func loadFromLibrary(_ entry: LibraryEntry, on deck: DeckID) async {
        guard self.deck(deck).activity == .idle else { return }
        await requestLoad(entry, on: deck, reason: entry.origin == .demo ? .demo : .library, closesLibrary: true)
    }

    /// « Charger la démo » (SF-76) : son de démonstration chargé sans lecture, selon les mêmes règles.
    public func loadDemoAndWait(on deck: DeckID) async {
        await load(LibraryEntry.demo(title: DemoSound.title, duration: DemoSound.duration), on: deck)
    }

    /// Vide la platine (suppression d'un son chargé, 3.5).
    public func unload(_ deck: DeckID) {
        guard engine.send(.unload(deck)) else { return }
        let model = self.deck(deck)
        model.loadedEntry = nil
        model.loadedClip = nil
    }

    /// Platines qui portent l'entrée `entryID` (RM-57 : les deux à la fois possible).
    public func decks(carrying entryID: UUID) -> [DeckID] {
        DeckID.allCases.filter { deck($0).loadedEntry?.id == entryID }
    }

    /// Réponse à la confirmation affichée. Le chargement éventuel est rendu sous forme de tâche
    /// (attendue par les tests).
    @discardableResult
    public func resolveConfirmation(replace: Bool) -> Task<Void, Never>? {
        guard let confirmation = confirmations.first else { return nil }
        confirmations.removeFirst()
        if replace {
            return Task {
                await self.performLoad(confirmation.entry, on: confirmation.deck, reason: confirmation.reason,
                                       closesLibrary: confirmation.closesLibrary)
            }
        }
        if confirmation.reason == .imported {
            toasts.show(BannerText.addedWithoutReplacing(confirmation.entry.title))
        }
        return nil
    }

    /// Ferme l'erreur affichée.
    public func dismissAlert() {
        if !alerts.isEmpty { alerts.removeFirst() }
    }

    /// L'état de la platine est lu maintenant, à la fin de la copie (UX §3.2). Une platine chargée et
    /// active (moteur en marche, disque en mouvement ou tenu) demande une confirmation. Une platine
    /// chargée à l'arrêt, ou vide même si son plateau tourne, est remplacée directement (D-40) ; le
    /// chargement arrête alors le moteur (SF-03).
    private func requestLoad(_ entry: LibraryEntry, on deck: DeckID, reason: LoadReason,
                             closesLibrary: Bool = false) async {
        let snapshot = engine.latestSnapshot()[deck]
        if snapshot.isLoaded, snapshot.isActive {
            confirmations.append(ReplacementConfirmation(deck: deck, currentTitle: self.deck(deck).title,
                                                         entry: entry, reason: reason, closesLibrary: closesLibrary))
            return
        }
        await performLoad(entry, on: deck, reason: reason, closesLibrary: closesLibrary)
    }

    private func performLoad(_ entry: LibraryEntry, on deck: DeckID, reason: LoadReason,
                             closesLibrary: Bool = false) async {
        let model = self.deck(deck)
        model.activity = .loading
        let clip: AudioClip
        do {
            if entry.id == LibraryEntry.demoID {
                clip = await demoClip()
            } else {
                clip = try await decodedClip(for: entry)
            }
        } catch {
            model.activity = .idle
            await reportLoadFailure(error, entry: entry)
            return
        }
        model.activity = .idle
        guard engine.send(.load(deck, clip)) else {
            alerts.append(.failure(.writeFailed(reason: "file de commandes pleine"), name: entry.title))
            return
        }
        model.loadedClip = clip
        model.loadedEntry = entry
        if reason == .duplicate { toasts.show(BannerText.duplicate(entry.title)) }
        if closesLibrary { isLibraryPresented = false }
    }

    // MARK: - Bibliothèque (3.5)

    /// Ferme la feuille Bibliothèque (« OK », Échap).
    public func closeLibrary() {
        isLibraryPresented = false
    }

    /// Demande la suppression de `entry`. La confirmation nomme les platines qui portent le son ;
    /// la démo n'est jamais supprimable (SF-74).
    public func requestDelete(_ entry: LibraryEntry) {
        guard entry.isDeletable else { return }
        deletionConfirmation = DeletionConfirmation(entry: entry, decks: decks(carrying: entry.id))
    }

    /// Réponse à la confirmation de suppression (RM-49). Les platines qui portent le son sont
    /// arrêtées et vidées, puis la copie est supprimée ; l'original n'est jamais touché. La
    /// suppression est rendue sous forme de tâche (attendue par les tests).
    @discardableResult
    public func resolveDeletion(confirm: Bool) -> Task<Void, Never>? {
        guard let confirmation = deletionConfirmation else { return nil }
        deletionConfirmation = nil
        guard confirm else { return nil }
        let entry = confirmation.entry
        for deck in decks(carrying: entry.id) {
            engine.send(.motor(deck, on: false))
            unload(deck)
        }
        return Task { await self.deleteCopy(of: entry) }
    }

    private func deleteCopy(of entry: LibraryEntry) async {
        do {
            try await library.delete(id: entry.id)
        } catch LibraryError.notFound {
            // Already gone (reconciled elsewhere): nothing left to delete.
        } catch {
            alerts.append(.deletionFailed(name: entry.title))
        }
        await refreshLibrary()
    }

    /// Copie vérifiée (`url(for:)`), puis décodage hors du fil principal.
    private func decodedClip(for entry: LibraryEntry) async throws -> AudioClip {
        let url = try await library.url(for: entry.id)
        let decoder = self.decoder
        let title = entry.title
        return try await Task.detached(priority: .userInitiated) {
            try await decoder.decode(url: url, title: title)
        }.value
    }

    /// Clip de démonstration généré une seule fois, hors du fil principal, et partagé (RM-57).
    private func demoClip() async -> AudioClip {
        if let demoClipTask { return await demoClipTask.value }
        let task = Task.detached(priority: .userInitiated) { DemoSound.makeClip() }
        demoClipTask = task
        return await task.value
    }

    // MARK: - Erreurs

    private func report(_ error: any Error, name: String) {
        if error is CancellationError { return }
        let libraryError = error as? LibraryError ?? .writeFailed(reason: "\(error)")
        alerts.append(.failure(libraryError, name: name))
    }

    /// Copie disparue au chargement : « Son introuvable » et liste mise à jour (D-11). Le son déjà
    /// chargé, s'il y en a un, continue d'être joué depuis la mémoire.
    private func reportLoadFailure(_ error: any Error, entry: LibraryEntry) async {
        if error is CancellationError { return }
        if (error as? LibraryError) == .notFound {
            alerts.append(.missingCopy(name: entry.title))
            await refreshLibrary()
            return
        }
        report(error, name: entry.title)
    }
}

// MARK: - Intentions de l'interface (4.1)

extension AppModel: DeckIntents {
    /// Ouvre le sélecteur du système pour la platine, sauf pendant un import ou un chargement.
    public func importFile(on deck: DeckID) {
        guard self.deck(deck).isImportEnabled else { return }
        importPickerDeck = deck
        isImportPickerPresented = true
    }

    public func loadDemo(on deck: DeckID) {
        Task { await self.loadDemoAndWait(on: deck) }
    }

    /// Dépôt d'un fichier sur la platine : même parcours qu'un import (SF-73 ; 5.2).
    public func importDroppedFile(_ url: URL, on deck: DeckID) {
        Task { await self.importDroppedFileAndWait(url, on: deck) }
    }

    /// Ouvre la feuille Bibliothèque, liste à jour (3.5 ; ⌘L, bouton « Bibliothèque »).
    public func openLibrary() {
        isLibraryPresented = true
        Task { await self.refreshLibrary() }
    }

    /// Ouvre les réglages (3.4) : feuille sur iOS, fenêtre Réglages sur Mac (⌘,).
    public func openSettings() {
        isSettingsPresented = true
    }

    /// Mac : ouvre `Documents/Banque de sons` dans le Finder (menu Fichier ; 3.5). Sans effet sur iOS.
    public func revealLibraryInFinder() {
        #if os(macOS)
        guard let libraryFolder else { return }
        try? FileManager.default.createDirectory(at: libraryFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(libraryFolder)
        #endif
    }
}
