import Foundation
import Observation
import ScratchCore
import ScratchLibrary

/// Modèle de présentation d'une platine (PRD 4.1 ; architecture §5.2).
///
/// **Version de base (story 0.2), complétée en 4.1** (textes affichés, états des boutons, points
/// d'accroche de l'`AppModel`), **en 4.5 et en 4.6** (forme d'onde, needle drop).
///
/// Deux cadences :
/// - `frame` : instantané complet de la platine, remplacé **à chaque image** par `AppModel.tick()`.
///   Seules les vues qui le lisent (disque, forme d'onde, position, VU-mètre) sont redessinées à
///   chaque image ;
/// - les autres propriétés ne changent que lorsque leur valeur change (boutons, curseurs, libellés).
///
/// Les intentions traduisent un geste de l'utilisateur en `EngineCommand`. L'état affiché vient
/// toujours de l'instantané (ou d'une mise à jour optimiste confirmée par l'instantané suivant).
@MainActor
@Observable
public final class DeckViewModel {
    public let deck: DeckID
    private let engine: any EngineControlling

    /// Instantané de la platine, mis à jour à chaque image.
    public private(set) var frame = DeckSnapshot.initial

    /// Entrée de bibliothèque chargée (titre affiché), renseignée par l'`AppModel` au chargement, avec
    /// `loadedClip`. Effacée seulement quand l'instantané montre que ce clip a quitté la platine.
    public var loadedEntry: LibraryEntry?
    /// Clip envoyé par `.load`, renseigné par l'`AppModel` en même temps que `loadedEntry` (story 4.1
    /// CA 7). Chaque changement de clip lance l'analyse de sa forme d'onde, ou la reprend du cache
    /// si l'autre platine affiche le même clip (4.6).
    public var loadedClip: AudioClip? {
        get { storedClip }
        set {
            storedClip = newValue
            loadedClipDidChange()
        }
    }
    private var storedClip: AudioClip?
    /// Enveloppe de la forme d'onde du clip chargé (4.6) ; `nil` à vide et pendant l'analyse.
    public private(set) var peaks: WaveformPeaks?
    /// Import ou chargement en cours, posé par l'`AppModel` (UX §5.10, §7.2).
    public var activity = DeckActivity.idle

    public private(set) var isLoaded = false
    public private(set) var motorOn = false
    public private(set) var speed = TurntableSpeed.rpm33
    public private(set) var pitch: Double = 0
    public private(set) var resistance = TurntableConstants.defaultResistance
    public private(set) var cueSeconds: Double?
    public private(set) var isHeld = false
    /// Tête bloquée en fin de son : pastille « Fin du son » (RM-55, UX §5.10).
    public private(set) var isAtEnd = false

    /// Position `mm:ss,d` (D-28) ; ne change que lorsque le dixième change.
    public private(set) var positionText = DeckFormatting.emptyTime
    /// Durée `mm:ss,d`, « --:--,- » sans son.
    public private(set) var durationText = DeckFormatting.emptyTime
    /// Durée du son chargé (0 sans son), hors de la cadence par image : géométrie de l'aperçu (4.6).
    public private(set) var durationSeconds: Double = 0
    /// Valeur VoiceOver du disque (UX §5.1), à la même cadence que `positionText`.
    public private(set) var discAccessibilityValue = "vide"
    /// Valeur VoiceOver de l'en-tête (UX §5.10), à la même cadence que `positionText`.
    public private(set) var headerAccessibilityValue = "aucun son"
    /// VU-mètre de la voie (niveau après le fader de voie, avant le crossfader ; SF-65, D-26),
    /// mis à jour à chaque image. Lu seulement par les VU-mètres de la table de mixage.
    public private(set) var channelMeter = VUMeterBallistics()
    /// Incrémenté à chaque SET CUE accepté : éclat de 150 ms du marqueur (4.5, 4.6).
    public private(set) var setCueCount = 0
    /// Annonce du dernier SET CUE : « Point CUE mémorisé à 12,3 secondes » (UX §5.6), avec le CUE
    /// confirmé par l'instantané (#94) ; émise à chaque incrément de `setCueAnnouncementCount`.
    public private(set) var setCueAnnouncement = ""
    public private(set) var setCueAnnouncementCount = 0
    /// Annonce VoiceOver d'un événement de la platine (son chargé, platine vidée ; UX §8.6), émise
    /// par la disposition principale à chaque incrément d'`eventAnnouncementCount` (5.3).
    public private(set) var eventAnnouncement = ""
    public private(set) var eventAnnouncementCount = 0
    /// Incrémenté à chaque START sur une platine vide : la vue met alors en avant « Importer » et
    /// « Charger la démo » et VoiceOver l'annonce (PO-01, UX §5.2).
    public private(set) var emptyDeckHighlightCount = 0

