import Foundation

/// Empreinte SHA-256 du contenu d'un fichier, en hexadécimal minuscule (SF-75, RM-58 ; PRD 3.1
/// critère 4 ; ADR-09).
///
/// **Squelette (story 3.1, Hugo) : renvoie une chaîne vide.** À implémenter : SHA-256 portable en
/// Swift pur (`SHA256.swift`), **sans CryptoKit** (NFR9), calculé en flux (blocs de 1 Mio, jamais le
/// fichier entier en mémoire) ; vecteurs de test officiels (chaîne vide, « abc », un million de « a »),
/// identiques sous Linux et macOS.
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
