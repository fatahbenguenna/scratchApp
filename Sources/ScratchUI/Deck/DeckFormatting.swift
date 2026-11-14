import Foundation
import ScratchCore

/// Textes affichés et lus par VoiceOver pour une platine (spec 3.1, D-28 ; UX §5.1, §5.2, §5.10,
/// §8.1). Fonctions pures, testées sans interface.
enum DeckFormatting {
    /// Position ou durée sans son (UX §8.1).
    static let emptyTime = "--:--,-"
    /// Signe moins typographique (U+2212).
    static let minusSign = "\u{2212}"
    private static let nbsp = "\u{00A0}"

    /// Nombre de dixièmes de seconde, tronqué vers zéro (« dixième inférieur » : 12,34 → 123,
    /// −1,25 → −12). Une valeur non finie compte pour 0.
    static func tenths(_ seconds: Double) -> Int {
        guard seconds.isFinite else { return 0 }
        // Small epsilon: 12.3 stored as 12.29999… must still read "12,3".
        let magnitude = Int((min(abs(seconds), 1e6) * 10 + 1e-6).rounded(.down))
        return seconds < 0 ? -magnitude : magnitude
    }

    /// `mm:ss,d` avec la virgule décimale ; « −00:01,2 » dans l'amorce (D-28).
    static func clockText(tenths: Int) -> String {
        let magnitude = abs(tenths)
        let text = String(format: "%02d:%02d,%d", magnitude / 600, (magnitude / 10) % 60, magnitude % 10)
        return tenths < 0 ? minusSign + text : text
    }

    /// Forme parlée (UX §8.1) : « 12,3 secondes », « 1 minute 12,3 secondes », « 0 seconde ».
    static func spokenTime(tenths: Int) -> String {
        let magnitude = abs(tenths)
        let minutes = magnitude / 600
        let secondTenths = magnitude % 600
        var parts: [String] = []
        if minutes > 0 { parts.append(minutes > 1 ? "\(minutes) minutes" : "1 minute") }
        if secondTenths > 0 || minutes == 0 {
            let decimal = secondTenths % 10
            let number = decimal == 0 ? "\(secondTenths / 10)" : "\(secondTenths / 10),\(decimal)"
            // French: singular below 2 ("0 seconde", "1,5 seconde").
            parts.append(number + (secondTenths >= 20 ? " secondes" : " seconde"))
        }
        return (tenths < 0 ? "moins " : "") + parts.joined(separator: " ")
    }

    /// Pitch signé au dixième de pour cent : « +5,3 % », « −2,0 % » (U+2212), « 0,0 % » (UX §8.1).
    static func pitchText(_ pitch: Double) -> String {
        let tenths = Int((pitch * 1000).rounded())
        let magnitude = abs(tenths)
        let sign = tenths > 0 ? "+" : (tenths < 0 ? minusSign : "")
        return "\(sign)\(magnitude / 10),\(magnitude % 10)\u{00A0}%"
    }

    /// Texte entre guillemets français avec espaces insécables (UX §8.1).
    static func quoted(_ text: String) -> String { "«\(nbsp)\(text)\(nbsp)»" }

    /// Vitesse nominale parlée (UX §5.3).
    static func spokenSpeed(_ speed: TurntableSpeed) -> String {
        speed == .rpm33 ? "33 tours un tiers" : "45 tours"
    }

    /// État du disque pour VoiceOver (UX §5.1, §7.2).
    enum DiscStatus: Equatable {
        case empty, stopped, held, atEnd
        case rotating(TurntableSpeed)

        init(_ snapshot: DeckSnapshot) {
            if !snapshot.isLoaded {
                self = .empty
            } else if snapshot.isAtEnd {
                self = .atEnd
            } else if snapshot.isHeld {
                self = .held
            } else if snapshot.motorOn || abs(snapshot.playbackRate) > 1e-3 {
                self = .rotating(snapshot.speed)
            } else {
                self = .stopped
            }
        }
    }

    /// Valeur VoiceOver du disque : « vide », « à l'arrêt, position 0 seconde »,
    /// « en rotation, 33 tours un tiers, position 12,3 secondes », « tenu, … », « fin du son ».
    static func discValue(status: DiscStatus, positionTenths: Int) -> String {
        let position = "position " + spokenTime(tenths: positionTenths)
        switch status {
        case .empty: return "vide"
        case .atEnd: return "fin du son"
        case .held: return "tenu, " + position
        case .stopped: return "à l'arrêt, " + position
        case let .rotating(speed): return "en rotation, \(spokenSpeed(speed)), " + position
        }
    }

    /// Valeur VoiceOver de l'en-tête : « position 12,3 secondes sur 3 minutes 45 secondes » (UX §5.10).
    static func headerValue(isLoaded: Bool, positionTenths: Int, durationTenths: Int) -> String {
        guard isLoaded else { return "aucun son" }
        return "position \(spokenTime(tenths: positionTenths)) sur \(spokenTime(tenths: durationTenths))"
    }
}
