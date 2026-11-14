import ScratchCore
import SwiftUI

/// Rangée de transport d'une platine (spec 3.1 ; UX §5.2, §5.3) : START/STOP, 33⅓ / 45, puis les
/// emplacements de SET CUE et CUE (story 4.5).
struct TransportControls: View {
    let model: DeckViewModel
    let metrics: MainLayoutMetrics

    var body: some View {
        HStack(spacing: metrics.transportSpacing) {
            StartStopButton(model: model)
                .frame(width: metrics.startStopWidth, height: metrics.transportHeight)
            SpeedSelector(model: model, segmentWidth: metrics.speedSegmentWidth)
                .frame(height: metrics.transportHeight)
            // Slots reserved for SET CUE and CUE (story 4.5).
            Color.clear.frame(width: metrics.setCueWidth + metrics.transportSpacing + metrics.cueWidth)
                .accessibilityHidden(true)
        }
    }
}

/// START/STOP : agit **à l'appui**, sans annulation par glissement, jamais désactivé (UX §5.0,
/// §5.2). Le texte et le témoin suivent la commande du moteur (`motorOn`), pas la vitesse réelle.
struct StartStopButton: View {
    let model: DeckViewModel
    @State private var isPressed = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Theme.buttonRadius)
                .fill(isPressed ? Theme.bgPressed : Theme.bgRaised)
            Text(verbatim: model.startStopTitle)
                .font(Theme.controlLabel)
                .tracking(0.5)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Circle()
                .fill(model.motorOn ? Theme.stateOn : Theme.vuOff)
                .frame(width: 8, height: 8)
                .padding(6)
        }
        .scaleEffect(isPressed ? 0.97 : 1)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    model.toggleMotor()
                }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(model.startStopAccessibilityLabel)
        .accessibilityValue(model.startStopAccessibilityValue)
        .accessibilityInputLabels([model.startStopTitle])
        .accessibilityAction { model.toggleMotor() }
        .accessibilityIdentifier("deck.\(model.deck.rawValue.lowercased()).startStop")
    }
}

/// Sélecteur 33⅓ / 45 : deux segments, agit au relâchement (UX §5.3).
struct SpeedSelector: View {
    let model: DeckViewModel
    let segmentWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            segment(.rpm33, title: "33⅓", id: "speed33")
            segment(.rpm45, title: "45", id: "speed45")
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.buttonRadius))
    }

    private func segment(_ speed: TurntableSpeed, title: String, id: String) -> some View {
        let isSelected = model.speed == speed
        return Button { model.setSpeed(speed) } label: {
            Text(verbatim: title)
                .font(Theme.controlLabel)
                .foregroundStyle(isSelected ? Theme.textOnAccent : Theme.textSecondary)
                .frame(width: segmentWidth)
                .frame(maxHeight: .infinity)
                .background(isSelected ? Theme.deckColor(model.deck) : Theme.bgRaised)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(DeckFormatting.spokenSpeed(speed)), \(model.deckName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("deck.\(model.deck.rawValue.lowercased()).\(id)")
    }
}
