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
        let showsImportText = width >= 320
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
            .padding(.trailing, showsImportText ? 112 : 48)   // room for the Import button
            // The time readout never truncates; only the status pills give way.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                PositionText(model: model).fixedSize().layoutPriority(2)
                Text(verbatim: "/ " + model.durationText)
                    .font(Theme.timeDuration)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize()
                    .layoutPriority(1)
                if model.isAtEnd { StatusPill(text: "Fin du son", showsProgress: false) }
                if let activity = model.activityText { StatusPill(text: activity, showsProgress: true) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.headerAccessibilityLabel)
        .accessibilityValue(model.headerAccessibilityValue)
        .accessibilityIdentifier("\(id).title")
        .overlay(alignment: .topTrailing) {
            Button { intents.importFile(on: model.deck) } label: {
                if showsImportText {
                    Label("Importer", systemImage: "square.and.arrow.down")
                } else {
                    Image(systemName: "square.and.arrow.down")
                }
            }
            .buttonStyle(RaisedButtonStyle(compact: true))
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
