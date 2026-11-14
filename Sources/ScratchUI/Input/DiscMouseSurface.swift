#if os(macOS)
import AppKit
import ScratchCore
import SwiftUI

/// Surface souris et trackpad d'un disque (macOS ; story 4.3 CA 3 à 6) : vue AppKit retournée
/// (y vers le bas, comme le contrat), saisie au premier clic d'une fenêtre inactive.
///
/// - Clic maintenu = doigt posé ; le glisser est suivi hors du disque et hors de la fenêtre ; le
///   relâchement du bouton relâche le disque où que soit le pointeur ; clic secondaire sans effet.
/// - Curseur main ouverte au survol de la zone de saisie d'un disque chargé, main fermée pendant la
///   saisie.
/// - Défilement par phases (trackpad) et molette sans phases ; l'inertie est ignorée ; deltas
///   corrigés du « défilement naturel » (D-24).
struct DiscInputSurface: NSViewRepresentable {
    let coordinator: DiscInputCoordinator

    func makeNSView(context: Context) -> MouseView { MouseView(coordinator: coordinator) }
    func updateNSView(_ view: MouseView, context: Context) { view.coordinator = coordinator }

    final class MouseView: NSView {
        var coordinator: DiscInputCoordinator
        private static let mouseContact = 0
        private var isDragging = false

        init(coordinator: DiscInputCoordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
        }

        @available(*, unavailable) required init?(coder: NSCoder) { nil }

        override var isFlipped: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited,
                                                                  .activeInKeyWindow, .inVisibleRect],
                                           owner: self))
        }

        override func mouseDown(with event: NSEvent) {
            let sample = sample(of: event)
            coordinator.contactBegan(Self.mouseContact, at: sample)
            isDragging = coordinator.isHoldingContact
            updateCursor(x: sample.x, y: sample.y)
        }

        override func mouseDragged(with event: NSEvent) {
            guard isDragging else { return }
            coordinator.contactMoved(Self.mouseContact, samples: [sample(of: event)])
        }

        override func mouseUp(with event: NSEvent) {
            guard isDragging else { return }
            isDragging = false
            coordinator.contactEnded(Self.mouseContact, time: event.timestamp)
            let sample = sample(of: event)
            updateCursor(x: sample.x, y: sample.y)
        }

        override func mouseMoved(with event: NSEvent) {
            let sample = sample(of: event)
            updateCursor(x: sample.x, y: sample.y)
        }

        override func mouseExited(with event: NSEvent) {
            if !isDragging { NSCursor.arrow.set() }
        }

        override func scrollWheel(with event: NSEvent) {
            guard let phase = Self.phase(of: event) else { return }
            let sample = sample(of: event)
            let delta = DiscGeometry.fingerDelta(scrollingDeltaX: event.scrollingDeltaX,
                                                 scrollingDeltaY: event.scrollingDeltaY,
                                                 invertedFromDevice: event.isDirectionInvertedFromDevice)
            coordinator.scroll(x: sample.x, y: sample.y, deltaX: delta.dx, deltaY: delta.dy, phase: phase,
                               time: event.timestamp)
        }

        /// Phase du défilement : inertie, molette sans phases, ou phase du geste (`mayBegin` ignoré).
        static func phase(of event: NSEvent) -> ScrollGestureMapper.Phase? {
            if !event.momentumPhase.isEmpty { return ScrollGestureMapper.Phase.momentum }
            if event.phase.isEmpty { return ScrollGestureMapper.Phase.none }
            if event.phase.contains(.began) { return ScrollGestureMapper.Phase.began }
            if event.phase.contains(.changed) { return ScrollGestureMapper.Phase.changed }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                return ScrollGestureMapper.Phase.ended
            }
            return nil
        }

        /// Position de l'événement dans le repère du traqueur ; la géométrie est relue à chaque
        /// événement (redimensionnement pendant un geste, 6.14).
        private func sample(of event: NSEvent) -> ContactSample {
            coordinator.updateGeometry(width: bounds.width, height: bounds.height)
            let point = convert(event.locationInWindow, from: nil)
            let tracker = DiscGeometry.trackerPoint(x: point.x, y: point.y, height: bounds.height, isFlipped: isFlipped)
            return ContactSample(x: tracker.x, y: tracker.y, time: event.timestamp)
        }

        private func updateCursor(x: Double, y: Double) {
            if isDragging {
                NSCursor.closedHand.set()
            } else if coordinator.isGrabbable(x: x, y: y) {
                NSCursor.openHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}
#endif
