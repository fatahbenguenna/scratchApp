import ScratchCore
import SwiftUI
import UniformTypeIdentifiers

/// Sélecteur de fichiers du système pour « Importer » (SF-02 ; 6.1 « Importer un fichier WAV »,
/// « Importer depuis le Finder sur Mac »). Fichiers sur iPhone et iPad, panneau d'ouverture sur
/// macOS. Il est filtré sur WAV, AIFF, MP3 et M4A, accepte un seul fichier et affiche le message
/// « Importer sur la platine A » avec le bouton « Importer ».
///
/// L'URL choisie est à portée de sécurité. L'`AppModel` n'ouvre l'accès que pendant la copie.
struct ImportPicker: ViewModifier {
    @Bindable var model: AppModel

    /// Types acceptés : WAV, AIFF, MP3, M4A (AAC ou ALAC).
    static let contentTypes: [UTType] = [.wav, .aiff, .mp3, .mpeg4Audio]

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $model.isImportPickerPresented, allowedContentTypes: Self.contentTypes) { result in
                model.finishImportPicking(result)
            }
            .fileDialogMessage(Text(Self.message(for: model.importPickerDeck)))
            .fileDialogConfirmationLabel(Text("Importer"))
    }

    static func message(for deck: DeckID?) -> String {
        "Importer sur la platine \((deck ?? .a).rawValue)"
    }
}
