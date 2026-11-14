import Foundation

/// Empreinte SHA-256 du contenu d'un fichier, en hexadécimal minuscule (SF-75, RM-58 ; ADR-09).
///
/// **Squelette (story EP3, Hugo) : renvoie une chaîne vide.** À implémenter :
/// - `#if canImport(CryptoKit)` : `CryptoKit.SHA256`, lecture du fichier par blocs (1 Mio) ;
/// - sinon (Linux) : implémentation Swift pure (`SHA256.swift`), même lecture par blocs ;
/// - tests : vecteurs NIST (« abc », chaîne vide, 1 Mio de « a ») sur les deux implémentations,
///   l'implémentation Swift pure restant testée aussi sur macOS.
public enum ContentHasher {
    /// Empreinte d'un fichier, lu par blocs (jamais chargé en entier en mémoire).
    public static func sha256Hex(ofFileAt url: URL) throws -> String {
        ""
    }

    /// Empreinte d'un bloc de données en mémoire.
    public static func sha256Hex(of data: Data) -> String {
        ""
    }
}
