import Foundation

/// Emplacements de stockage de l'application (spec v2.0 — 5.3).
public struct LibraryLocations: Sendable {
    /// Dossier racine « Documents » de l'app (ou un dossier temporaire en test).
    public let documentsDirectory: URL
    /// Dossier « Application Support/ScratchApp ».
    public let supportDirectory: URL

    public init(documentsDirectory: URL, supportDirectory: URL) {
        self.documentsDirectory = documentsDirectory
        self.supportDirectory = supportDirectory
    }

    /// Copies des sons importés : `Documents/Banque de sons/`.
    public var soundBankDirectory: URL {
        documentsDirectory.appendingPathComponent("Banque de sons", isDirectory: true)
    }

    /// Enregistrements du mix (P2) : `Documents/Enregistrements/`.
    public var recordingsDirectory: URL {
        documentsDirectory.appendingPathComponent("Enregistrements", isDirectory: true)
    }

    /// Index de la bibliothèque : `Application Support/ScratchApp/library.json`.
    public var libraryIndexURL: URL {
        supportDirectory.appendingPathComponent("library.json", isDirectory: false)
    }

    /// Emplacements standard de l'application sur l'appareil courant.
    public static func standard(fileManager: FileManager = .default) throws -> LibraryLocations {
        let documents = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let support = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ScratchApp", isDirectory: true)
        return LibraryLocations(documentsDirectory: documents, supportDirectory: support)
    }
}
