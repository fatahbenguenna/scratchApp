import Foundation

/// Nommage des copies dans `Banque de sons` (SF-02, SF-60, RM-43, D-12 ; 6.13 « Importer deux
/// fichiers portant le même nom »). Logique pure, sans accès au disque.
///
/// - La copie garde le nom d'origine, accents et espaces compris ; l'extension est conservée telle
///   quelle (casse comprise).
/// - **Assainissement** (validé par l'orchestrateur) : un nom n'est accepté par la bibliothèque que
///   s'il ne peut pas sortir de `Banque de sons` (`LibraryStore.isSafeFileName`). Les points en tête
///   sont retirés (`.cache.wav` → `cache.wav`), une suite de points devient un seul point
///   (`remix..final.wav` → `remix.final.wav`), `/`, `\` et les caractères de contrôle deviennent `_`.
///   Un nom vide devient « son ».
/// - **Collision** (D-12) : `voix_funk.wav`, puis `voix_funk_2.wav`, `voix_funk_3.wav`… ; une copie
///   n'est jamais écrasée.
/// - **Longueur** : 255 octets UTF-8 au plus (limite des systèmes de fichiers), le nom de base étant
///   raccourci avant le suffixe et l'extension.
enum CopyNaming {
    /// Longueur maximale d'un nom de fichier, en octets UTF-8.
    static let maximumNameBytes = 255
    /// Nom utilisé quand le nom d'origine est vide après assainissement.
    static let fallbackBaseName = "son"

    /// Nom de copie sûr dérivé du nom d'origine (dernier composant du chemin source).
    static func sanitizedName(_ original: String) -> String {
        var characters = String.UnicodeScalarView()
        var previousWasDot = false
        for scalar in original.unicodeScalars {
            if scalar == "." {
                if previousWasDot || characters.isEmpty { continue }  // collapse dots, drop leading ones
                previousWasDot = true
                characters.append(scalar)
                continue
            }
            previousWasDot = false
            if scalar == "/" || scalar == "\\" || scalar.properties.generalCategory == .control {
                characters.append("_")
            } else {
                characters.append(scalar)
            }
        }
        var name = String(characters)
        while name.hasSuffix(".") { name.removeLast() }
        let (base, pathExtension) = split(name)
        return fitted(base: base.isEmpty ? fallbackBaseName : base, suffix: "", pathExtension: pathExtension)
    }

    /// Premier nom libre parmi `name`, `name_2`, `name_3`… (suffixe avant l'extension).
    static func availableName(for name: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(name) else { return name }
        let (base, pathExtension) = split(name)
        var number = 2
        while true {
            let candidate = fitted(base: base, suffix: "_\(number)", pathExtension: pathExtension)
            if !isTaken(candidate) { return candidate }
            number += 1
        }
    }

    /// Clé de comparaison des noms : sans distinction de casse ni de forme de normalisation Unicode,
    /// comme les volumes APFS du Mac ; prudente sur iOS (APFS sensible à la casse).
    static func comparisonKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    // MARK: - Helpers

    /// Sépare le nom de base et l'extension (sans le point) ; pas d'extension pour un nom sans point.
    private static func split(_ name: String) -> (base: String, pathExtension: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]))
    }

    /// Assemble `base + suffix + .extension` en raccourcissant `base` pour tenir en 255 octets.
    private static func fitted(base: String, suffix: String, pathExtension: String) -> String {
        let tail = suffix + (pathExtension.isEmpty ? "" : "." + pathExtension)
        var trimmed = base
        while !trimmed.isEmpty, (trimmed + tail).utf8.count > maximumNameBytes || trimmed.hasSuffix(".") {
            trimmed.removeLast()
        }
        if trimmed.isEmpty { trimmed = fallbackBaseName }
        return trimmed + tail
    }
}
