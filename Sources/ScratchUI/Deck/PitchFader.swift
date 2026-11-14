import ScratchCore
import SwiftUI

/// Fader PITCH vertical à droite du disque (SF-11, D-31 ; UX §5.4) : « + » en haut, −8 % à +8 % par
/// pas de 0,1 %, saisie par le bouton seulement (déplacement relatif, cran de 6 pt à 0 %), valeur
/// toujours signée, témoin « 0 », remise à 0 % par double-toucher sur le fader ou par le bouton « 0 ».
/// Toujours actif, même sur une platine vide.
struct PitchFader: View {
    let model: DeckViewModel
    let height: CGFloat
    /// Libellé « PITCH » omis en iPhone paysage.
    var showsLabel = true

    @State private var drag: FaderDragModel?

    var body: some View {
        let id = "deck.\(model.deck.rawValue.lowercased())"
        VStack(spacing: 4) {
            if showsLabel {
                Text(verbatim: "PITCH").font(Theme.sectionLabel).foregroundStyle(Theme.textSecondary)
            }
            Text(verbatim: model.pitchText)
                .font(.system(size: showsLabel ? 13 : 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GeometryReader { proxy in track(height: proxy.size.height) }
                .contentShape(Rectangle())
                .accessibilityElement()
                .accessibilityLabel("Pitch, \(model.deckName)")
                .accessibilityValue(model.pitchText)
                .accessibilityAdjustableAction { model.nudgePitch(steps: $0 == .increment ? 1 : -1) }
                .accessibilityAction(named: "Remettre à zéro") { model.resetPitch() }
                .accessibilityIdentifier("\(id).pitch")
            Button { model.resetPitch() } label: {
                Text(verbatim: "0")
                    .font(Theme.controlLabel)
                    .foregroundStyle(model.isPitchZero ? Theme.stateOn : Theme.textPrimary)
                    .frame(width: 44, height: 32)
                    .background(RoundedRectangle(cornerRadius: Theme.buttonRadius).fill(Theme.bgRaised))
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remettre le pitch à zéro, \(model.deckName)")
            .accessibilityIdentifier("\(id).pitchReset")
        }
        .frame(width: 44, height: height)
        // Double tap anywhere on the fader resets the pitch; the drag of the knob does not move it.
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.resetPitch() })
    }

    /// Piste de 4 pt, graduations +8 / 0 / −8 et traits à ±2, ±4, ±6, bouton 36 × 20.
    private func track(height: CGFloat) -> some View {
        let knob: CGFloat = 20
        let travel = max(1, height - knob)
        let range = TurntableConstants.pitchRange
        let fraction = (model.pitch - range.lowerBound) / (range.upperBound - range.lowerBound)
        let knobY = (1 - fraction) * travel + knob / 2
        return ZStack(alignment: .top) {
            Capsule().fill(Theme.strokeStrong).frame(width: 4).frame(maxHeight: .infinity)
            ForEach(-4...4, id: \.self) { mark in
                Rectangle()
                    .fill(mark == 0 ? Theme.stateOn : Theme.strokeSubtle)
                    .frame(width: mark % 2 == 0 ? 14 : 8, height: 1)
                    .offset(y: knob / 2 + (1 - (Double(mark) + 4) / 8) * travel)
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(drag == nil ? Theme.knob : Theme.textPrimary)
                .overlay(Rectangle().fill(Theme.bgApp).frame(width: 22, height: 2))
                .frame(width: 36, height: knob)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .offset(y: knobY - 22)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            var current = drag ?? FaderDragModel.pitch(travel: Double(travel))
                            if drag == nil { current.begin(at: model.pitch) }
                            drag = current
                            let value = current.value(afterDrag: Double(-gesture.translation.height))
                            if abs(value - model.pitch) > 1e-9 { model.setPitch(value) }
                        }
                        .onEnded { _ in drag = nil }
                )
        }
        .frame(maxWidth: .infinity)
    }
}
