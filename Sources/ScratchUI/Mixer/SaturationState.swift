import ScratchCore

/// Indicateur SAT de la sortie (SF-65, D-13 ; UX §5.16) : éteint, « limiteur actif » dès 1 dB de
/// réduction, « écrêtage » si la crête atteint 0 dBFS ; chaque état allumé est maintenu 1 s.
/// L'écrêtage l'emporte sur le limiteur. Logique pure.
public struct SaturationState: Equatable, Sendable {
    public enum Level: Int, Equatable, Sendable {
        case none, limiting, clipping
    }

    static let holdDuration: Double = 1

    public private(set) var level = Level.none
    private var holdUntil = 0.0

    public init() {}

    /// Une image : état de la table publié par le moteur, à l'instant `now` (secondes).
    public mutating func update(_ mixer: MixerSnapshot, at now: Double) {
        let input: Level = mixer.isClipping ? .clipping : (mixer.limiterActive ? .limiting : .none)
        if input != .none, input.rawValue >= level.rawValue || now >= holdUntil {
            level = input
            holdUntil = now + Self.holdDuration
        } else if input == .none, now >= holdUntil {
            level = .none
        }
    }

    /// Valeur VoiceOver : « aucune », « limiteur actif », « écrêtage ».
    public var accessibilityValue: String {
        switch level {
        case .none: return "aucune"
        case .limiting: return "limiteur actif"
        case .clipping: return "écrêtage"
        }
    }
}
