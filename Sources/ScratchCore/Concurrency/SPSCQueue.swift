import Atomics

/// File sans verrou à **un seul producteur et un seul consommateur** (SPSC), de capacité fixe
/// (architecture §4, ADR-03).
///
/// - Capacité arrondie à la puissance de 2 supérieure (minimum 2). La mémoire est allouée à la
///   création : `push` et `pop` n'allouent jamais et ne prennent aucun verrou.
/// - Un seul fil (ou une seule tâche séquentielle) appelle `push` ; un seul appelle `pop`.
/// - Sur le fil audio, n'utiliser que des éléments **triviaux** (sans référence comptée : nombres,
///   énumérations simples, `Unmanaged`), pour qu'aucune libération ne s'y produise.
public final class SPSCQueue<Element>: @unchecked Sendable {
    /// Nombre maximal d'éléments en attente.
    public let capacity: Int

    private let mask: Int
    private let storage: UnsafeMutablePointer<Element>
    /// Prochain indice à lire. Écrit par le consommateur seulement.
    private let head = ManagedAtomic<Int>(0)
    /// Prochain indice à écrire. Écrit par le producteur seulement.
    private let tail = ManagedAtomic<Int>(0)

    public init(minimumCapacity: Int) {
        precondition(minimumCapacity > 0, "SPSCQueue: capacity must be positive")
        var capacity = 2
        while capacity < minimumCapacity { capacity <<= 1 }
        self.capacity = capacity
        self.mask = capacity - 1
        self.storage = .allocate(capacity: capacity)
    }

    deinit {
        var index = head.load(ordering: .relaxed)
        let end = tail.load(ordering: .relaxed)
        while index != end {
            (storage + (index & mask)).deinitialize(count: 1)
            index &+= 1
        }
        storage.deallocate()
    }

    /// Producteur : ajoute un élément. Renvoie `false`, sans rien modifier, si la file est pleine.
    @discardableResult
    public func push(_ element: Element) -> Bool {
        let currentTail = tail.load(ordering: .relaxed)
        let currentHead = head.load(ordering: .acquiring)
        guard currentTail &- currentHead < capacity else { return false }
        (storage + (currentTail & mask)).initialize(to: element)
        tail.store(currentTail &+ 1, ordering: .releasing)
        return true
    }

    /// Consommateur : retire le plus ancien élément, ou `nil` si la file est vide.
    public func pop() -> Element? {
        let currentHead = head.load(ordering: .relaxed)
        let currentTail = tail.load(ordering: .acquiring)
        guard currentHead != currentTail else { return nil }
        let element = (storage + (currentHead & mask)).move()
        head.store(currentHead &+ 1, ordering: .releasing)
        return element
    }

    /// Producteur : places libres garanties (valeur prudente : la place réelle peut être supérieure).
    public var availableCapacity: Int {
        capacity - (tail.load(ordering: .relaxed) &- head.load(ordering: .acquiring))
    }

    /// Nombre approximatif d'éléments en attente (exact si appelé hors concurrence).
    public var approximateCount: Int {
        let currentHead = head.load(ordering: .acquiring)
        let currentTail = tail.load(ordering: .acquiring)
        return max(0, currentTail &- currentHead)
    }

    /// Consommateur : `true` si aucun élément n'est en attente.
    public var isEmpty: Bool {
        head.load(ordering: .relaxed) == tail.load(ordering: .acquiring)
    }
}
