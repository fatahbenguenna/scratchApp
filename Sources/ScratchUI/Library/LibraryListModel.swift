import Foundation
import ScratchCore
import ScratchLibrary

/// Ligne de l'écran Bibliothèque (UX §5.19) : textes déjà mis en forme, calculés quand la liste
/// change, jamais à chaque image.
struct LibraryRowItem: Identifiable, Equatable {
    let entry: LibraryEntry
    /// Platines qui portent ce son (pastilles « Sur A » / « Sur B »).
    let loadedOn: [DeckID]

    var id: UUID { entry.id }
    var isDemo: Bool { entry.origin == .demo }
    /// La démo n'est jamais supprimable (SF-74).
    var isDeletable: Bool { entry.isDeletable }
    /// Nom de la copie (D-12).
    var title: String { entry.title }
    /// « 3:45 · 14 nov. 2026 · Import » ; pour la démo « 8,0 s · Intégré » (D-20, D-36).
    let subtitle: String
    /// « « voix_funk.wav », 1 minute 12 secondes, importé le 14 novembre 2026 ».
    let accessibilityLabel: String

    init(entry: LibraryEntry, loadedOn: [DeckID]) {
        self.entry = entry
        self.loadedOn = loadedOn
        let duration = LibraryFormatting.duration(entry.duration)
        let origin = LibraryFormatting.origin(entry.origin)
        let quoted = DeckFormatting.quoted(entry.title)
        let spokenDuration = LibraryFormatting.spokenDuration(entry.duration)
        if entry.origin == .demo {
            subtitle = "\(duration) · \(origin)"
            accessibilityLabel = "\(quoted), \(spokenDuration), son intégré"
        } else {
            subtitle = "\(duration) · \(LibraryFormatting.date(entry.importedAt)) · \(origin)"
            accessibilityLabel = "\(quoted), \(spokenDuration), importé le \(LibraryFormatting.spokenDate(entry.importedAt))"
        }
    }

    /// « chargé sur la platine A », « chargé sur les platines A et B », ou rien.
    var accessibilityValue: String? {
        switch loadedOn.count {
        case 0: return nil
        case 1: return "chargé sur la platine \(loadedOn[0].rawValue)"
        default: return "chargé sur les platines \(loadedOn.map(\.rawValue).joined(separator: " et "))"
        }
    }

    /// Identifiant des tests d'interface : `library.row.demo` ou `library.row.<uuid>` (UX §11.6).
    var identifier: String { isDemo ? "library.row.demo" : "library.row.\(entry.id.uuidString)" }
}

/// Liste de l'écran Bibliothèque : section « Démonstration », puis « Mes sons » du plus récent au
/// plus ancien (l'ordre de `LibraryStoring.entries`).
struct LibraryListModel: Equatable {
    let demo: [LibraryRowItem]
    let mine: [LibraryRowItem]

    init(entries: [LibraryEntry], loadedOn: (UUID) -> [DeckID]) {
        let rows = entries.map { LibraryRowItem(entry: $0, loadedOn: loadedOn($0.id)) }
        demo = rows.filter(\.isDemo)
        mine = rows.filter { !$0.isDemo }
    }

    enum Idiom {
        case phone, pad, mac
    }

    /// Pied de « Mes sons » quand rien n'est importé (UX §5.19).
    static func emptyText(for idiom: Idiom) -> String {
        let button = DeckFormatting.quoted("Importer")
        switch idiom {
        case .phone: return "Aucun son importé. Touchez \(button) sur une platine."
        case .pad: return "Aucun son importé. Touchez \(button) ou déposez un fichier sur une platine."
        case .mac: return "Aucun son importé. Cliquez sur \(button) ou déposez un fichier sur une platine."
        }
    }
}

/// Formats de la bibliothèque (UX §8.1).
enum LibraryFormatting {
    private static let nbsp = "\u{00A0}"
    private static let french = Locale(identifier: "fr_FR")

    /// `m:ss` à partir de 10 s (« 3:45 ») ; en dessous, secondes et dixièmes (« 8,0 s »).
    static func duration(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, seconds) : 0
        if value < 10 {
            return "\(decimal(value))\(nbsp)s"
        }
        let total = Int(value.rounded(.down))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// Forme parlée : « 1 minute 12 secondes », « 3 minutes », « 8,0 secondes ».
    static func spokenDuration(_ seconds: Double) -> String {
        let value = seconds.isFinite ? max(0, seconds) : 0
        if value < 10 {
            return "\(decimal(value)) \(value < 2 ? "seconde" : "secondes")"
        }
        let total = Int(value.rounded(.down))
        let minutes = total / 60, rest = total % 60
        var parts: [String] = []
        if minutes > 0 { parts.append("\(minutes) \(minutes > 1 ? "minutes" : "minute")") }
        if rest > 0 || minutes == 0 { parts.append("\(rest) \(rest > 1 ? "secondes" : "seconde")") }
        return parts.joined(separator: " ")
    }

    /// Date d'import au format moyen français : « 14 nov. 2026 ».
    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(french))
    }

    /// Date parlée : « 14 novembre 2026 ».
    static func spokenDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(french))
    }

    /// Origine affichée (D-36) : « Import », « Intégré » ; « Micro » et « Mix » viendront en P2.
    static func origin(_ origin: LibraryEntry.Origin) -> String {
        switch origin {
        case .imported: return "Import"
        case .demo: return "Intégré"
        case .microphone: return "Micro"
        case .mix: return "Mix"
        }
    }

    /// Un chiffre après la virgule décimale : « 8,0 », « 0,2 ».
    private static func decimal(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded(.down))
        return "\(tenths / 10),\(tenths % 10)"
    }
}
