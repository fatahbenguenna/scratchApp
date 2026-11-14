import Foundation
import Observation
import ScratchCore
import SwiftUI
import UniformTypeIdentifiers

/// État de la zone de dépôt d'une platine (UX §5.9).
enum DropZoneState: Equatable, Sendable {
    case inactive
    case accepted
    case rejected(AudioDropRejection)
}

/// Zone de dépôt d'une platine (story 5.2 ; SF-73, D-27, UX §5.9) : décision au survol, puis
/// remise du fichier déposé à l'intention `importDroppedFile(_:on:)`, qui l'importe et le charge
/// selon SF-15 (6.1).
@MainActor
@Observable
final class DeckDropZoneModel {
    let deck: DeckID
    private(set) var state = DropZoneState.inactive
    // Incremented at each hover: a late URL resolution of a previous hover is ignored.
    @ObservationIgnored private var session = 0

    init(deck: DeckID) {
        self.deck = deck
    }

    /// Texte du survol : « Déposer pour charger sur la platine A » ou le motif du refus.
    var text: String? {
        switch state {
        case .inactive: return nil
        case .accepted: return "Déposer pour charger sur la platine \(deck.rawValue)"
        case let .rejected(reason): return reason.message
        }
    }

    var acceptsDrop: Bool { state == .accepted }

    /// Début du survol. Renvoie un jeton à passer à `didResolve(_:session:)` quand le type du fichier
    /// ne se lit que dans son URL (Finder). En attendant, le survol est accepté.
    @discardableResult
    func enter(itemTypes: [[String]], isBusy: Bool) -> Int? {
        session += 1
        switch AudioDropFilter.evaluate(itemTypes: itemTypes, isBusy: isBusy) {
        case .accept:
            state = .accepted
            return nil
        case let .reject(reason):
            state = .rejected(reason)
            return nil
        case .resolveFileURL:
            state = .accepted
            return session
        }
    }

    /// URL du fichier survolé obtenue : son extension décide (WAV, AIFF, MP3, M4A).
    func didResolve(_ url: URL?, session token: Int) {
        guard token == session, state != .inactive else { return }
        state = url.map(AudioDropFilter.isAcceptedFile) == true ? .accepted : .rejected(.unsupportedFormat)
    }

    /// Fin du survol, ou dépôt : la zone disparaît (fondu de 120 ms).
    func exit() {
        session += 1
        state = .inactive
    }

    /// Fichier déposé prêt : l'intention de la platine l'importe puis le charge.
    func deliver(_ url: URL?, to intents: any DeckIntents) {
        guard let url else { return }
        intents.importDroppedFile(url, on: deck)
    }
}

/// Reçoit les glisser-déposer d'une platine. Le survol est refusé (`.forbidden`) pour un type non
/// audio, plusieurs fichiers ou un import en cours. Aucun fichier n'est lu pendant le survol.
///
/// SwiftUI appelle ces méthodes sur le fil principal : l'état est lu et écrit sous
/// `MainActor.assumeIsolated`.
struct DeckDropDelegate: DropDelegate {
    let zone: DeckDropZoneModel
    let deckModel: DeckViewModel
    let intents: any DeckIntents

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        let providers = info.itemProviders(for: [.item])
        let itemTypes = providers.map(\.registeredTypeIdentifiers)
        let token: Int? = MainActor.assumeIsolated {
            let token = zone.enter(itemTypes: itemTypes, isBusy: !deckModel.isImportEnabled)
            if let text = zone.text { AccessibilityNotification.Announcement(text).post() }
            return token
        }
        guard let token, let provider = providers.first else { return }
        let zone = self.zone
        DroppedFileLoader.fileURL(from: provider) { url in
            Task { @MainActor in zone.didResolve(url, session: token) }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let accepted: Bool = MainActor.assumeIsolated { zone.acceptsDrop }
        return DropProposal(operation: accepted ? .copy : .forbidden)
    }

    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated { zone.exit() }
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.item])
        let count = providers.count
        let accepted: Bool = MainActor.assumeIsolated {
            let accepted = zone.acceptsDrop && count == 1
            zone.exit()
            return accepted
        }
        guard accepted, let provider = providers.first else { return false }
        let zone = self.zone
        let intents = self.intents
        DroppedFileLoader.load(provider) { url in
            Task { @MainActor in zone.deliver(url, to: intents) }
        }
        return true
    }
}

