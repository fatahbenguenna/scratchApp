import ScratchCore
import SwiftUI

/// Aperçu complet et needle drop (story 4.6 CA 3, 4, 6 ; SF-70, SF-71, SF-72, D-33 ; UX §5.8).
///
/// - Le son entier sur [−2 s ; durée] : amorce hachurée au début, enveloppe opaque à gauche de la
///   tête et à 50 % à droite, tête blanche de 2 pt, CUE en triangle `cue` de 8 pt sur le bord bas.
/// - L'enveloppe est réduite une fois par largeur (`OverviewEnvelope`) ; à chaque image, seuls le
///   masque de la partie lue et la tête bougent (`OverviewProgress`).
/// - Needle drop au relâchement (`NeedleDropGesture`) : tête fantôme pointillée et bulle de temps
///   « 01:23,4 » ; zone tactile de 44 pt qui déborde vers le haut, sur la forme d'onde zoomée.
/// - Sur Mac (et au pointeur sur iPad), le survol montre un trait fin et la bulle de temps.
/// - VoiceOver : « Aperçu du son, platine A », ajustable par ± 5 % de la durée.
struct WaveformOverviewView: View {
    let model: DeckViewModel
    let width: CGFloat
    /// Hauteur visuelle : 28 (iPhone portrait, Mac), 24 (compacte), 20 (iPhone paysage), 32 (iPad).
    let height: CGFloat

    static let touchHeight: CGFloat = 44

    @State private var gesture = NeedleDropGesture()
    /// Point de départ du geste suivi : un autre point de départ signale un nouveau geste, même si
    /// le précédent n'a pas reçu de fin (geste interrompu par le système).
    @State private var dragStart: CGPoint?
    @State private var hoverX: CGFloat?
    /// Vrai pendant le glisser ; remis à faux par SwiftUI à la fin **et** à l'annulation par le système
    /// (rotation, changement de disposition, appel, geste prioritaire), qui n'appelle pas `onEnded`
    /// (#102).
    @GestureState private var isDragging = false

    private var overflow: CGFloat { max(0, Self.touchHeight - height) }

