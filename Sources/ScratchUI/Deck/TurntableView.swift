import ScratchCore
import SwiftUI

/// Disque d'une platine : plateau, feutrine ou vinyle, étiquette, repère (UX §5.1 ; SF-69, SF-70).
///
/// Seules les couches tournantes lisent `frame` et sont réévaluées à chaque image ; elles tournent par
/// `rotationEffect` sans animation, sur des dessins qui ne changent qu'avec la taille ou le son
/// (UX §10.2). Angles du contrat : radians, sens horaire positif, 0 = midi ; le repère est dessiné à
/// midi puis tourné de `stickerAngle` (D-10). Aucune saisie ici (story 4.3).
struct TurntableView: View {
    let model: DeckViewModel
    let intents: any DeckIntents
    /// Diamètre du plateau P.
    let platter: CGFloat

    var body: some View {
        let disc = platter * 0.92
        ZStack {
            Circle().fill(Theme.platter)
            RotatingLayer(model: model, angle: \.platterAngle) { StrobeMarks(platter: platter).equatable() }
            if model.isLoaded || model.activity != .idle {
                VinylSurface(diameter: disc).equatable()
            }
            if model.isLoaded {
                RotatingLayer(model: model, angle: \.discAngle) {
                    DiscLabel(deck: model.deck, title: model.title, disc: disc).equatable()
                }
                RotatingLayer(model: model, angle: \.stickerAngle) { Sticker(disc: disc).equatable() }
            } else if model.activity == .idle {
                RotatingLayer(model: model, angle: \.platterAngle) {
                    Slipmat(deck: model.deck, disc: disc).equatable()
                }
            }
            Circle().fill(Theme.knob).frame(width: disc * 0.025, height: disc * 0.025)
            PlayheadMarker(platter: platter)
            Circle()
                .strokeBorder(Theme.deckColor(model.deck), lineWidth: 3)
                .frame(width: disc, height: disc)
                .opacity(model.isHeld ? 1 : 0)
                .animation(model.isHeld ? nil : .easeOut(duration: 0.08), value: model.isHeld)
        }
        .frame(width: platter, height: platter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Disque, \(model.deckName)")
        .accessibilityValue(model.discAccessibilityValue)
        .accessibilityHint("Interaction directe. Posez un doigt pour retenir le disque, tournez pour scratcher.")
        #if os(iOS)
        .accessibilityAddTraits(.allowsDirectInteraction)
        #endif
        .accessibilityIdentifier("deck.\(model.deck.rawValue.lowercased()).disc")
        .overlay {
            if model.showsEmptyActions {
                EmptyDeckOverlay(model: model, intents: intents, disc: disc)
            } else if !model.isLoaded {
                DelayedProgressView()
            }
        }
    }
}

/// Couche qui tourne à un angle de l'instantané : la seule partie du disque réévaluée à chaque image.
private struct RotatingLayer<Content: View>: View {
    let model: DeckViewModel
    let angle: KeyPath<DeckSnapshot, Double>
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .rotationEffect(.radians(model.frame[keyPath: angle]))
            .transaction { $0.animation = nil }
    }
}

/// Anneau du plateau : 16 marques stroboscopiques de 3 pt × 0,03 P entre D et P (UX §5.1, §10.3).
private struct StrobeMarks: View, Equatable {
    let platter: CGFloat

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let length = platter * 0.03
            let outer = platter / 2 - (platter * 0.04 - length) / 2
            for index in 0..<16 {
                var mark = context
                mark.translateBy(x: center.x, y: center.y)
                mark.rotate(by: .radians(Double(index) * .pi / 8))
                mark.fill(Path(CGRect(x: -1.5, y: -outer, width: 3, height: length)), with: .color(Theme.strobe))
            }
        }
        .frame(width: platter, height: platter)
    }
}

/// Vinyle de révolution : sillons tous les 3 pt entre 0,36 R et 0,97 R, reflet fixe (UX §5.1).
private struct VinylSurface: View, Equatable {
    let diameter: CGFloat

    var body: some View {
        Canvas { context, size in
            let radius = diameter / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            context.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)), with: .color(Theme.vinyl))
            var groove = radius * 0.36
            while groove <= radius * 0.97 {
                let rect = CGRect(x: center.x - groove, y: center.y - groove, width: 2 * groove, height: 2 * groove)
                context.stroke(Path(ellipseIn: rect), with: .color(Theme.groove), lineWidth: 1)
                groove += 3
            }
            let sheen = Gradient(colors: [.white.opacity(0), .white.opacity(0.07), .white.opacity(0),
                                          .white.opacity(0), .white.opacity(0.07), .white.opacity(0)])
            context.fill(Path(ellipseIn: CGRect(origin: .zero, size: size)),
                         with: .conicGradient(sheen, center: center, angle: .degrees(-30)))
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Feutrine d'une platine vide : anneau imprimé et lettre de la platine (UX §5.1).
private struct Slipmat: View, Equatable {
    let deck: DeckID
    let disc: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Theme.slipmat)
            Circle().stroke(Theme.strokeSubtle, lineWidth: 2).padding(disc * 0.06)
            Text(verbatim: deck.rawValue)
                .font(.system(size: disc * 0.08, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.deckColor(deck).opacity(0.6))
                .offset(y: -disc * 0.38)
        }
        .frame(width: disc, height: disc)
    }
}

/// Étiquette : couleur de la platine, lettre (0,12 D) et titre sur deux lignes (0,035 D).
private struct DiscLabel: View, Equatable {
    let deck: DeckID
    let title: String
    let disc: CGFloat

    var body: some View {
        let size = disc * 0.33
        ZStack {
            Circle().fill(Theme.labelColor(deck))
            VStack(spacing: disc * 0.01) {
                Text(verbatim: deck.rawValue).font(.system(size: disc * 0.12, weight: .bold, design: .rounded))
                Text(verbatim: title)
                    .font(.system(size: disc * 0.035, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
                    .frame(width: size * 0.7)
            }
            .foregroundStyle(Theme.textPrimary)
            .offset(y: disc * 0.02)
        }
        .frame(width: size, height: size)
    }
}

/// Repère (autocollant) : 0,035 D × 0,10 D, de 0,06 D à 0,16 D du centre, dessiné à midi.
private struct Sticker: View, Equatable {
    let disc: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: disc * 0.008)
            .fill(Theme.cue)
            .overlay(RoundedRectangle(cornerRadius: disc * 0.008).stroke(Theme.bgApp, lineWidth: 1))
            .frame(width: disc * 0.035, height: disc * 0.10)
            .offset(y: -disc * 0.11)
            .frame(width: disc, height: disc)
    }
}

/// Repère de lecture fixe à midi, posé sur l'anneau du plateau, pointe vers le centre.
private struct PlayheadMarker: View {
    let platter: CGFloat

    var body: some View {
        let scale = min(1, platter / 300)
        Path { path in
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 12 * scale, y: 0))
            path.addLine(to: CGPoint(x: 6 * scale, y: 8 * scale))
            path.closeSubpath()
        }
        .fill(Theme.textPrimary)
        .frame(width: 12 * scale, height: 8 * scale)
        .offset(y: -platter / 2 + platter * 0.005 + 4 * scale)
        .accessibilityHidden(true)
    }
}

/// Indicateur d'activité affiché après 150 ms seulement (UX §5.1).
private struct DelayedProgressView: View {
    @State private var isVisible = false

    var body: some View {
        ProgressView()
            .opacity(isVisible ? 1 : 0)
            .task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                isVisible = true
            }
    }
}
