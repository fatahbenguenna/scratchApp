import Foundation

/// Minuterie du relâchement trackpad (SF-79, D-24) : une échéance sur le fil principal, réarmée à
/// chaque événement de défilement ; seule la dernière échéance armée agit. L'ordonnanceur est
/// injectable (tests) ; par défaut, un `Timer` de la boucle principale, actif aussi pendant le suivi
/// des événements (`.common`).
@MainActor
final class ScrollReleaseTimer {
    typealias Scheduler = @MainActor (_ delay: Double, _ action: @escaping @MainActor () -> Void) -> Void

    private let schedule: Scheduler
    private var generation = 0

    /// - Parameter schedule: ordonnanceur ; `nil` pour un `Timer` de la boucle principale.
    init(schedule: Scheduler? = nil) {
        self.schedule = schedule ?? Self.runLoopScheduler
    }

    /// Arme la minuterie dans `delay` secondes ; l'échéance précédente est annulée.
    func arm(after delay: Double, _ action: @escaping @MainActor () -> Void) {
        generation &+= 1
        let armed = generation
        schedule(max(0, delay)) { [weak self] in
            guard let self, self.generation == armed else { return }
            action()
        }
    }

    /// Annule l'échéance en cours.
    func disarm() {
        generation &+= 1
    }

    static func runLoopScheduler(delay: Double, action: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated { action() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