    var body: some View {
        let enabled = model.isLoaded && model.durationSeconds > 0
        let geometry = OverviewGeometry(width: Double(width), duration: model.durationSeconds)
        let color = Theme.deckColor(model.deck)
        ZStack(alignment: .topLeading) {
            Theme.bgInset
            if enabled {
                LeadInHatching(geometry: geometry, height: height).equatable()
                if let peaks = model.peaks {
                    OverviewEnvelope(peaks: peaks, geometry: geometry, height: height, color: color)
                        .equatable()
                        .opacity(0.5)
                }
                OverviewProgress(model: model, geometry: geometry, height: height, color: color)
                if let cue = model.cueSeconds {
                    CueTriangle()
                        .cueFlash(model.setCueCount, reduceMotion: reduceMotion)
                        .offset(x: CGFloat(geometry.x(of: cue)) - CueTriangle.size / 2, y: height - CueTriangle.size)
                }
            } else {
                Rectangle().fill(Theme.textDisabled).frame(height: 1).offset(y: height / 2)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .topLeading) { indicator(geometry: geometry) }
        .padding(.top, overflow)
        .contentShape(Rectangle())
        .gesture(needleDrop(geometry: geometry), including: enabled ? .all : .subviews)
        .onChange(of: isDragging) {
            // Ended normally: `onEnded` has already reset the state. Cancelled: hide the ghost.
            if !isDragging, gesture.isActive {
                gesture.reset()
                dragStart = nil
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case let .active(location): hoverX = enabled ? location.x : nil
            case .ended: hoverX = nil
            }
        }
        .padding(.top, -overflow)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aperçu du son, \(model.deckName)")
        .accessibilityValue(model.overviewAccessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: model.nudgeNeedle(steps: 1)
            case .decrement: model.nudgeNeedle(steps: -1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("deck.\(model.deck.rawValue.lowercased()).overview")
        .keyboardAdjustable(id: "deck.\(model.deck.rawValue.lowercased()).overview") { model.nudgeNeedle(steps: $0) }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Tête fantôme et bulle pendant un geste ; trait fin et bulle au survol.
    @ViewBuilder
    private func indicator(geometry: OverviewGeometry) -> some View {
        if let x = gesture.ghostX {
            let clamped = min(max(CGFloat(x), 0), width)
            Path { path in
                path.move(to: CGPoint(x: clamped, y: 0))
                path.addLine(to: CGPoint(x: clamped, y: height))
            }
            .stroke(Theme.textPrimary, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
            timeBubble(x: clamped, seconds: geometry.seconds(atX: Double(clamped)))
        } else if !gesture.isActive, let x = hoverX {
            let clamped = min(max(x, 0), width)
            Rectangle().fill(Theme.textPrimary.opacity(0.6)).frame(width: 1, height: height).offset(x: clamped)
            timeBubble(x: clamped, seconds: geometry.seconds(atX: Double(clamped)))
        }
    }

    /// Bulle « 01:23,4 » au-dessus de la zone tactile, maintenue dans la largeur de l'aperçu.
    private func timeBubble(x: CGFloat, seconds: Double) -> some View {
        let half: CGFloat = 40
        let center = width > 2 * half ? min(max(x, half), width - half) : width / 2
        return Text(verbatim: DeckFormatting.clockText(tenths: DeckFormatting.tenths(seconds)))
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.bgRaised))
            .fixedSize()
            .position(x: center, y: -overflow - 15)
            .allowsHitTesting(false)
    }

    private func needleDrop(geometry: OverviewGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                // Local space includes the upward overflow: the touch zone is [0, max(44, height)].
                let zone = Double(max(Self.touchHeight, height))
                if gesture.isActive, dragStart == value.startLocation {
                    gesture.move(x: value.location.x, y: value.location.y, zoneHeight: zone)
                } else {
                    dragStart = value.startLocation
                    gesture.begin(x: value.startLocation.x, y: value.startLocation.y, zoneHeight: zone,
                                  isHeld: model.isDiscHeld)
                    gesture.move(x: value.location.x, y: value.location.y, zoneHeight: zone)
                }
            }
            .onEnded { value in
                dragStart = nil
                let zone = Double(max(Self.touchHeight, height))
                if let x = gesture.end(x: value.location.x, y: value.location.y, zoneHeight: zone,
                                       isHeld: model.isDiscHeld) {
                    model.needleDrop(toSeconds: geometry.seconds(atX: x))
                }
            }
    }
}

/// Enveloppe de l'aperçu, réduite à une barre par point de largeur : recalculée seulement quand le
/// son, la largeur ou la hauteur change (`equatable()`), jamais à chaque image.
private struct OverviewEnvelope: View, Equatable {
    let peaks: WaveformPeaks
    let geometry: OverviewGeometry
    let height: CGFloat
    let color: Color

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.peaks === rhs.peaks && lhs.geometry == rhs.geometry && lhs.height == rhs.height && lhs.color == rhs.color
    }

    var body: some View {
        Canvas { context, size in
            let columns = Int(size.width.rounded(.up))
            guard columns > 0, geometry.span > 0 else { return }
            let step = geometry.span / Double(size.width)
            let middle = size.height / 2
            let amplitude = size.height / 2 - 1
            var bars = Path()
            for column in 0..<columns {
                let start = geometry.start + Double(column) * step
                guard let envelope = peaks.envelope(from: start, to: start + step) else { continue }
                let top = middle - CGFloat(envelope.max) * amplitude
                let bottom = middle - CGFloat(envelope.min) * amplitude
                bars.addRect(CGRect(x: CGFloat(column), y: top, width: 1, height: max(1, bottom - top)))
            }
            context.fill(bars, with: .color(color))
        }
        .frame(height: height)
    }
}

/// Amorce [−2 s ; 0[ hachurée, proportionnelle, au début de l'aperçu (UX §5.8).
private struct LeadInHatching: View, Equatable {
    let geometry: OverviewGeometry
    let height: CGFloat

    var body: some View {
        Canvas { context, size in
            WaveformHatching.draw(in: CGRect(x: 0, y: 0, width: CGFloat(geometry.x(of: 0)), height: size.height),
                                  context: context)
        }
        .frame(height: height)
    }
}

/// Partie lue de l'aperçu (enveloppe opaque à gauche de la tête) et tête de lecture : seule partie
/// de l'aperçu lue à chaque image.
private struct OverviewProgress: View {
    let model: DeckViewModel
    let geometry: OverviewGeometry
    let height: CGFloat
    let color: Color

    var body: some View {
        let x = CGFloat(geometry.x(of: model.frame.positionSeconds))
        ZStack(alignment: .topLeading) {
            if let peaks = model.peaks {
                OverviewEnvelope(peaks: peaks, geometry: geometry, height: height, color: color)
                    .equatable()
                    .mask(alignment: .leading) { Rectangle().frame(width: max(0, x)) }
            }
            Rectangle().fill(Color.white).frame(width: 2, height: height).offset(x: min(max(x - 1, 0), CGFloat(geometry.width) - 2))
        }
        .frame(width: CGFloat(geometry.width), height: height, alignment: .topLeading)
        .transaction { $0.animation = nil }
    }
}

/// Triangle `cue` de 8 pt, pointe vers le haut, posé sur le bord inférieur de l'aperçu.
private struct CueTriangle: View {
    static let size: CGFloat = 8

    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: Self.size / 2, y: 0))
            path.addLine(to: CGPoint(x: Self.size, y: Self.size))
            path.addLine(to: CGPoint(x: 0, y: Self.size))
            path.closeSubpath()
        }
        .fill(Theme.cue)
        .frame(width: Self.size, height: Self.size)
    }
}
