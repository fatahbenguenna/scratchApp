import Foundation
import ScratchCore

/// Rapport de latence geste→son de la recette (6.3 CA 3 ; SF-78, D-14, D-15, D-54, D-56), produit
/// par `ScratchApp --latency-report` au format JSON.
///
/// - **Sortie réelle** : nom, fréquence, tampon demandé (128 trames, 256 en repli : #91) et tampon
///   effectif, latence de sortie annoncée, fréquence réelle mesurée par le système et dérive en ppm
///   (#129 ; macOS seulement). Sans sortie, « indisponible », avec la mesure à 48 kHz et 256 trames.
/// - **Mesure par cadence d'affichage** (120 Hz, puis 60 Hz) : régime appris sur 8 phases
///   touches/affichage. La **moyenne**, tampon et latence de sortie annoncée compris, est la
///   référence de D-56 et se compare à l'objectif de D-15 (20 ms au plus à 120 Hz, 30 ms au plus à
///   60 Hz). Le pire cas et le premier geste sont publiés sans décider ; un pire cas au-delà de
///   l'objectif plus une période d'image signale un défaut du rejeu et commande une issue (D-56).
///
/// Toutes les durées sont en millisecondes.
public struct LatencyReport: Codable, Equatable, Sendable {
    /// Sortie audio mesurée.
    public struct Output: Codable, Equatable, Sendable {
        /// Nom de la sortie ; `nil` si aucune n'a démarré.
        public var name: String?
        public var available: Bool
        public var sampleRate: Double
        public var requestedBufferFrames: Int
        public var effectiveBufferFrames: Int
        public var outputLatencyMilliseconds: Double
        /// Fréquence réelle mesurée par le système (`kAudioDevicePropertyActualSampleRate`), `nil` si
        /// inconnue (iOS, sortie indisponible).
        public var actualSampleRate: Double?
        /// Écart de la fréquence réelle à la fréquence nominale, en parties par million (#129).
        public var driftPartsPerMillion: Double?
    }

    /// Mesure à une cadence d'affichage.
    public struct Display: Codable, Equatable, Sendable {
        public var displayRate: Double
        public var phases: Int
        /// Référence (D-56) : régime appris, moyenne sur la phase, tampon et latence annoncée compris.
        public var totalMilliseconds: Double
        /// Pire phase, publiée sans décider de la gate (D-56).
        public var worstTotalMilliseconds: Double
        /// Premier geste, moyenne sur la phase, tampon et latence annoncée compris.
        public var firstGestureTotalMilliseconds: Double
        /// Partie moteur du régime appris : moyenne, maximum et minimum sur la phase.
        public var learnedEngineMeanMilliseconds: Double
        public var learnedEngineMaximumMilliseconds: Double
        public var learnedEngineMinimumMilliseconds: Double
        /// Objectif de D-15 pour cette cadence.
        public var targetMilliseconds: Double
        public var withinTarget: Bool
        /// Seuil d'issue de D-56 : objectif plus une période d'image (28,3 ms à 120 Hz, 46,7 ms à 60 Hz).
        public var issueThresholdMilliseconds: Double
        /// La pire phase dépasse ce seuil : défaut du rejeu, une issue est requise (D-56).
        public var worstExceedsIssueThreshold: Bool
    }

    public var output: Output
    public var displays: [Display]
    /// Toutes les moyennes tiennent leur objectif.
    public var withinTargets: Bool
    /// Une pire phase au moins dépasse le seuil d'issue de D-56.
    public var issueRequired: Bool

    /// Objectif de D-15 : 20 ms au plus sur un écran à 120 Hz, 30 ms au plus à 60 Hz.
    public static func target(displayRate: Double) -> Double {
        displayRate >= 90 ? 0.020 : 0.030
    }

    /// Dérive en ppm de `actual` par rapport à `nominal`.
    public static func drift(actual: Double, nominal: Double) -> Double {
        (actual - nominal) / nominal * 1_000_000
    }

    /// - Parameters:
    ///   - status: état de la sortie pendant la mesure.
    ///   - requestedBufferFrames: tampon demandé au système.
    ///   - unavailableBufferFrames: tampon de la mesure sans sortie (horloge de secours).
    ///   - actualSampleRate: fréquence réelle mesurée par le système, si elle est connue.
    ///   - measurements: mesure de la sonde pour chaque cadence d'affichage, dans l'ordre.
    public init(status: AudioOutputStatus, requestedBufferFrames: Int,
                unavailableBufferFrames: Int = TurntableConstants.preferredBufferFrames, actualSampleRate: Double? = nil,
                measurements: [(displayRate: Double, measurement: GestureLatencyProbe.Measurement)]) {
        let info = status.outputInfo
        let actual = info == nil ? nil : actualSampleRate
        var drift: Double?
        if let actual, let nominal = info?.sampleRate { drift = Self.drift(actual: actual, nominal: nominal) }
        output = Output(name: info?.name, available: info != nil, sampleRate: info?.sampleRate ?? 48_000,
                        requestedBufferFrames: requestedBufferFrames,
                        effectiveBufferFrames: info?.bufferFrames ?? unavailableBufferFrames,
                        outputLatencyMilliseconds: (info?.outputLatency ?? 0) * 1_000,
                        actualSampleRate: actual,
                        driftPartsPerMillion: drift)
        displays = measurements.map { displayRate, measurement in
            let target = Self.target(displayRate: displayRate)
            let issueThreshold = target + 1 / displayRate
            return Display(displayRate: displayRate, phases: measurement.learned.values.count,
                           totalMilliseconds: measurement.total * 1_000,
                           worstTotalMilliseconds: measurement.worstTotal * 1_000,
                           firstGestureTotalMilliseconds: measurement.firstGestureTotal * 1_000,
                           learnedEngineMeanMilliseconds: measurement.learned.mean * 1_000,
                           learnedEngineMaximumMilliseconds: measurement.learned.maximum * 1_000,
                           learnedEngineMinimumMilliseconds: measurement.learned.minimum * 1_000,
                           targetMilliseconds: target * 1_000,
                           withinTarget: measurement.total <= target,
                           issueThresholdMilliseconds: issueThreshold * 1_000,
                           worstExceedsIssueThreshold: measurement.worstTotal > issueThreshold)
        }
        withinTargets = displays.allSatisfy(\.withinTarget)
        issueRequired = displays.contains(where: \.worstExceedsIssueThreshold)
    }
}
