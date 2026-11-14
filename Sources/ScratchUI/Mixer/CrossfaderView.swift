import ScratchCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Crossfader (SF-12, SF-19, SF-66, SF-67 ; UX §5.12) : lettres d'extrémité (échangées par le
/// hamster, le bouton ne bouge pas), repères de cut-in, bouton 28 × 44.
///
/// Saisie par une surface UIKit ou AppKit dédiée : chaque touche regroupée (`coalescedTouches`) ou
/// chaque `mouseDragged` part vers le moteur dans le cycle d'événements qui la reçoit, sans attendre
/// la mise à jour de l'interface, pour ne perdre aucune coupure rapide (CA 6, NFR1). Un seul contact
/// tient le crossfader ; un second est ignoré jusqu'au relâchement du premier (CA 5).
struct CrossfaderView: View {
    let mixer: MixerViewModel
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let knobWidth: CGFloat = 28

    var body: some View {
        HStack(spacing: 8) {
            letter(mixer.leftDeck)
            GeometryReader { proxy in
                let course = max(1, proxy.size.width - Self.knobWidth)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.strokeStrong).frame(height: 4)
                    if let width = mixer.cutInWidth {
                        marker(at: width, course: course, deck: mixer.rightDeck)
                        marker(at: 1 - width, course: course, deck: mixer.leftDeck)
                    }
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.knob)
                        .overlay(Rectangle().fill(Theme.bgApp).frame(width: 2, height: 24))
                        .frame(width: Self.knobWidth, height: 44)
                        .offset(x: mixer.crossfader * course)
                }
                .frame(maxHeight: .infinity)
                .overlay(CrossfaderSurface(mixer: mixer, course: course, knobWidth: Self.knobWidth))
            }
            letter(mixer.rightDeck)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Crossfader")
        .accessibilityValue(mixer.crossfaderAccessibilityValue)
        .accessibilityAdjustableAction { direction in
            mixer.nudgeCrossfader(steps: direction == .increment ? 1 : -1)
        }
        .accessibilityAction(named: "Butée gauche") { mixer.setCrossfader(0) }
        .accessibilityAction(named: "Centre") { mixer.setCrossfader(0.5) }
        .accessibilityAction(named: "Butée droite") { mixer.setCrossfader(1) }
        .accessibilityIdentifier("mixer.crossfader")
    }

    /// Lettre d'extrémité ; pastille pleine pendant une coupure momentanée de la voie (UX §5.12).
    private func letter(_ deck: DeckID) -> some View {
        let open = mixer.momentaryCuts[deck]
        return Text(verbatim: deck.rawValue)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(open ? Theme.textOnAccent : Theme.deckColor(deck))
            .frame(width: 22, height: 22)
            .background(Circle().fill(open ? Theme.deckColor(deck) : .clear))
            .id(deck)
            .transition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: mixer.hamster)
    }

    private func marker(at position: Double, course: CGFloat, deck: DeckID) -> some View {
        Rectangle()
            .fill(Theme.deckColor(deck))
            .frame(width: 2, height: 14)
            .offset(x: position * course + Self.knobWidth / 2 - 1)
    }
}

/// Saisie du crossfader, logique pure (UX §5.12) : un toucher dans la zone du bouton (± 22 pt) saisit
/// relativement, sans saut ; ailleurs sur la piste, le bouton vient sous le doigt puis le suit.
/// Abscisses mesurées depuis la position 0 du centre du bouton ; `course` en points.
struct CrossfaderGrip {
    static let knobZoneHalfWidth = 22.0

    let course: Double
    private var offset = 0.0

    init(course: Double) {
        self.course = max(1, course)
    }

    /// Début du contact en `x` ; renvoie la nouvelle position (inchangée dans la zone du bouton).
    mutating func begin(at x: Double, value: Double) -> Double {
        if abs(x - value * course) <= Self.knobZoneHalfWidth {
            offset = value - x / course
            return value
        }
        offset = 0
        return position(at: x)
    }

    /// Position pour le contact en `x`, bornée à 0…1.
    func position(at x: Double) -> Double {
        min(1, max(0, x / course + offset))
    }
}

/// Surface de saisie native : envoie `setCrossfader` pour chaque événement reçu (CA 6).
@MainActor
private struct CrossfaderSurface {
    let mixer: MixerViewModel
    let course: CGFloat
    let knobWidth: CGFloat

    @MainActor
    final class Coordinator {
        var mixer: MixerViewModel
        var course: CGFloat
        var knobWidth: CGFloat
        private var grip: CrossfaderGrip?

        init(mixer: MixerViewModel, course: CGFloat, knobWidth: CGFloat) {
            self.mixer = mixer
            self.course = course
            self.knobWidth = knobWidth
        }

        func began(at x: CGFloat) {
            var newGrip = CrossfaderGrip(course: Double(course))
            mixer.setCrossfader(newGrip.begin(at: Double(x - knobWidth / 2), value: mixer.crossfader))
            grip = newGrip
        }

        func moved(to x: CGFloat) {
            guard let grip else { return }
            mixer.setCrossfader(grip.position(at: Double(x - knobWidth / 2)))
        }

        func ended() { grip = nil }
    }

    func makeCoordinator() -> Coordinator { Coordinator(mixer: mixer, course: course, knobWidth: knobWidth) }

    fileprivate func refresh(_ coordinator: Coordinator) {
        coordinator.mixer = mixer
        coordinator.course = course
        coordinator.knobWidth = knobWidth
    }
}

#if os(macOS)
extension CrossfaderSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> SurfaceView { SurfaceView(coordinator: context.coordinator) }
    func updateNSView(_ view: SurfaceView, context: Context) { refresh(context.coordinator) }

    final class SurfaceView: NSView {
        let coordinator: Coordinator
        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
        }
        @available(*, unavailable) required init?(coder: NSCoder) { nil }
        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { coordinator.began(at: location(of: event)) }
        override func mouseDragged(with event: NSEvent) { coordinator.moved(to: location(of: event)) }
        override func mouseUp(with event: NSEvent) { coordinator.ended() }
        private func location(of event: NSEvent) -> CGFloat { convert(event.locationInWindow, from: nil).x }
    }
}
#else
extension CrossfaderSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> SurfaceView { SurfaceView(coordinator: context.coordinator) }
    func updateUIView(_ view: SurfaceView, context: Context) { refresh(context.coordinator) }

    final class SurfaceView: UIView {
        let coordinator: Coordinator
        private var owner: UITouch?

        init(coordinator: Coordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
            isMultipleTouchEnabled = true
            isExclusiveTouch = false
            backgroundColor = .clear
        }
        @available(*, unavailable) required init?(coder: NSCoder) { nil }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard owner == nil, let touch = touches.first else { return }
            owner = touch
            coordinator.began(at: touch.location(in: self).x)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let owner, touches.contains(owner) else { return }
            for touch in event?.coalescedTouches(for: owner) ?? [owner] {
                coordinator.moved(to: touch.location(in: self).x)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { release(touches) }

        private func release(_ touches: Set<UITouch>) {
            guard let owner, touches.contains(owner) else { return }
            self.owner = nil
            coordinator.ended()
        }
    }
}
#endif
