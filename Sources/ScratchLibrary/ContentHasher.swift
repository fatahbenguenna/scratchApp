import Foundation

/// Empreinte SHA-256 du contenu d'un fichier, en hexadécimal minuscule (SF-75, RM-58 ; PRD 3.1
/// critère 4 ; ADR-09).
///
/// Calcul en Swift pur (`SHA256`), **sans CryptoKit** (NFR9, D-43) : mêmes résultats sous Linux et
/// macOS. Un fichier est lu en flux par blocs de 1 Mio, jamais chargé en entier en mémoire.
public enum ContentHasher {
    /// Taille des blocs lus dans un fichier : 1 Mio (ADR-09).
    static let readChunkSize = 1_048_576

    /// Empreinte d'un fichier, lu par blocs de 1 Mio (jamais chargé en entier en mémoire).
    /// Lève l'erreur du système si le fichier ne peut pas être ouvert ou lu.
    public static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var reachedEnd = false
        while !reachedEnd {
            // Drain the bridged chunk at each iteration on Apple platforms: memory stays at one block.
            try withLocalAutoreleasePool {
                if let chunk = try handle.read(upToCount: readChunkSize), !chunk.isEmpty {
                    hasher.update(chunk)
                } else {
                    reachedEnd = true
                }
            }
        }
        return SHA256.hexString(hasher.finalize())
    }

    /// Empreinte d'un bloc de données en mémoire.
    public static func sha256Hex(of data: Data) -> String {
        SHA256.hexString(SHA256.hash(data))
    }

    /// Exécute `body` dans un bassin d'autolibération local sur les plateformes Apple (lectures par
    /// blocs : la mémoire reste à un bloc) ; appel direct ailleurs.
    static func withLocalAutoreleasePool<Result>(_ body: () throws -> Result) rethrows -> Result {
        #if canImport(ObjectiveC)
        return try autoreleasepool(invoking: body)
        #else
        return try body()
        #endif
    }
}
