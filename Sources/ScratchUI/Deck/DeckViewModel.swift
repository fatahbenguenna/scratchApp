import Observation
import ScratchCore
import ScratchLibrary

/// Modèle de présentation d'une platine (PRD 4.1 ; architecture §5.2).
///
/// **Version de base (story 0.2), complétée par Léa en 4.1 et 4.5** (formats d'affichage, états des
/// boutons, faux moteur des aperçus).
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

    /// Entrée de bibliothèque chargée (titre affiché), renseignée par l'`AppModel` au chargement.
    public var loadedEntry: LibraryEntry?
    public private(set) var isLoaded = false
    public private(set) var motorOn = false
    public private(set) var speed = TurntableSpeed.rpm33
    public private(set) var pitch: Double = 0
    public private(set) var resistance = TurntableConstants.defaultResistance
    public private(set) var cueSeconds: Double?
    public private(set) var isHeld = false

    public init(deck: DeckID, engine: any EngineControlling) {
        self.deck = deck
        self.engine = engine
    }

    /// Applique l'instantané de l'image (appelé par `AppModel.tick()`).
    func apply(_ snapshot: DeckSnapshot) {
        if frame != snapshot { frame = snapshot }
        if isLoaded != snapshot.isLoaded { isLoaded = snapshot.isLoaded }
        if motorOn != snapshot.motorOn { motorOn = snapshot.motorOn }
        if speed != snapshot.speed { speed = snapshot.speed }
        if pitch != snapshot.pitch { pitch = snapshot.pitch }
        if resistance != snapshot.resistance { resistance = snapshot.resistance }
        if cueSeconds != snapshot.cueSeconds { cueSeconds = snapshot.cueSeconds }
        if isHeld != snapshot.isHeld { isHeld = snapshot.isHeld }
        if !snapshot.isLoaded, loadedEntry != nil { loadedEntry = nil }
    }

    // MARK: Transport

    /// START / STOP (SF-04, SF-05).
    public func toggleMotor() {
        setMotor(!motorOn)
    }

    public func setMotor(_ on: Bool) {
        if engine.send(.motor(deck, on: on)) { motorOn = on }
    }

    /// 33⅓ / 45 RPM (SF-04).
    public func setSpeed(_ newSpeed: TurntableSpeed) {
        if engine.send(.speed(deck, newSpeed)) { speed = newSpeed }
    }

    /// Pitch en fraction, quantifié au pas de 0,1 % et borné à ±8 % (SF-11).
    public func setPitch(_ value: Double) {
        let quantized = Self.quantizedPitch(value)
        if engine.send(.pitch(deck, quantized)) { pitch = quantized }
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
        if engine.send(.resistance(deck, clamped)) { resistance = clamped }
    }

    /// SET CUE (SF-13).
    public func setCue() { engine.send(.setCue(deck)) }

    /// CUE (SF-13).
    public func recallCue() { engine.send(.recallCue(deck)) }

    /// Needle drop sur l'aperçu complet : `fraction` 0…1 de la durée (SF-71). Ignoré disque tenu.
    public func needleDrop(fraction: Double) {
        guard !isHeld, frame.durationSeconds > 0, fraction.isFinite else { return }
        engine.send(.seek(deck, seconds: fraction.clamped(to: 0...1, fallback: 0) * frame.durationSeconds))
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
