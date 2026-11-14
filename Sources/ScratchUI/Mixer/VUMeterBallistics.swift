import Foundation

/// Balistique d'un VU-mètre de voie (SF-65, D-26 ; UX §5.15) : montée instantanée, descente de
/// 20 dB/s, maintien de crête 1 s, 12 segments. Calculée à partir de la crête de l'instantané
/// (`DeckSnapshot.peakLevel`, linéaire, 1 = 0 dBFS), sans traitement du signal. Logique pure.
public struct VUMeterBallistics: Equatable, Sendable {
    /// Seuils des 12 segments, en dBFS, du bas vers le haut.
    public static let segmentLevels: [Double] = [-48, -42, -36, -30, -24, -18, -12, -9, -6, -3, -1, 0]
    /// Plancher de l'échelle : silence.
    static let floor: Double = -96
    static let fallRate: Double = 20
    static let peakHoldDuration: Double = 1

    /// Niveau affiché, en dBFS.
    public private(set) var level = floor
    /// Crête maintenue, en dBFS.
    public private(set) var peakHold = floor
    private var holdUntil = 0.0
    private var lastTime: Double?

    public init() {}

    /// Une image : crête linéaire du dernier tampon, à l'instant `now` (secondes).
    public mutating func update(peak: Double, at now: Double) {
        let input = peak.isFinite && peak > 0 ? max(Self.floor, 20 * log10(peak)) : Self.floor
        let elapsed = lastTime.map { max(0, now - $0) } ?? 0
        lastTime = now
        level = input >= level ? input : max(input, level - Self.fallRate * elapsed)
        if level >= peakHold {
            peakHold = level
            holdUntil = now + Self.peakHoldDuration
        } else if now >= holdUntil {
            peakHold = level
        }
    }

    /// Nombre de segments allumés (0 à 12). Un niveau égal à un seuil, aux arrondis près, l'allume.
    public var litSegments: Int { Self.segmentLevels.filter { level + 1e-9 >= $0 }.count }

    /// Segment de la crête maintenue, ou `nil` sous le premier seuil.
    public var peakSegment: Int? { Self.segmentLevels.lastIndex { peakHold + 1e-9 >= $0 } }

    /// Valeur VoiceOver : niveau arrondi à 3 dB (« −12 dB »), « silence » sous le premier segment.
    public var accessibilityValue: String {
        guard level >= Self.segmentLevels[0] else { return "silence" }
        let rounded = Int((level / 3).rounded() * 3)
        return (rounded < 0 ? "\u{2212}\(-rounded)" : "\(rounded)") + "\u{00A0}dB"
    }
}
