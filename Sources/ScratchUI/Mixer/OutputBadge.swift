import ScratchCore
import SwiftUI

/// Badge de la sortie audio (SF-16, SF-82, D-35 ; UX §5.17) : capsule de 28 pt, icône et nom de la
/// sortie, « Sortie audio indisponible » sur `danger.deep`. Alimenté par une valeur injectée
/// (`AppModel.outputStatus` dès la 6.2, statut factice dans les aperçus). Non interactif.
struct OutputBadge: View {
    let status: AudioOutputStatus

    var body: some View {
        let unavailable = Self.isUnavailable(status)
        HStack(spacing: 6) {
            Image(systemName: Self.symbol(for: status))
                .font(.system(size: 15))
                .foregroundStyle(unavailable ? Theme.danger : Theme.textSecondary)
            Text(verbatim: Self.label(for: status))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .frame(maxWidth: 240, alignment: .leading)
        .background(Capsule().fill(unavailable ? Theme.dangerDeep : Theme.bgRaised))
        .fixedSize(horizontal: false, vertical: true)
        .help(Self.label(for: status))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sortie audio")
        .accessibilityValue(Self.label(for: status))
        .accessibilityIdentifier("output.badge")
    }

    /// Libellé affiché (UX §5.17) ; « Démarrage de la sortie audio… » et « Sortie audio arrêtée »
    /// pour les états transitoires, absents de l'UX.
    static func label(for status: AudioOutputStatus) -> String {
        switch status {
        case let .running(info): return info.name
        case .unavailable: return "Sortie audio indisponible"
        case .starting: return "Démarrage de la sortie audio\u{2026}"
        case .stopped: return "Sortie audio arrêtée"
        }
    }

    /// Icône SF Symbols selon le type de sortie, déduit du nom (UX §5.17).
    static func symbol(for status: AudioOutputStatus) -> String {
        switch status {
        case .unavailable, .stopped: return "speaker.slash"
        case .starting: return "speaker.wave.2"
        case let .running(info):
            let name = info.name.lowercased()
            if name.contains("(usb)") { return "cable.connector" }
            if name.contains("(hdmi)") { return "tv" }
            if name.contains("(airplay)") { return "airplayaudio" }
            if ["casque", "airpods", "headphone", "écouteurs", "beats"].contains(where: { name.contains($0) }) {
                return "headphones"
            }
            return "speaker.wave.2"
        }
    }

    static func isUnavailable(_ status: AudioOutputStatus) -> Bool {
        if case .unavailable = status { return true }
        return false
    }
}