    @ObservationIgnored private var displayKey: DisplayKey?
    /// Clip attendu (`loadedClip`) déjà vu dans un instantané.
    @ObservationIgnored private var confirmedClipID: AudioClip.ID?
    @ObservationIgnored private var previousClipID: AudioClip.ID?

    // Commanded values shown until a snapshot confirms them (#57).
    @ObservationIgnored private var commandedMotor = CommandedValue<Bool>()
    @ObservationIgnored private var commandedSpeed = CommandedValue<TurntableSpeed>()
    @ObservationIgnored private var commandedPitch = CommandedValue<Double>()
    @ObservationIgnored private var commandedResistance = CommandedValue<Double>()
    /// SET CUE envoyé, en attente du CUE de l'instantané : CUE précédent, position affichée et date.
    @ObservationIgnored private var pendingSetCue: (previous: Double?, position: Double, time: Double)?
    /// Horloge monotone des confirmations (injectée par les tests).
    @ObservationIgnored var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }

    // Waveform analysis of the loaded clip (4.6).
    @ObservationIgnored private let waveformCache: WaveformCache
    @ObservationIgnored private var waveformClipID: AudioClip.ID?
    @ObservationIgnored private var waveformTask: Task<Void, Never>?

    /// Saisie du disque (doigt, souris, trackpad) partagée par les surfaces de la story 4.3 ;
    /// `cancelAll` relâche le disque (rotation, changement de disposition, sélecteur de platine).
    public let discInput: DiscInputCoordinator

    /// - Parameter waveformCache: cache des formes d'onde partagé par les platines (`.shared` par défaut).
    public init(deck: DeckID, engine: any EngineControlling, waveformCache: WaveformCache? = nil) {
        self.deck = deck
        self.engine = engine
        self.waveformCache = waveformCache ?? .shared
        discInput = DiscInputCoordinator(deck: deck)
        discInput.model = self
    }

    // MARK: Textes et états affichés (story 4.1)

    /// « platine A » : suffixe des libellés VoiceOver (UX §5.0).
    public var deckName: String { "platine \(deck.rawValue)" }

    /// Titre : nom de l'entrée, c'est-à-dire de la copie locale (D-12), « Aucun son » à vide.
    public var title: String {
        if let title = loadedEntry?.title, !title.isEmpty { return title }
        if let title = loadedClip?.title, !title.isEmpty { return title }
        return isLoaded ? "Son sans titre" : "Aucun son"
    }

    /// Un titre de son est affiché (sinon « Aucun son », en texte secondaire).
    public var hasTitle: Bool { isLoaded || loadedEntry != nil || loadedClip != nil }

    /// Libellé VoiceOver de l'en-tête : « Platine A, « titre » » (UX §5.10).
    public var headerAccessibilityLabel: String {
        hasTitle ? "Platine \(deck.rawValue), \(DeckFormatting.quoted(title))" : "Platine \(deck.rawValue)"
    }

    /// Pastille d'activité : « Import de « nom »… », « Chargement… ».
    public var activityText: String? {
        switch activity {
        case .idle: return nil
        case let .importing(fileName): return "Import de \(DeckFormatting.quoted(fileName))…"
        case .loading: return "Chargement…"
        }
    }

    /// « Importer » est désactivé pendant un import ou un chargement (UX §7.2).
    public var isImportEnabled: Bool { activity == .idle }

    /// La platine vide propose « Importer » et « Charger la démo » (SF-01) ; pendant un import ou
    /// un chargement, un indicateur les remplace (UX §5.1).
    public var showsEmptyActions: Bool { !isLoaded && activity == .idle }

    /// Texte du bouton : il suit la commande du moteur, pas la vitesse réelle (UX §5.2) :
    /// « START » pendant le freinage, « STOP » pendant l'accélération.
    public var startStopTitle: String { motorOn ? "STOP" : "START" }
    public var startStopAccessibilityLabel: String { "\(startStopTitle), \(deckName)" }
    public var startStopAccessibilityValue: String { motorOn ? "moteur en marche" : "moteur arrêté" }

    /// Annonce VoiceOver d'un START sur une platine vide (UX §8.6).
    public var emptyStartAnnouncement: String { AccessibilityText.emptyStart(deck: deck) }

    /// Applique l'instantané de l'image (appelé par `AppModel.tick()`).
    func apply(_ snapshot: DeckSnapshot) {
        if frame != snapshot { frame = snapshot }
        if isLoaded != snapshot.isLoaded {
            // A deck only empties when its sound is deleted from the library (3.5).
            if isLoaded { announce(AccessibilityText.cleared(deck: deck)) }
            isLoaded = snapshot.isLoaded
        }
        if durationSeconds != snapshot.durationSeconds { durationSeconds = snapshot.durationSeconds }
        // A commanded value stays shown until a snapshot confirms it (#57).
        let now = clock()
        var meter = channelMeter
        meter.update(peak: snapshot.peakLevel, at: now)
        if channelMeter != meter { channelMeter = meter }
        let shownMotor = commandedMotor.resolve(snapshot.motorOn, at: now)
        if motorOn != shownMotor { motorOn = shownMotor }
        let shownSpeed = commandedSpeed.resolve(snapshot.speed, at: now)
        if speed != shownSpeed { speed = shownSpeed }
        let shownPitch = commandedPitch.resolve(snapshot.pitch, at: now)
        if pitch != shownPitch { pitch = shownPitch }
        let shownResistance = commandedResistance.resolve(snapshot.resistance, at: now)
        if resistance != shownResistance { resistance = shownResistance }
        if cueSeconds != snapshot.cueSeconds { cueSeconds = snapshot.cueSeconds }
        if isHeld != snapshot.isHeld { isHeld = snapshot.isHeld }
        if isAtEnd != snapshot.isAtEnd { isAtEnd = snapshot.isAtEnd }
        reconcileLoadedClip(with: snapshot.clipID)
        announceConfirmedCue(snapshot, at: now)
        updateTexts(for: snapshot)
    }

    /// N'efface `loadedEntry` et `loadedClip` que lorsque l'instantané montre que le clip attendu a
    /// quitté la platine, jamais sur une image rendue avant l'application de `.load` (CA 7).
    /// Les identifiants de clip sont croissants : un clip plus ancien que celui attendu signifie que
    /// le chargement n'est pas encore appliqué.
    private func reconcileLoadedClip(with shown: AudioClip.ID?) {
        defer { previousClipID = shown }
        guard let expected = loadedClip?.id else {
            // Entry without a clip: clear it only when the deck content changes.
            if loadedEntry != nil, previousClipID != nil, shown != previousClipID { loadedEntry = nil }
            return
        }
        if shown == expected {
            if confirmedClipID != expected {
                announce(AccessibilityText.loaded(deck: deck, title: title, duration: durationSeconds))
            }
            confirmedClipID = expected
        } else if let shown, shown > expected {
            clearLoadedClip()   // superseded by a newer load
        } else if confirmedClipID == expected {
            clearLoadedClip()   // our clip was unloaded or replaced
        }
    }

    private func announce(_ text: String) {
        eventAnnouncement = text
        eventAnnouncementCount &+= 1
    }

    private func clearLoadedClip() {
        loadedEntry = nil
        loadedClip = nil
        confirmedClipID = nil
    }

    /// Forme d'onde du nouveau clip : rend la référence de l'ancien au cache, puis attend l'analyse
    /// du nouveau (partagée avec l'autre platine si c'est le même clip, RM-57).
    private func loadedClipDidChange() {
        let id = storedClip?.id
        guard id != waveformClipID else { return }
        if let previous = waveformClipID { waveformCache.release(previous) }
        waveformTask?.cancel()
        waveformTask = nil
        waveformClipID = id
        if peaks != nil { peaks = nil }
        guard let clip = storedClip else { return }
        let analysis = waveformCache.retain(clip)
        waveformTask = Task { [weak self] in
            let result = await analysis.value
            guard let self, self.waveformClipID == id else { return }
            self.peaks = result
        }
    }

    /// Met à jour les textes seulement quand le dixième affiché ou l'état change (UX §10.2).
    private func updateTexts(for snapshot: DeckSnapshot) {
        let loaded = snapshot.isLoaded
        let key = DisplayKey(
            isLoaded: loaded,
            positionTenths: loaded ? DeckFormatting.tenths(snapshot.positionSeconds) : 0,
            durationTenths: loaded ? DeckFormatting.tenths(snapshot.durationSeconds) : 0,
            status: DeckFormatting.DiscStatus(snapshot)
        )
        guard key != displayKey else { return }
        displayKey = key
        let position = loaded ? DeckFormatting.clockText(tenths: key.positionTenths) : DeckFormatting.emptyTime
        let duration = loaded ? DeckFormatting.clockText(tenths: key.durationTenths) : DeckFormatting.emptyTime
        let discValue = DeckFormatting.discValue(status: key.status, positionTenths: key.positionTenths)
        let headerValue = DeckFormatting.headerValue(
            isLoaded: loaded, positionTenths: key.positionTenths, durationTenths: key.durationTenths)
        if positionText != position { positionText = position }
        if durationText != duration { durationText = duration }
        if discAccessibilityValue != discValue { discAccessibilityValue = discValue }
        if headerAccessibilityValue != headerValue { headerAccessibilityValue = headerValue }
    }

    private struct DisplayKey: Equatable {
        var isLoaded: Bool
        var positionTenths: Int
        var durationTenths: Int
        var status: DeckFormatting.DiscStatus
    }

    // MARK: Transport

    /// START / STOP (SF-04, SF-05).
    public func toggleMotor() {
        setMotor(!motorOn)
    }

    /// Permis sur une platine vide : le plateau tourne sans son (PO-01) et les actions de l'état vide
    /// sont mises en avant.
    public func setMotor(_ on: Bool) {
        guard engine.send(.motor(deck, on: on)) else { return }
        motorOn = on
        commandedMotor.command(on, at: clock())
        if on, !isLoaded { emptyDeckHighlightCount &+= 1 }
    }

    /// 33⅓ / 45 RPM (SF-04).
    public func setSpeed(_ newSpeed: TurntableSpeed) {
        guard engine.send(.speed(deck, newSpeed)) else { return }
        speed = newSpeed
        commandedSpeed.command(newSpeed, at: clock())
    }

    /// Pitch en fraction, quantifié au pas de 0,1 % et borné à ±8 % (SF-11).
    public func setPitch(_ value: Double) {
        let quantized = Self.quantizedPitch(value)
        guard engine.send(.pitch(deck, quantized)) else { return }
        pitch = quantized
        commandedPitch.command(quantized, at: clock())
    }

    /// Pitch ± `steps` × 0,1 % (clavier Mac, actions d'accessibilité : 3.5, 6.16).
    public func nudgePitch(steps: Int) {
        setPitch(pitch + Double(steps) * TurntableConstants.pitchStep)
    }

    /// Remise à 0 % en un geste (SF-11).
    public func resetPitch() {
        setPitch(0)
    }

    static func quantizedPitch(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let steps = (value / TurntableConstants.pitchStep).rounded()
        return (steps * TurntableConstants.pitchStep).clamped(to: TurntableConstants.pitchRange, fallback: 0)
    }

    // MARK: Jeu

    /// Résistance du vinyle 0…1 (SF-21).
    public func setResistance(_ value: Double) {
        let clamped = value.clamped(to: 0...1, fallback: TurntableConstants.defaultResistance)
        guard engine.send(.resistance(deck, clamped)) else { return }
        resistance = clamped
        commandedResistance.command(clamped, at: clock())
    }

    /// Résistance ± `steps` × 5 % (actions d'accessibilité, flèches sur le curseur focalisé ; 5.3).
    public func nudgeResistance(steps: Int) {
        setResistance(resistance + Double(steps) * 0.05)
    }

    /// SET CUE (SF-13) : mémorise la position de la tête, y compris disque tenu (6.6). Sans effet sur
    /// une platine vide.
    public func setCue() {
        guard isLoaded, engine.send(.setCue(deck)) else { return }
        pendingSetCue = (cueSeconds, frame.positionSeconds, clock())
        setCueCount &+= 1
    }

    /// Annonce le CUE mémorisé par le moteur, qui le prend une image et un tampon après l'affichage
    /// (#94) : au premier instantané qui montre un nouveau CUE, ou après le délai de confirmation de
    /// #57 (100 ms), avec le CUE de l'instantané (SET CUE au même endroit) ou la position affichée.
    private func announceConfirmedCue(_ snapshot: DeckSnapshot, at now: Double) {
        guard let pending = pendingSetCue else { return }
        let confirmed = snapshot.cueSeconds != nil && snapshot.cueSeconds != pending.previous
        guard confirmed || now - pending.time >= CommandedValue<Double>.timeout else { return }
        pendingSetCue = nil
        setCueAnnouncement = AccessibilityText.setCue(at: snapshot.cueSeconds ?? pending.position)
        setCueAnnouncementCount &+= 1
    }

    /// CUE (SF-13) : ramène la tête au CUE, ou à 0 s sans CUE, sans changer le moteur, y compris
    /// disque tenu (6.6). Sans effet sur une platine vide.
    public func recallCue() {
        guard isLoaded else { return }
        engine.send(.recallCue(deck))
    }

    // MARK: Textes du pitch, du CUE et de la résistance (story 4.5)

    /// Pitch toujours signé : « +5,3 % », « −2,0 % », « 0,0 % » (UX §5.4, §8.1).
    public var pitchText: String { DeckFormatting.pitchText(pitch) }
    /// Témoin « 0 » : pitch exactement à 0 %.
    public var isPitchZero: Bool { abs(pitch) < 1e-9 }
    /// Résistance : « 50 % ».
    public var resistanceText: String { AccessibilityText.percent(resistance) }
    /// Un CUE est défini : témoin du bouton CUE allumé.
    public var hasCue: Bool { cueSeconds != nil }
    /// Valeur VoiceOver du bouton CUE : « CUE à 12,3 secondes » ou « aucun CUE, retour au début ».
    public var cueAccessibilityValue: String { AccessibilityText.cue(cueSeconds) }

    // MARK: Aperçu et needle drop (story 4.6)

    /// Disque tenu, d'après l'instantané ou un contact déjà reçu par la surface du disque : le needle
    /// drop est alors ignoré (SF-71, D-33).
    public var isDiscHeld: Bool { isHeld || discInput.isHolding }

    /// Needle drop (SF-71, D-33) : place la tête à `seconds`, amorce comprise ([−2 s ; durée]), sans
    /// changer l'état du moteur. Ignoré sur une platine vide ou disque tenu.
    public func needleDrop(toSeconds seconds: Double) {
        let duration = frame.durationSeconds
        guard !isDiscHeld, duration > 0, seconds.isFinite else { return }
        let target = seconds.clamped(to: -TurntableConstants.leadInSeconds...duration, fallback: 0)
        engine.send(.seek(deck, seconds: target))
    }

    /// Needle drop en fraction 0…1 de la durée (SF-71). Ignoré disque tenu.
    public func needleDrop(fraction: Double) {
        guard fraction.isFinite else { return }
        needleDrop(toSeconds: fraction.clamped(to: 0...1, fallback: 0) * frame.durationSeconds)
    }

    /// Needle drop accessible (UX §5.8) : ± `steps` × 5 % de la durée depuis la position actuelle.
    public func nudgeNeedle(steps: Int) {
        let duration = frame.durationSeconds
        needleDrop(toSeconds: frame.positionSeconds + Double(steps) * 0.05 * duration)
    }

    /// Valeur VoiceOver de l'aperçu : « position 12,3 secondes sur 3 minutes 45 secondes, CUE à
    /// 4 secondes » (ou « aucun CUE ») ; à la cadence du dixième, comme l'en-tête (UX §10.2).
    public var overviewAccessibilityValue: String {
        AccessibilityText.overview(header: headerAccessibilityValue, isLoaded: isLoaded, cue: cueSeconds)
    }

    // MARK: Geste sur le disque (angles de `GestureAngleTracker`, temps des événements)

    public func touchBegan(angle: Double, time: Double) {
        engine.send(.touchBegan(deck, angle: angle, time: time))
    }

    /// À appeler pour chaque touche regroupée, dans l'ordre ; `predicted` pour une touche prédite (SF-78).
    public func touchMoved(angle: Double, time: Double, predicted: Bool = false) {
        engine.send(.touchMoved(deck, angle: angle, time: time, predicted: predicted))
    }

    /// Relâchement ou annulation par le système (RM-60).
    public func touchEnded(time: Double) {
        engine.send(.touchEnded(deck, time: time))
    }
}