/// Chargement d'un fichier déposé, hors du fil principal.
enum DroppedFileLoader {
    /// Copies temporaires des fichiers déposés depuis Fichiers (iPad), supprimées après l'import.
    static let stagingDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ScratchApp-Drops", isDirectory: true)

    /// URL d'un fichier déposé depuis le Finder (`public.file-url`), sans lire son contenu.
    static func fileURL(from provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) {
        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
            completion(nil)
            return
        }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in completion(url) }
    }

    /// Fichier déposé : l'URL réelle (Finder, Mac), ou une copie de la représentation du fichier
    /// (Fichiers, iPad). Cette représentation n'est valable que dans le rappel, d'où la copie.
    static func load(_ provider: NSItemProvider, completion: @escaping @Sendable (URL?) -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            fileURL(from: provider, completion: completion)
            return
        }
        guard let type = AudioDropFilter.audioType(in: provider.registeredTypeIdentifiers) else {
            completion(nil)
            return
        }
        let suggestedName = provider.suggestedName
        _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
            completion(url.flatMap { stage($0, suggestedName: suggestedName, type: type) })
        }
    }

    /// Copie `url` dans un dossier temporaire unique, sous le nom d'origine (la copie de la
    /// bibliothèque garde ce nom, D-12).
    static func stage(_ url: URL, suggestedName: String?, type: UTType) -> URL? {
        let folder = stagingDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let pathExtension = url.pathExtension.isEmpty ? (type.preferredFilenameExtension ?? "") : url.pathExtension
        var name = suggestedName.flatMap { $0.isEmpty ? nil : $0 } ?? url.deletingPathExtension().lastPathComponent
        name = name.replacingOccurrences(of: "/", with: "_")
        if !pathExtension.isEmpty, (name as NSString).pathExtension.lowercased() != pathExtension.lowercased() {
            name += ".\(pathExtension)"
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(name, isDirectory: false)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination
        } catch {
            return nil
        }
    }

    /// La copie temporaire d'un dépôt (jamais un fichier de l'utilisateur).
    static func isStaged(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(stagingDirectory.standardizedFileURL.path + "/")
    }

    /// Supprime la copie temporaire d'un dépôt et son dossier ; sans effet sur tout autre fichier.
    static func removeStaged(_ url: URL) {
        guard isStaged(url) else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

/// Rendu de la zone (UX §5.9). Survol accepté : bordure pointillée de 2 pt et voile à 12 % de la
/// couleur de la platine. Refus : couleur `danger`, voile à 8 %. Fondu de 120 ms, gardé avec
/// « Réduire les animations ».
struct DropZoneOverlay: View {
    let zone: DeckDropZoneModel

    static let danger = Color(hex: 0xFF6369)

    var body: some View {
        ZStack {
            if let text = zone.text {
                let accepted = zone.state == .accepted
                let color = accepted ? Theme.deckColor(zone.deck) : Self.danger
                RoundedRectangle(cornerRadius: Theme.panelRadius)
                    .fill(color.opacity(accepted ? 0.12 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.panelRadius)
                            .strokeBorder(color, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    )
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: accepted ? "square.and.arrow.down" : "nosign")
                                .font(.system(size: 28, weight: .semibold))
                            Text(text)
                                .font(Theme.deckTitle)
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(color)
                        .padding(16)
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: zone.state)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Zone de dépôt posée sur une platine entière, en-tête compris (`.deckDropZone(model:intents:)`).
struct DeckDropZone: ViewModifier {
    let model: DeckViewModel
    let intents: any DeckIntents
    @State private var zone: DeckDropZoneModel

    init(model: DeckViewModel, intents: any DeckIntents) {
        self.model = model
        self.intents = intents
        _zone = State(initialValue: DeckDropZoneModel(deck: model.deck))
    }

    func body(content: Content) -> some View {
        content
            .overlay { DropZoneOverlay(zone: zone) }
            .onDrop(of: [.item], delegate: DeckDropDelegate(zone: zone, deckModel: model, intents: intents))
    }
}

extension View {
    /// Accepte le dépôt d'un fichier audio sur la platine (SF-73, story 5.2).
    func deckDropZone(model: DeckViewModel, intents: any DeckIntents) -> some View {
        modifier(DeckDropZone(model: model, intents: intents))
    }
}
