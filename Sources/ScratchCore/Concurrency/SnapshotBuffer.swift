import Atomics

/// Triple tampon sans verrou pour publier un état d'**un** fil écrivain vers **un** fil lecteur
/// (architecture §4, ADR-04).
///
/// L'écrivain (fil audio) publie une valeur complète par `write` ; le lecteur (fil principal)
/// obtient par `read` la dernière valeur publiée, jamais une valeur à moitié écrite. Chaque
/// emplacement appartient à un seul fil à la fois ; la propriété change de main par un échange
/// atomique (acquisition/libération). Aucune allocation ni verrou après la création.
///
/// Sur le fil audio, `Value` doit être **triviale** (aucune référence comptée, aucun tableau,
/// aucune chaîne) : l'affectation ne doit ni retenir ni libérer d'objet.
public final class SnapshotBuffer<Value>: @unchecked Sendable {
    private static var freshBit: Int { 0b100 }
    private static var indexMask: Int { 0b011 }

    private let slots: UnsafeMutablePointer<Value>
    /// Indice de l'emplacement intermédiaire, avec le bit « nouvelle valeur ».
    private let middle: ManagedAtomic<Int>
    /// Emplacement en cours d'écriture. Propriété exclusive de l'écrivain.
    private var writeIndex: Int
    /// Emplacement en cours de lecture. Propriété exclusive du lecteur.
    private var readIndex: Int

    public init(initialValue: Value) {
        slots = .allocate(capacity: 3)
        slots.initialize(repeating: initialValue, count: 3)
        writeIndex = 0
        middle = ManagedAtomic(1)
        readIndex = 2
    }

    deinit {
        slots.deinitialize(count: 3)
        slots.deallocate()
    }

    /// Écrivain : publie une nouvelle valeur.
    public func write(_ value: Value) {
        slots[writeIndex] = value
        let previous = middle.exchange(writeIndex | Self.freshBit, ordering: .acquiringAndReleasing)
        writeIndex = previous & Self.indexMask
    }

    /// Lecteur : `true` si une valeur a été publiée depuis la dernière lecture.
    public var hasNewValue: Bool {
        middle.load(ordering: .relaxed) & Self.freshBit != 0
    }

    /// Lecteur : renvoie la dernière valeur publiée (ou la même que la lecture précédente si
    /// rien n'a été publié entre-temps).
    public func read() -> Value {
        if hasNewValue {
            let previous = middle.exchange(readIndex, ordering: .acquiringAndReleasing)
            readIndex = previous & Self.indexMask
        }
        return slots[readIndex]
    }
}
