import ScratchCore
import SwiftUI

/// Forme d'onde zoomée (story 4.6 CA 2 ; SF-70, D-13 ; UX §5.7).
///
/// - Fenêtre de ±1,8 s, tête fixe au centre : le son défile de droite à gauche en lecture avant, de
///   gauche à droite en arrière, selon `frame.positionSeconds` (jamais selon l'angle du disque ; en
///   butée, la bande ne défile plus).
/// - Seule vue de la bande lue à chaque image : elle ne fait que translater deux ou trois tuiles de
///   512 pt rendues une fois (`WaveformTile`, comparées par valeur) et placer la tête et le CUE ;
///   l'enveloppe n'est jamais recalculée à chaque image (UX §10.2).
/// - Amorce et zone après la fin hachurées ; vide ou pendant l'analyse : ligne médiane.
/// - Décorative : masquée pour VoiceOver (la position est dans l'en-tête).
struct ZoomedWaveformView: View {
    let model: DeckViewModel
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        let geometry = ZoomGeometry(width: Double(width))
        let position = model.frame.positionSeconds
        ZStack(alignment: .topLeading) {
            Theme.bgInset
            if model.isLoaded, let peaks = model.peaks {
                let tiles = geometry.visibleTiles(position: position)
                ForEach(Array(tiles), id: \.self) { index in
                    WaveformTile(peaks: peaks, index: index, geometry: geometry, height: height,
                                 color: Theme.deckColor(model.deck))
                        .equatable()
                        .frame(width: ZoomGeometry.tileWidth, height: height)
                        .offset(x: geometry.tileOffset(index, position: position))
                }
            } else {
                Rectangle().fill(Theme.textDisabled).frame(height: 1).offset(y: height / 2)
            }
            if model.isLoaded {
                if let cue = model.cueSeconds {
                    CueFlag(height: height, flash: model.setCueCount)
                        .offset(x: CGFloat(geometry.x(of: cue, position: position)) - CueFlag.width / 2)
                }
                Rectangle().fill(Color.white).frame(width: 2, height: height).offset(x: width / 2 - 1)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .transaction { $0.animation = nil }
        .accessibilityHidden(true)
        .accessibilityIdentifier("deck.\(model.deck.rawValue.lowercased()).waveform")
    }
}

/// Tuile de 512 pt de la forme d'onde zoomée : une barre min/max par point, hachures hors du son.
/// Rendue une fois par son, largeur et hauteur ; `equatable()` évite de la redessiner quand seule
/// la position change.
private struct WaveformTile: View, Equatable {
    let peaks: WaveformPeaks
    let index: Int
    let geometry: ZoomGeometry
    let height: CGFloat
    let color: Color

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.peaks === rhs.peaks && lhs.index == rhs.index && lhs.geometry == rhs.geometry
            && lhs.height == rhs.height && lhs.color == rhs.color
    }

    var body: some View {
        Canvas { context, size in
            let range = geometry.tileRange(index)
            let step = geometry.secondsPerPoint
            let middle = size.height / 2
            let amplitude = size.height / 2 - 1
            var bars = Path()
            for column in 0..<Int(ZoomGeometry.tileWidth) {
                let start = range.lowerBound + Double(column) * step
                guard let envelope = peaks.envelope(from: start, to: start + step) else { continue }
                let top = middle - CGFloat(envelope.max) * amplitude
                let bottom = middle - CGFloat(envelope.min) * amplitude
                bars.addRect(CGRect(x: CGFloat(column), y: top, width: 1, height: max(1, bottom - top)))
            }
            context.fill(bars, with: .color(color))
            for outside in ZoomGeometry.outsideRanges(of: range, duration: peaks.duration) {
                let x0 = (outside.lowerBound - range.lowerBound) / step
                let x1 = (outside.upperBound - range.lowerBound) / step
                WaveformHatching.draw(in: CGRect(x: CGFloat(x0), y: 0, width: CGFloat(x1 - x0), height: size.height),
                                      context: context)
            }
        }
    }
}

/// Hachures à 45° (`stroke.subtle`, pas de 4 pt) de l'amorce et de la zone après la fin (UX §5.7).
/// Le pas est aligné sur l'origine de la tuile (512 est un multiple de 4) : les hachures se
/// raccordent d'une tuile à l'autre.
enum WaveformHatching {
    static let spacing: CGFloat = 4

    static func draw(in rect: CGRect, context: GraphicsContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        var lines = Path()
        var x = (rect.minX / spacing).rounded(.down) * spacing
        while x < rect.maxX + rect.height {
            lines.move(to: CGPoint(x: x, y: rect.minY))
            lines.addLine(to: CGPoint(x: x - rect.height, y: rect.maxY))
            x += spacing
        }
        var clipped = context
        clipped.clip(to: Path(rect))
        clipped.stroke(lines, with: .color(Theme.strokeSubtle), lineWidth: 1)
    }
}

/// Marqueur CUE de la bande zoomée : trait `cue` de 2 pt et fanion triangulaire de 6 pt en haut ;
/// bref éclat de 150 ms après un SET CUE (supprimé avec « Réduire les animations », UX §5.6).
private struct CueFlag: View {
    static let width: CGFloat = 8
    let height: CGFloat
    let flash: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(Theme.cue).frame(width: 2, height: height)
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: Self.width, y: 0))
                path.addLine(to: CGPoint(x: Self.width / 2, y: 6))
                path.closeSubpath()
            }
            .fill(Theme.cue)
            .frame(width: Self.width, height: 6)
        }
        .frame(width: Self.width, height: height, alignment: .top)
        .cueFlash(flash, reduceMotion: reduceMotion)
    }
}

extension View {
    /// Éclat de 150 ms du marqueur CUE après un SET CUE (`setCueCount`), aucun avec « Réduire les
    /// animations ».
    func cueFlash(_ count: Int, reduceMotion: Bool) -> some View {
        keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : count) { content, glow in
            content
                .shadow(color: Theme.cue.opacity(glow), radius: 6 * glow)
                .brightness(0.3 * glow)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(1.0, duration: 0.05)
                LinearKeyframe(0.0, duration: 0.1)
            }
        }
    }
}

#if DEBUG
#Preview("Formes d'onde, platine A en lecture") {
    let environment = PreviewEnvironment(scenario: .playing)
    let deck = environment.model.deckA
    return VStack(spacing: 6) {
        ZoomedWaveformView(model: deck, width: 448, height: 56)
        WaveformOverviewView(model: deck, width: 448, height: 28).frame(height: 32)
    }
    .padding(24)
    .background(Theme.bgSurface)
    .preferredColorScheme(.dark)
}
#endif
