import ScratchCore
import SwiftUI

/// Réglage de courbe du crossfader (SF-66, D-30 ; UX §5.13) : « Douce » ↔ « Franche », valeur
/// « Coupure franche », « Douce » ou « 60 % » ; VoiceOver par pas de 10 %. Mini-graphique 44 × 28
/// des gains A et B (#75), sauf dans la table de l'iPad portrait, trop basse (176 pt, UX §4.4).
struct CrossfaderCurveControl: View {
    let mixer: MixerViewModel
    var showsGraph = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Tight row: « Coupure franche » must stay on one line in the 240-pt Mac mixer.
            HStack(spacing: 6) {
                Text(verbatim: "Courbe").font(Theme.sectionLabel).foregroundStyle(Theme.textSecondary)
                if showsGraph {
                    CurveGraph(curve: mixer.crossfaderCurve, hamster: mixer.hamster).equatable()
                }
                Spacer(minLength: 0)
                Text(verbatim: mixer.curveText).font(Theme.valueReadout).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
            }
            HStack(spacing: 6) {
                Text(verbatim: "Douce").font(Theme.caption).foregroundStyle(Theme.textSecondary)
                KnobFader(orientation: .horizontal, value: mixer.crossfaderCurve, knobLength: 20,
                          knobThickness: 28) { mixer.setCrossfaderCurve($0) }
                    .frame(height: 44)
                Text(verbatim: "Franche").font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Courbe du crossfader")
        .accessibilityValue(mixer.curveAccessibilityValue)
        .accessibilityAdjustableAction { mixer.nudgeCrossfaderCurve(steps: $0 == .increment ? 1 : -1) }
        .accessibilityIdentifier("mixer.curve")
        .keyboardAdjustable(id: "mixer.curve") { mixer.nudgeCrossfaderCurve(steps: $0) }
    }
}

/// Mini-graphique 44 × 28 des gains A (`deck.a`) et B (`deck.b`) de la courbe (UX §5.13 ; #75) :
/// redessiné seulement quand la courbe ou le hamster change (`equatable()`), jamais à chaque image.
/// Décoratif : masqué pour VoiceOver, la valeur textuelle suffit.
private struct CurveGraph: View, Equatable {
    let curve: Double
    let hamster: Bool

    var body: some View {
        Canvas { context, size in
            let samples = CurveGraphModel.samples(curve: curve, hamster: hamster, count: Int(size.width))
            func path(_ gain: (CurveGraphModel.Sample) -> Double) -> Path {
                var path = Path()
                for (index, sample) in samples.enumerated() {
                    let point = CGPoint(x: CGFloat(sample.x) * size.width,
                                        y: (size.height - 2) * CGFloat(1 - gain(sample)) + 1)
                    if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                return path
            }
            context.stroke(path { $0.gainA }, with: .color(Theme.deckColor(.a)), lineWidth: 1.5)
            context.stroke(path { $0.gainB }, with: .color(Theme.deckColor(.b)), lineWidth: 1.5)
        }
        .frame(width: 44, height: 28)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.bgInset))
        .accessibilityHidden(true)
    }
}
