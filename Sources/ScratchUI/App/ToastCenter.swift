import Foundation
import Observation

/// Bandeau d'information : message bref, sans décision ni blocage (UX §5.21, §8.5).
public struct Toast: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let text: String

    public init(text: String) {
        self.text = text
    }

    /// Durée d'affichage : 4 s, 6 s au-delà de 80 caractères (UX §5.21).
    public var duration: Double { text.count > 80 ? 6 : 4 }
}

/// File d'un seul bandeau : le plus récent remplace le précédent ; il se ferme seul après sa durée,
/// ou au toucher (UX §5.21).
@MainActor
@Observable
public final class ToastCenter {
    /// Bandeau affiché.
    public private(set) var current: Toast?
    @ObservationIgnored private var dismissal: Task<Void, Never>?

    public init() {}

    /// Affiche `text`, en remplaçant le bandeau courant.
    public func show(_ text: String) {
        let toast = Toast(text: text)
        current = toast
        dismissal?.cancel()
        dismissal = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(toast.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss(toast)
        }
    }

    /// Ferme `toast` s'il est encore affiché (ou le bandeau courant, sans argument).
    public func dismiss(_ toast: Toast? = nil) {
        guard let shown = current, toast == nil || toast?.id == shown.id else { return }
        current = nil
        dismissal?.cancel()
        dismissal = nil
    }
}
