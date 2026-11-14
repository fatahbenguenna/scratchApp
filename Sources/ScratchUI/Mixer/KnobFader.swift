import SwiftUI

/// Fader générique de l'écran principal (UX §5.0 « règles communes aux faders ») : saisie par le
/// bouton seulement (un toucher sur la piste hors du bouton ne fait rien), déplacement relatif
/// depuis le point de saisie, zone de saisie d'au moins 44 × 44. Valeur 0…1 ; en vertical, 1 en haut.
/// Chaque position part vers le modèle dans le cycle d'événements qui la reçoit. Réutilisé par la 4.5
/// (pitch, résistance).
struct KnobFader: View {
    enum Orientation { case vertical, horizontal }

    let orientation: Orientation
    let value: Double
    /// Taille visuelle du bouton, dans l'axe puis en travers (36 × 20 pour un fader de voie).
    var knobLength: CGFloat = 20
    var knobThickness: CGFloat = 36
    let onChange: (Double) -> Void

    @State private var grabValue: Double?

    var body: some View {
        GeometryReader { proxy in
            let isVertical = orientation == .vertical
            let extent = isVertical ? proxy.size.height : proxy.size.width
            let travel = max(1, extent - knobLength)
            let offset = (isVertical ? 1 - value : value) * travel + knobLength / 2
            ZStack(alignment: isVertical ? .top : .leading) {
                Capsule()
                    .fill(Theme.strokeStrong)
                    .frame(width: isVertical ? 4 : nil, height: isVertical ? nil : 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.knob)
                    .overlay(Rectangle().fill(Theme.bgApp).frame(width: isVertical ? knobThickness * 0.6 : 2,
                                                                 height: isVertical ? 2 : knobThickness * 0.6))
                    .frame(width: isVertical ? knobThickness : knobLength,
                           height: isVertical ? knobLength : knobThickness)
                    .frame(width: max(44, isVertical ? knobThickness : knobLength + 16),
                           height: max(44, isVertical ? knobLength + 16 : knobThickness))
                    .contentShape(Rectangle())
                    .gesture(drag(travel: travel, isVertical: isVertical))
                    .offset(x: isVertical ? 0 : offset - max(44, knobLength + 16) / 2,
                            y: isVertical ? offset - max(44, knobLength + 16) / 2 : 0)
                    .frame(maxWidth: isVertical ? .infinity : nil, maxHeight: isVertical ? nil : .infinity)
            }
        }
    }

    private func drag(travel: CGFloat, isVertical: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let start = grabValue ?? value
                grabValue = start
                let delta = isVertical ? -gesture.translation.height : gesture.translation.width
                onChange(min(1, max(0, start + Double(delta / travel))))
            }
            .onEnded { _ in grabValue = nil }
    }
}
