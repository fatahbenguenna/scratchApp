import Observation
import ScratchCore

/// Modèle de présentation de la table de mixage (architecture §5.4). Mêmes cadences que
/// `DeckViewModel` : `frame` à chaque image (VU-mètres, saturation), le reste sur changement.
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

    public init(engine: any EngineControlling) {
        self.engine = engine
    }

    func apply(_ snapshot: MixerSnapshot) {
        if frame != snapshot { frame = snapshot }
        if crossfader != snapshot.crossfader { crossfader = snapshot.crossfader }
        if crossfaderCurve != snapshot.crossfaderCurve { crossfaderCurve = snapshot.crossfaderCurve }
        if hamster != snapshot.hamster { hamster = snapshot.hamster }
        if lineFaders != snapshot.lineFaders { lineFaders = snapshot.lineFaders }
        if momentaryCuts != snapshot.momentaryCuts { momentaryCuts = snapshot.momentaryCuts }
    }

    /// Position 0 (butée A) … 1 (butée B) (SF-12).
    public func setCrossfader(_ value: Double) {
        let clamped = value.clamped(to: 0...1, fallback: TurntableConstants.defaultCrossfader)
        if engine.send(.crossfader(clamped)) { crossfader = clamped }
    }

    /// Clavier Mac `←` / `→` : pas de 5 % (3.5, 6.14).
    public func nudgeCrossfader(steps: Int) {
        let step = TurntableConstants.keyboardCrossfaderStep
        setCrossfader(((crossfader + Double(steps) * step) / step).rounded() * step)
    }

    /// Clavier Mac `⇧←` / `⇧↓` / `⇧→` : butée A, centre, butée B (3.5).
    public func moveCrossfaderToA() { setCrossfader(0) }
    public func centerCrossfader() { setCrossfader(0.5) }
    public func moveCrossfaderToB() { setCrossfader(1) }

    /// Courbe 0 (douce) … 1 (coupure franche) (SF-66).
    public func setCrossfaderCurve(_ value: Double) {
        let clamped = value.clamped(to: 0...1, fallback: TurntableConstants.defaultCrossfaderCurve)
        if engine.send(.crossfaderCurve(clamped)) { crossfaderCurve = clamped }
    }

    /// Hamster (SF-67).
    public func setHamster(_ on: Bool) {
        if engine.send(.hamster(on)) { hamster = on }
    }

    /// Fader de voie 0…1 (SF-65).
    public func setLineFader(_ deck: DeckID, _ value: Double) {
        let clamped = value.clamped(to: 0...1, fallback: TurntableConstants.defaultLineFader)
        if engine.send(.lineFader(deck, clamped)) { lineFaders[deck] = clamped }
    }

    /// Coupure momentanée `F` / `J` : ouverte tant que la touche est maintenue (3.5, IC-06).
    public func setMomentaryCut(_ deck: DeckID, open: Bool) {
        if engine.send(.momentaryCut(deck, open: open)) { momentaryCuts[deck] = open }
    }
}
