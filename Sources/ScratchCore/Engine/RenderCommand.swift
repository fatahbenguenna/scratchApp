/// Forme interne d'`EngineCommand` transportée par la file SPSC.
///
/// Identique à `EngineCommand`, sauf que le clip voyage comme référence **non gérée** déjà
/// retenue (+1) par `send` : l'élément de file est trivial, le fil audio ne fait aucun comptage
/// de références et ne libère jamais un clip (ADR-03, ADR-05).
enum RenderCommand {
    case load(DeckID, Unmanaged<AudioClip>)
    case unload(DeckID)
    case motor(DeckID, on: Bool)
    case speed(DeckID, TurntableSpeed)
    case pitch(DeckID, Double)
    case resistance(DeckID, Double)
    case touchBegan(DeckID, angle: Double, time: Double)
    case touchMoved(DeckID, angle: Double, time: Double, predicted: Bool)
    case touchEnded(DeckID, time: Double)
    case setCue(DeckID)
    case recallCue(DeckID)
    case seek(DeckID, seconds: Double)
    case startDuration(Double)
    case brakeDuration(Double)
    case slipmatCatchUp(Double)
    case crossfader(Double)
    case crossfaderCurve(Double)
    case hamster(Bool)
    case lineFader(DeckID, Double)
    case momentaryCut(DeckID, open: Bool)
    case stopAllMotors
    case outputSampleRate(Double)

    /// Convertit une commande publique. Pour `load`, retient le clip (+1) : l'appelant doit
    /// appeler `releaseUnsentClip()` si la commande n'a pas pu être mise en file.
    init(_ command: EngineCommand) {
        switch command {
        case let .load(deck, clip): self = .load(deck, Unmanaged.passRetained(clip))
        case let .unload(deck): self = .unload(deck)
        case let .motor(deck, on): self = .motor(deck, on: on)
        case let .speed(deck, speed): self = .speed(deck, speed)
        case let .pitch(deck, value): self = .pitch(deck, value)
        case let .resistance(deck, value): self = .resistance(deck, value)
        case let .touchBegan(deck, angle, time): self = .touchBegan(deck, angle: angle, time: time)
        case let .touchMoved(deck, angle, time, predicted):
            self = .touchMoved(deck, angle: angle, time: time, predicted: predicted)
        case let .touchEnded(deck, time): self = .touchEnded(deck, time: time)
        case let .setCue(deck): self = .setCue(deck)
        case let .recallCue(deck): self = .recallCue(deck)
        case let .seek(deck, seconds): self = .seek(deck, seconds: seconds)
        case let .startDuration(value): self = .startDuration(value)
        case let .brakeDuration(value): self = .brakeDuration(value)
        case let .slipmatCatchUp(value): self = .slipmatCatchUp(value)
        case let .crossfader(value): self = .crossfader(value)
        case let .crossfaderCurve(value): self = .crossfaderCurve(value)
        case let .hamster(value): self = .hamster(value)
        case let .lineFader(deck, value): self = .lineFader(deck, value)
        case let .momentaryCut(deck, open): self = .momentaryCut(deck, open: open)
        case .stopAllMotors: self = .stopAllMotors
        case let .outputSampleRate(value): self = .outputSampleRate(value)
        }
    }

    /// Rend le +1 pris par `init(_:)` sur une commande qui n'est pas partie (fil de contrôle).
    func releaseUnsentClip() {
        if case let .load(_, clip) = self { clip.release() }
    }
}
