#if os(iOS)
import ScratchCore
import SwiftUI
import UIKit

/// Surface tactile d'un disque (iOS, iPadOS ; story 4.3 CA 1, 2, 6, 7) : vue UIKit multitouch,
/// non exclusive, qui transmet au coordinateur chaque contact avec ses touches regroupées puis
/// prédites et leurs horodatages système. Un clic au pointeur (iPad) se comporte comme un doigt.
/// Les gestes SwiftUI ne donnent ni les touches regroupées ni le suivi par contact (R-08).
struct DiscInputSurface: UIViewRepresentable {
    let coordinator: DiscInputCoordinator

    func makeUIView(context: Context) -> TouchView { TouchView(coordinator: coordinator) }
    func updateUIView(_ view: TouchView, context: Context) { view.coordinator = coordinator }

    final class TouchView: UIView {
        var coordinator: DiscInputCoordinator

        init(coordinator: DiscInputCoordinator) {
            self.coordinator = coordinator
            super.init(frame: .zero)
            isMultipleTouchEnabled = true
            isExclusiveTouch = false
            backgroundColor = .clear
        }

        @available(*, unavailable) required init?(coder: NSCoder) { nil }

        override func layoutSubviews() {
            super.layoutSubviews()
            refreshGeometry()
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            refreshGeometry()
            for touch in touches { coordinator.contactBegan(Self.id(of: touch), at: sample(touch)) }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            refreshGeometry()
            for touch in touches {
                var samples = (event?.coalescedTouches(for: touch) ?? [touch]).map { sample($0) }
                samples += (event?.predictedTouches(for: touch) ?? []).map { sample($0, predicted: true) }
                coordinator.contactMoved(Self.id(of: touch), samples: samples)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches) }

        private func end(_ touches: Set<UITouch>) {
            for touch in touches { coordinator.contactEnded(Self.id(of: touch), time: touch.timestamp) }
        }

        private func refreshGeometry() {
            coordinator.updateGeometry(width: bounds.width, height: bounds.height)
        }

        private func sample(_ touch: UITouch, predicted: Bool = false) -> ContactSample {
            let point = touch.location(in: self)
            return ContactSample(x: point.x, y: point.y, time: touch.timestamp, isPredicted: predicted)
        }

        /// Identifiant stable pendant la vie du `UITouch`, sans le retenir.
        static func id(of touch: UITouch) -> Int { ObjectIdentifier(touch).hashValue }
    }
}
#endif
