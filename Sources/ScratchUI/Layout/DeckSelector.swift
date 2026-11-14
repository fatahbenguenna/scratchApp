import ScratchCore
import SwiftUI

/// Sélecteur de la platine affichée en iPhone portrait (spec 2, 6.8 ; UX §5.18) : deux segments
/// 56 × 36 (zone tactile 44), lettre et pastille d'état. Bascule immédiate (fondu de 150 ms, sans
/// « Réduire les animations ») ; la platine masquée continue de jouer ; un disque tenu sur la platine
/// quittée est relâché (annulation de la 4.3, RM-60).
struct DeckSelector: View {
    /// Pastille d'état : aucune (vide), cercle vide (son chargé, moteur arrêté), cercle plein (moteur
    /// en marche).
    enum Dot: Equatable { case none, hollow, filled }

    let model: AppModel
    @Binding var selected: DeckID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            segment(.a)
            segment(.b)
        }
        .background(RoundedRectangle(cornerRadius: Theme.buttonRadius).fill(Theme.bgSurface))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deckSelector")
    }

    private func segment(_ id: DeckID) -> some View {
        let deck = model.deck(id)
        let isSelected = id == selected
        return Button { select(id) } label: {
            HStack(spacing: 6) {
                Text(verbatim: id.rawValue)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(isSelected ? Theme.deckColor(id) : Theme.textSecondary)
                dot(Self.dot(for: deck), color: Theme.deckColor(id))
            }
            .frame(width: 56, height: 36)
            .background(RoundedRectangle(cornerRadius: Theme.buttonRadius).fill(isSelected ? Theme.bgRaised : .clear))
            .overlay(alignment: .bottom) {
                if isSelected { Rectangle().fill(Theme.deckColor(id)).frame(height: 2) }
            }
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Platine \(id.rawValue)")
        .accessibilityValue(Self.accessibilityValue(for: deck, displayed: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("deckSelector.\(id.rawValue.lowercased())")
    }

    @ViewBuilder
    private func dot(_ dot: Dot, color: Color) -> some View {
        switch dot {
        case .none: Color.clear.frame(width: 6, height: 6)
        case .hollow: Circle().stroke(color, lineWidth: 1).frame(width: 6, height: 6)
        case .filled: Circle().fill(color).frame(width: 6, height: 6)
        }
    }

    private func select(_ id: DeckID) {
        guard id != selected else { return }
        model.deck(selected).discInput.cancelAll()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { selected = id }
    }

    @MainActor
    static func dot(for deck: DeckViewModel) -> Dot {
        guard deck.isLoaded else { return .none }
        return deck.motorOn ? .filled : .hollow
    }

    /// Valeur VoiceOver : « affichée, moteur en marche », « son chargé, à l'arrêt », « vide ».
    @MainActor
    static func accessibilityValue(for deck: DeckViewModel, displayed: Bool) -> String {
        let state: String
        switch dot(for: deck) {
        case .none: state = "vide"
        case .hollow: state = "son chargé, à l'arrêt"
        case .filled: state = "moteur en marche"
        }
        return displayed ? "affichée, " + state : state
    }
}
