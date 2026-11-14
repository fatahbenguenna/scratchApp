import ScratchCore
import ScratchLibrary
import SwiftUI

/// Ligne de la bibliothèque (UX §5.19).
///
/// Contenu, de gauche à droite : icône, nom (deux lignes au plus, troncature au milieu),
/// sous-titre, pastilles « Sur A » / « Sur B », puis boutons de chargement. Les boutons valent
/// « Charger sur A » et « Charger sur B » sur iPad et Mac, « A » et « B » en largeur compacte
/// (iPhone). « Supprimer » est proposé par balayage et menu contextuel, jamais pour la démo.
struct LibraryRow: View {
    let row: LibraryRowItem
    let compact: Bool
    let onLoad: (DeckID) -> Void
    /// `nil` pour la démo : aucune action « Supprimer ».
    let onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.isDemo ? "sparkles" : "waveform")
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body)
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text(row.subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityValue(row.accessibilityValue ?? "")
            .accessibilityActions { actions }
            Spacer(minLength: 8)
            ForEach(row.loadedOn, id: \.self) { deck in
                Text("Sur \(deck.rawValue)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textOnAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.deckColor(deck)))
                    .accessibilityHidden(true)
            }
            ForEach(DeckID.allCases, id: \.self) { deck in
                Button(compact ? deck.rawValue : "Charger sur \(deck.rawValue)") { onLoad(deck) }
                    .buttonStyle(.bordered)
                    .tint(Theme.deckColor(deck))
                    .frame(minWidth: compact ? 44 : nil, minHeight: 44)
                    .accessibilityLabel("Charger sur la platine \(deck.rawValue)")
                    .accessibilityIdentifier("\(row.identifier).load\(deck.rawValue)")
            }
        }
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Charger sur A") { onLoad(.a) }
            Button("Charger sur B") { onLoad(.b) }
            if let onDelete {
                Button("Supprimer…", role: .destructive, action: onDelete)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if let onDelete {
                Button("Supprimer", action: onDelete).tint(Self.danger)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(row.identifier)
    }

    /// Couleur `danger` de l'UX (§9.2).
    static let danger = Color(hex: 0xFF6369)

    @ViewBuilder
    private var actions: some View {
        Button("Charger sur la platine A") { onLoad(.a) }
        Button("Charger sur la platine B") { onLoad(.b) }
        if let onDelete {
            Button("Supprimer", action: onDelete)
        }
    }
}
