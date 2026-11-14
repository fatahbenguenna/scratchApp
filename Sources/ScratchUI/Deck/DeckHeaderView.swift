import SwiftUI

/// En-tête de platine (spec 3.1, SF-03, D-12, D-28 ; UX §5.10) : lettre, titre tronqué au milieu,
/// « Importer », position `mm:ss,d` / durée et pastilles d'état.
///
/// Lettre, titre et position forment un seul élément VoiceOver (« Platine A, « titre » », valeur
/// « position 12,3 secondes sur 3 minutes 45 secondes »).
struct DeckHeaderView: View {
    let model: DeckViewModel
    let intents: any DeckIntents
    /// Largeur de la colonne : le texte « Importer » s'affiche à partir de 320 pt.
    let width: CGFloat

    var body: some View {
        let id = "deck.\(model.deck.rawValue.lowercased())"
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(verbatim: model.deck.rawValue)
                        .font(Theme.deckLetter)
                        .foregroundStyle(Theme.textOnAccent)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.deckColor(model.deck)))
                    Text(verbatim: model.title)
                        .font(Theme.deckTitle)
                        .foregroundStyle(model.hasTitle ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    PositionText(model: model)
                    Text(verbatim: "/").font(Theme.timeDuration).foregroundStyle(Theme.textSecondary)
                    Text(verbatim: model.durationText).font(Theme.timeDuration).foregroundStyle(Theme.textSecondary)
                    if model.isAtEnd { StatusPill(text: "Fin du son", showsProgress: false) }
                    if let activity = model.activityText { StatusPill(text: activity, showsProgress: true) }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.headerAccessibilityLabel)
            .accessibilityValue(model.headerAccessibilityValue)
            .accessibilityIdentifier("\(id).title")
            Spacer(minLength: 0)
            Button { intents.importFile(on: model.deck) } label: {
                if width >= 320 {
                    Label("Importer", systemImage: "square.and.arrow.down")
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .buttonStyle(RaisedButtonStyle())
            .disabled(!model.isImportEnabled)
            .accessibilityLabel("Importer, \(model.deckName)")
            .accessibilityIdentifier("\(id).import")
        }
        .frame(height: 52)
    }
}

/// Position de la tête : seule partie de l'en-tête qui suit la lecture (au dixième).
private struct PositionText: View {
    let model: DeckViewModel

    var body: some View {
        Text(verbatim: model.positionText)
            .font(Theme.timePosition)
            .foregroundStyle(model.isLoaded ? Theme.textPrimary : Theme.textSecondary)
            .accessibilityIdentifier("deck.\(model.deck.rawValue.lowercased()).position")
    }
}

/// Pastille d'état (« Fin du son », « Import de « nom »… », « Chargement… »).
private struct StatusPill: View {
    let text: String
    let showsProgress: Bool

    var body: some View {
        HStack(spacing: 4) {
            if showsProgress { ProgressView().controlSize(.mini) }
            Text(verbatim: text).font(Theme.caption).lineLimit(1).truncationMode(.middle)
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Theme.bgRaised))
    }
}
