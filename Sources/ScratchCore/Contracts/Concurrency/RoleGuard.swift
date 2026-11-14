import Atomics

/// Détecteur (débogage) d'appels **concurrents** à des méthodes réservées à un seul rôle.
///
/// Les files SPSC et le triple tampon supposent un seul producteur et un seul consommateur.
/// `RoleGuard` déclenche une assertion si deux fils exécutent en même temps des méthodes du même
/// rôle (par exemple deux `send` concurrents). Aucune allocation : utilisable sur le fil audio.
struct RoleGuard {
    private let busy = ManagedAtomic<Bool>(false)

    func enter(_ message: StaticString) {
        let wasBusy = busy.exchange(true, ordering: .acquiring)
        assert(!wasBusy, String(describing: message))
    }

    func exit() {
        busy.store(false, ordering: .releasing)
    }
}
