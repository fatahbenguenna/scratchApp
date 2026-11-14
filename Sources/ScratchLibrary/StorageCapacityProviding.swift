import Foundation
import ScratchCore

/// Espace libre du volume de stockage, consulté avant chaque import (6.1 « Échec de copie faute
/// d'espace » ; RM-48). Injectable : les tests simulent un volume plein.
public protocol StorageCapacityProviding: Sendable {
    /// Octets disponibles pour une écriture importante sur le volume qui contient `url` (un dossier
    /// existant), ou `nil` si le système ne le dit pas : l'import tente alors l'écriture et traite
    /// l'erreur « disque plein ».
    func availableCapacity(forWritingAt url: URL) -> Int64?
}

/// Espace libre donné par le système : `volumeAvailableCapacityForImportantUsage` sur les plateformes
/// Apple (espace purgeable compris), `attributesOfFileSystem` ailleurs.
public struct SystemStorageCapacity: StorageCapacityProviding {
    public init() {}

    public func availableCapacity(forWritingAt url: URL) -> Int64? {
        #if canImport(Darwin)
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return capacity
        }
        #endif
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: url.path),
              let free = attributes[.systemFreeSize] as? NSNumber
        else { return nil }
        return free.int64Value
    }
}

extension LibraryError {
    /// Erreur d'écriture du système, traduite : disque plein → `insufficientStorage`, sinon
    /// `writeFailed(reason:)` ; une `LibraryError` passe telle quelle.
    static func writing(_ error: Error, context: String) -> LibraryError {
        if let libraryError = error as? LibraryError { return libraryError }
        return isOutOfSpace(error) ? .insufficientStorage : .writeFailed(reason: "\(context) : \(error)")
    }

    /// `ENOSPC` ou `NSFileWriteOutOfSpaceError`, directement ou comme erreur sous-jacente.
    static func isOutOfSpace(_ error: Error) -> Bool {
        if let posix = error as? POSIXError { return posix.code == .ENOSPC }
        if let cocoa = error as? CocoaError {
            if cocoa.code == .fileWriteOutOfSpace { return true }
            if let underlying = cocoa.userInfo[NSUnderlyingErrorKey] as? Error { return isOutOfSpace(underlying) }
        }
        return false
    }
}
