import Foundation
import ScratchCore

/// Intentions de l'interface qui dépassent le moteur : import, démo, bibliothèque, réglages
/// (story 4.1 CA 6 ; architecture §5.2). Contrat Léa → Hugo.
///
/// Défini par l'interface, implémenté par l'`AppModel` en 6.1 ; `PreviewDeckIntents` en est le
/// double des aperçus et du lancement tant que 6.1 n'est pas livrée. Toute évolution se fait en
/// accord avec Hugo. Fil principal uniquement.
@MainActor
public protocol DeckIntents: AnyObject {
    /// « Importer » : ouvre le sélecteur de fichiers du système pour la platine (SF-02, 6.1).
    func importFile(on deck: DeckID)
    /// « Charger la démo » (SF-76).
    func loadDemo(on deck: DeckID)
    /// Fichier déposé sur la platine (SF-73, 5.2).
    func importDroppedFile(_ url: URL, on deck: DeckID)
    /// Ouvre la bibliothèque (⌘L, bouton ; 3.5).
    func openLibrary()
    /// Ouvre les réglages (⌘, sur Mac, feuille sur iOS ; 3.4).
    func openSettings()
    /// Mac : affiche le dossier de la bibliothèque dans le Finder (menu Fichier ; 3.5, 5.1).
    /// Sans effet sur iOS.
    func revealLibraryInFinder()
}

/// Activité d'import ou de chargement d'une platine, posée par l'`AppModel` et lue par l'en-tête
/// (UX §5.10, §7.2).
public enum DeckActivity: Equatable, Sendable {
    /// Aucune activité.
    case idle
    /// Copie du fichier dans la bibliothèque : pastille « Import de « nom »… », « Importer » désactivé.
    case importing(fileName: String)
    /// Décodage du son : pastille « Chargement… », indicateur après 150 ms.
    case loading
}
