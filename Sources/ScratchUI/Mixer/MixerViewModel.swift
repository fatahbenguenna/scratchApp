import Foundation
import Observation
import ScratchCore

/// Modèle de présentation de la table de mixage (PRD 4.2 ; architecture §5.2). Mêmes cadences que
/// `DeckViewModel` : `frame` à chaque image (VU-mètres, saturation), le reste sur changement.
///
/// **Version de base (story 0.2), complétée en 4.2** (SAT, libellés, lettres, repères de cut-in,
/// valeurs VoiceOver) **et en 5.1.** Les VU-mètres de voie sont portés par `DeckViewModel.channelMeter`
/// (crête de la voie dans l'instantané de la platine).
@MainActor
@Observable
public final class MixerViewModel {
    private let engine: any EngineControlling

    /// Instantané de la table, mis à jour à chaque image.
    public private(set) var frame = MixerSnapshot.initial

    public private(set) var crossfader = TurntableConstants.defaultCrossfader
    public private(set) var crossfaderCurve = TurntableConstants.defaultCrossfaderCurve
    public private(set) var hamster = false
    public private(set) var lineFaders = DeckPair(repeating: TurntableConstants.defaultLineFader)
    public private(set) var momentaryCuts = DeckPair(repeating: false)
    /// Indicateur SAT, maintenu 1 s (D-13).
    public private(set) var saturation = SaturationState()

