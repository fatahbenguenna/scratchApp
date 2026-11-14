import Atomics

/// Son décodé, prêt pour le rendu temps réel (architecture §5.1, ADR-05).
///
/// - Échantillons Float32 **désentrelacés stéréo** : mono dupliqué, multicanal réduit en stéréo
///   par le décodeur (SF-80).
/// - Fréquence d'échantillonnage **native** du fichier (plafonnée à 48 kHz par le décodeur, ADR-05).
///   Le rendu rééchantillonne à la volée vers la fréquence de sortie.
/// - **Immuable** après création : partageable entre fils (`Sendable`) et entre les deux platines (RM-57).
/// - Mémoire allouée une seule fois à la création, libérée au `deinit`.
///
/// Règle temps réel : le `deinit` ne doit **jamais** s'exécuter sur le fil audio. Le moteur ne tient
/// le clip que par une référence non gérée et rend les clips remplacés par sa file de retour,
/// vidée sur le fil principal (`ScratchEngine.drainReleasedClips()`).
public final class AudioClip: Identifiable, Hashable, @unchecked Sendable {
    /// Identifiant de processus, unique et croissant. Ce n'est pas l'UUID de bibliothèque (RM-58).
    public struct ID: Hashable, Comparable, Sendable, CustomStringConvertible {
        public let rawValue: UInt64
        public static func < (lhs: ID, rhs: ID) -> Bool { lhs.rawValue < rhs.rawValue }
        public var description: String { "clip#\(rawValue)" }
    }

    private static let nextID = ManagedAtomic<UInt64>(1)

    public let id: ID
    /// Titre affiché (nom du fichier sans extension, ou titre de l'entrée de bibliothèque).
    public let title: String
    /// Fréquence d'échantillonnage des données, en Hz.
    public let sampleRate: Double
    /// Nombre de trames (une trame = un échantillon gauche + un échantillon droit).
    public let frameCount: Int
    /// Canal gauche, `frameCount` échantillons. Adresse stable pendant toute la vie du clip.
    public let left: UnsafeBufferPointer<Float>
    /// Canal droit, `frameCount` échantillons. Adresse stable pendant toute la vie du clip.
    public let right: UnsafeBufferPointer<Float>

    private let storage: UnsafeMutablePointer<Float>

    /// Durée en secondes.
    public var duration: Double { Double(frameCount) / sampleRate }

    /// Crée un clip en remplissant directement sa mémoire (utilisé par le décodeur, sans copie
    /// intermédiaire). Si `fill` lève une erreur, la mémoire est libérée et l'erreur propagée.
    ///
    /// - Precondition: `sampleRate` fini et > 0, `frameCount` > 0.
    public init(
        title: String,
        sampleRate: Double,
        frameCount: Int,
        fill: (_ left: UnsafeMutableBufferPointer<Float>, _ right: UnsafeMutableBufferPointer<Float>) throws -> Void
    ) rethrows {
        precondition(sampleRate.isFinite && sampleRate > 0, "AudioClip: invalid sample rate")
        precondition(frameCount > 0, "AudioClip: empty clip")
        let storage = UnsafeMutablePointer<Float>.allocate(capacity: frameCount * 2)
        storage.initialize(repeating: 0, count: frameCount * 2)
        let leftBuffer = UnsafeMutableBufferPointer(start: storage, count: frameCount)
        let rightBuffer = UnsafeMutableBufferPointer(start: storage + frameCount, count: frameCount)
        do {
            try fill(leftBuffer, rightBuffer)
        } catch {
            storage.deinitialize(count: frameCount * 2)
            storage.deallocate()
            throw error
        }
        self.storage = storage
        self.left = UnsafeBufferPointer(leftBuffer)
        self.right = UnsafeBufferPointer(rightBuffer)
        self.title = title
        self.sampleRate = sampleRate
        self.frameCount = frameCount
        self.id = ID(rawValue: Self.nextID.loadThenWrappingIncrement(ordering: .relaxed))
    }

    /// Crée un clip stéréo par copie de deux canaux de même longueur.
    public convenience init(title: String, sampleRate: Double, left: [Float], right: [Float]) {
        precondition(left.count == right.count, "AudioClip: channel length mismatch")
        self.init(title: title, sampleRate: sampleRate, frameCount: left.count) { l, r in
            _ = l.initialize(from: left)
            _ = r.initialize(from: right)
        }
    }

    /// Crée un clip à partir d'un canal mono, dupliqué sur les deux canaux (SF-80).
    public convenience init(title: String, sampleRate: Double, mono: [Float]) {
        self.init(title: title, sampleRate: sampleRate, left: mono, right: mono)
    }

    deinit {
        storage.deinitialize(count: frameCount * 2)
        storage.deallocate()
    }

    public static func == (lhs: AudioClip, rhs: AudioClip) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
