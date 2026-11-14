import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Compteur des allocations d'objets Swift et des comptages de références d'un fil (story 1.5,
/// CA 9 ; NFR2). Sans cible C ni changement de `Package.swift`.
///
/// Principe : l'environnement d'exécution Swift appelle ses points d'entrée `swift_allocObject`,
/// `swift_retain`, `swift_release`, `swift_retain_n` et `swift_release_n` à travers des pointeurs
/// de fonction remplaçables (`_swift_allocObject`, `_swift_retain`, …, prévus pour
/// l'instrumentation). Le compteur les remplace pendant la mesure et ne compte que les appels faits
/// **par le fil armé** (les autres fils du processus de test ne sont pas comptés). Les retenues
/// multiples (`_n`) comptent pour `n`.
///
/// Les crochets sont des variables globales lues sans synchronisation par les autres fils : ne pas
/// exécuter les mesures sous ThreadSanitizer (note de QA sur #27).
///
/// Couverture : toute allocation d'objet du tas Swift (instances de classe, stockage des `Array`,
/// `String`, `Dictionary` et `Set`, contextes de closures, boîtes d'existentiels et de variables
/// capturées). Hors couverture : `malloc` appelé directement par du code C et
/// `UnsafeMutablePointer.allocate` (absents du rendu, vérifiés par revue).
enum AllocationCounter {
    typealias AllocObject = @convention(c) (UnsafeRawPointer?, Int, Int) -> UnsafeMutableRawPointer?
    typealias Retain = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    typealias Release = @convention(c) (UnsafeMutableRawPointer?) -> Void
    typealias RetainN = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> UnsafeMutableRawPointer?
    typealias ReleaseN = @convention(c) (UnsafeMutableRawPointer?, UInt32) -> Void

    struct Counts: Equatable {
        var allocations = 0
        var retains = 0
        var releases = 0
        /// Retenues des objets surveillés (`watching`).
        var watchedRetains = 0
    }

    private static let watchedCapacity = 8
    private static var watched = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: watchedCapacity)
    private static var watchedCount = 0
    private static var swizzlingFlag: UnsafeMutablePointer<Bool>?

    private static var allocSlot: UnsafeMutablePointer<AllocObject?>?
    private static var retainSlot: UnsafeMutablePointer<Retain?>?
    private static var releaseSlot: UnsafeMutablePointer<Release?>?
    private static var retainNSlot: UnsafeMutablePointer<RetainN?>?
    private static var releaseNSlot: UnsafeMutablePointer<ReleaseN?>?
    private static var originalRetainN: RetainN?
    private static var originalReleaseN: ReleaseN?
    private static var originalAlloc: AllocObject?
    private static var originalRetain: Retain?
    private static var originalRelease: Release?
    private static var armed = false
    private static var armedThread = pthread_self()
    private static var counts = Counts()
    /// Objets retenus par le fil armé (diagnostic), 256 au plus.
    static let retainedCapacity = 256
    private static var retainedObjects = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: retainedCapacity)

    /// Objets distincts retenus pendant la dernière mesure (diagnostic).
    static var lastRetainedObjects: [UnsafeMutableRawPointer] {
        (0..<min(counts.retains, retainedCapacity)).compactMap { retainedObjects[$0] }
    }

    /// Les points d'entrée remplaçables et le drapeau qui les active existent dans cet environnement
    /// d'exécution.
    static var isAvailable: Bool {
        resolve()
        return allocSlot != nil && retainSlot != nil && releaseSlot != nil && retainNSlot != nil
            && releaseNSlot != nil && swizzlingFlag != nil
    }

    private static func resolve() {
        guard allocSlot == nil, let handle = dlopen(nil, RTLD_NOW) else { return }
        allocSlot = dlsym(handle, "_swift_allocObject")?.assumingMemoryBound(to: AllocObject?.self)
        retainSlot = dlsym(handle, "_swift_retain")?.assumingMemoryBound(to: Retain?.self)
        releaseSlot = dlsym(handle, "_swift_release")?.assumingMemoryBound(to: Release?.self)
        retainNSlot = dlsym(handle, "_swift_retain_n")?.assumingMemoryBound(to: RetainN?.self)
        releaseNSlot = dlsym(handle, "_swift_release_n")?.assumingMemoryBound(to: ReleaseN?.self)
        // The runtime only routes retain and release through the hooks when this flag is set.
        swizzlingFlag = dlsym(handle, "_swift_enableSwizzlingOfAllocationAndRefCountingFunctions_forInstrumentsOnly")?
            .assumingMemoryBound(to: Bool.self)
    }

    /// Compte les allocations et les comptages de références faits par le fil courant pendant
    /// `body`. Les autres fils ne sont pas comptés.
    static func measure(watching objects: [AnyObject] = [], _ body: () -> Void) -> Counts {
        resolve()
        guard let allocSlot, let retainSlot, let releaseSlot, let retainNSlot, let releaseNSlot else { return Counts() }
        counts = Counts()
        watchedCount = min(objects.count, watchedCapacity)
        for index in 0..<watchedCount { watched[index] = Unmanaged.passUnretained(objects[index]).toOpaque() }
        armedThread = pthread_self()
        originalAlloc = allocSlot.pointee
        originalRetain = retainSlot.pointee
        originalRelease = releaseSlot.pointee
        originalRetainN = retainNSlot.pointee
        originalReleaseN = releaseNSlot.pointee
        allocSlot.pointee = { metadata, size, alignment in
            if AllocationCounter.armed, pthread_equal(pthread_self(), AllocationCounter.armedThread) != 0 {
                AllocationCounter.counts.allocations += 1
            }
            return AllocationCounter.originalAlloc!(metadata, size, alignment)
        }
        retainSlot.pointee = { object in
            if AllocationCounter.armed, pthread_equal(pthread_self(), AllocationCounter.armedThread) != 0 {
                if AllocationCounter.counts.retains < AllocationCounter.retainedCapacity {
                    AllocationCounter.retainedObjects[AllocationCounter.counts.retains] = object
                }
                AllocationCounter.counts.retains += 1
                for index in 0..<AllocationCounter.watchedCount where AllocationCounter.watched[index] == object {
                    AllocationCounter.counts.watchedRetains += 1
                }
            }
            return AllocationCounter.originalRetain!(object)
        }
        releaseSlot.pointee = { object in
            if AllocationCounter.armed, pthread_equal(pthread_self(), AllocationCounter.armedThread) != 0 {
                AllocationCounter.counts.releases += 1
            }
            AllocationCounter.originalRelease!(object)
        }
        retainNSlot.pointee = { object, count in
            if AllocationCounter.armed, pthread_equal(pthread_self(), AllocationCounter.armedThread) != 0 {
                AllocationCounter.counts.retains += Int(count)
                for index in 0..<AllocationCounter.watchedCount where AllocationCounter.watched[index] == object {
                    AllocationCounter.counts.watchedRetains += Int(count)
                }
            }
            return AllocationCounter.originalRetainN!(object, count)
        }
        releaseNSlot.pointee = { object, count in
            if AllocationCounter.armed, pthread_equal(pthread_self(), AllocationCounter.armedThread) != 0 {
                AllocationCounter.counts.releases += Int(count)
            }
            AllocationCounter.originalReleaseN!(object, count)
        }
        let previousFlag = swizzlingFlag?.pointee ?? false
        swizzlingFlag?.pointee = true
        armed = true
        body()
        armed = false
        swizzlingFlag?.pointee = previousFlag
        allocSlot.pointee = originalAlloc
        retainSlot.pointee = originalRetain
        releaseSlot.pointee = originalRelease
        retainNSlot.pointee = originalRetainN
        releaseNSlot.pointee = originalReleaseN
        return counts
    }
}