    // Commanded values shown until a snapshot confirms them (#57).
    @ObservationIgnored private var commandedCrossfader = CommandedValue<Double>()
    @ObservationIgnored private var commandedCurve = CommandedValue<Double>()
    @ObservationIgnored private var commandedHamster = CommandedValue<Bool>()
    @ObservationIgnored private var commandedLineFaders = CommandedValue<DeckPair<Double>>()
    @ObservationIgnored private var commandedCuts = CommandedValue<DeckPair<Bool>>()
    /// Horloge monotone des confirmations (injectée par les tests).
    @ObservationIgnored var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }

    public init(engine: any EngineControlling) {
        self.engine = engine
    }

    /// Applique l'instantané de l'image ; une valeur commandée reste affichée jusqu'à confirmation
    /// (#57, `CommandedValue`).
    func apply(_ snapshot: MixerSnapshot) {
        if frame != snapshot { frame = snapshot }
        let now = clock()
        var nextSaturation = saturation
        nextSaturation.update(snapshot, at: now)
        if saturation != nextSaturation { saturation = nextSaturation }
        let shownCrossfader = commandedCrossfader.resolve(snapshot.crossfader, at: now)
        if crossfader != shownCrossfader { crossfader = shownCrossfader }
        let shownCurve = commandedCurve.resolve(snapshot.crossfaderCurve, at: now)
        if crossfaderCurve != shownCurve { crossfaderCurve = shownCurve }
        let shownHamster = commandedHamster.resolve(snapshot.hamster, at: now)
        if hamster != shownHamster { hamster = shownHamster }
        let shownFaders = commandedLineFaders.resolve(snapshot.lineFaders, at: now)
        if lineFaders != shownFaders { lineFaders = shownFaders }
        let shownCuts = commandedCuts.resolve(snapshot.momentaryCuts, at: now)
        if momentaryCuts != shownCuts { momentaryCuts = shownCuts }
    }

    // MARK: Textes et repères (story 4.2)

    /// Platine à chaque extrémité du crossfader : la butée gauche est la voie A, ou B avec le
    /// hamster (SF-67, 6.10) ; le bouton ne bouge pas.
    public var leftDeck: DeckID { hamster ? .b : .a }
    public var rightDeck: DeckID { hamster ? .a : .b }

    /// Valeur de la courbe : « Coupure franche » (1), « Douce » (0), sinon « 60 % » (UX §5.13).
    public var curveText: String {
        if crossfaderCurve >= 1 { return "Coupure franche" }
        if crossfaderCurve <= 0 { return "Douce" }
        return Self.percent(crossfaderCurve)
    }

    /// Largeur de cut-in `w = lerp(1 ; 0,03 ; courbe)` ; repères affichés quand `w ≤ 0,2`, à `w`
    /// (plein niveau de la voie de droite) et `1 − w` (voie de gauche) (UX §5.12).
    public var cutInWidth: Double? {
        let width = CrossfaderCurve.cutInWidth(curve: crossfaderCurve)   // core formula (#75)
        return width <= 0.2 ? width : nil
    }

    /// Valeur VoiceOver du crossfader : « 50 %, centre », « butée gauche, voie A » (UX §5.12, §11.2).
    public var crossfaderAccessibilityValue: String {
        AccessibilityText.crossfader(crossfader, leftDeck: leftDeck, rightDeck: rightDeck)
    }

    /// Valeur VoiceOver de la courbe : « coupure franche », « douce », « 60 % » (UX §11.2).
    public var curveAccessibilityValue: String { AccessibilityText.curve(crossfaderCurve) }

    /// Valeur d'un fader de voie : « 100 % ».
    public func lineFaderText(_ deck: DeckID) -> String { Self.percent(lineFaders[deck]) }

    /// Pourcentage entier avec espace insécable (UX §8.1).
    static func percent(_ value: Double) -> String { AccessibilityText.percent(value) }

    /// Position 0 (butée A) … 1 (butée B) (SF-12).
    public func setCrossfader(_ value: Double) {
        let clamped = value.clamped(to: 0...1, fallback: TurntableConstants.defaultCrossfader)
        guard engine.send(.crossfader(clamped)) else { return }
        crossfader = clamped
        commandedCrossfader.command(clamped, at: clock())
    }

    /// Clavier Mac `←` / `→` : pas de 5 % (3.5, 6.14).
    public func nudgeCrossfader(steps: Int) {
        let step = TurntableConstants.keyboardCrossfaderStep
        setCrossfader(((crossfader + Double(steps) * step) / step).rounded() * step)
    }

    /// Clavier Mac `⇧←` / `⇧↓` / `⇧→` : butée A, centre, butée B (3.5).
    /// Fader de voie ± `steps` × 5 % (actions d'accessibilité, flèches sur le fader focalisé ; 5.3).
    public func nudgeLineFader(_ deck: DeckID, steps: Int) {
        setLineFader(deck, lineFaders[deck] + Double(steps) * 0.05)
    }

    /// Courbe ± `steps` × 10 % (actions d'accessibilité, flèches sur la courbe focalisée ; 5.3).
    public func nudgeCrossfaderCurve(steps: Int) {
        setCrossfaderCurve(crossfaderCurve + Double(steps) * 0.1)
    }

    public func moveCrossfaderToA() { setCrossfader(0) }
    public func centerCrossfader() { setCrossfader(0.5) }
    public func moveCrossfaderToB() { setCrossfader(1) }

    /// Courbe 0 (douce) … 1 (coupure franche) (SF-66).
    public func setCrossfaderCurve(_ value: Double) {
        let clamped = value.clamped(to: 0...1, fallback: TurntableConstants.defaultCrossfaderCurve)
        guard engine.send(.crossfaderCurve(clamped)) else { return }
        crossfaderCurve = clamped
        commandedCurve.command(clamped, at: clock())
    }

    /// Hamster (SF-67).
    public func setHamster(_ on: Bool) {
        guard engine.send(.hamster(on)) else { return }
        hamster = on
        commandedHamster.command(on, at: clock())
    }

    /// Fader de voie 0…1 (SF-65).
    public func setLineFader(_ deck: DeckID, _ value: Double) {
        let clamped = value.clamped(to: 0...1, fallback: TurntableConstants.defaultLineFader)
        guard engine.send(.lineFader(deck, clamped)) else { return }
        lineFaders[deck] = clamped
        commandedLineFaders.command(lineFaders, at: clock())
    }

    /// Coupure momentanée `F` / `J` : ouverte tant que la touche est maintenue (3.5, IC-06).
    public func setMomentaryCut(_ deck: DeckID, open: Bool) {
        guard engine.send(.momentaryCut(deck, open: open)) else { return }
        momentaryCuts[deck] = open
        commandedCuts.command(momentaryCuts, at: clock())
    }
}
