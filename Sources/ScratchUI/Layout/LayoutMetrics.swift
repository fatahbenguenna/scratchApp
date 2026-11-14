import CoreGraphics

/// Disposition de l'écran principal (UX §4.1).
enum LayoutKind: Equatable, Sendable {
    /// A | table | B : Mac, iPad paysage, fenêtres larges (UX §4.5, §4.6).
    case sideBySide
    /// Une platine et un sélecteur A | B : iPhone portrait, fenêtre iPad étroite (UX §4.2, §4.7).
    case singleDeck
    /// Deux platines réduites et la table au centre : iPhone paysage (UX §4.3).
    case compactSideBySide
    /// Platines empilées en bandes, B en miroir, table entre les deux : iPad portrait (UX §4.4).
    case stacked
}

/// Choix de la disposition et tailles des dispositions iPhone et iPad portrait (story 4.4 ; UX §4.1
/// à §4.4 ; D-29). Calcul pur, testé ; la disposition côte à côte est calculée par
/// `MainLayoutMetrics(width:height:idiom:)`. Les tailles sont celles de la zone sûre.
enum LayoutMetrics {
    /// Règle de l'UX §4.1 : par taille de fenêtre, jamais par modèle d'appareil.
    static func kind(width: CGFloat, height: CGFloat, isMac: Bool) -> LayoutKind {
        if isMac { return .sideBySide }
        if width < 600 { return .singleDeck }
        if height < 500 { return .compactSideBySide }
        if width < height { return .stacked }
        return .sideBySide
    }

    /// Éléments fixes de l'iPhone portrait hors plateau (barre supérieure, colonne, table, marges) :
    /// 448 pt, 418 en variante compacte (hauteur utile < 700 pt, iPhone SE).
    static let singleDeckChrome: CGFloat = 448
    static let singleDeckCompactChrome: CGFloat = 418

    /// iPhone portrait (UX §4.2) : P = 309 sur 393 × 759 (iPhone 15, zone sûre).
    static func singleDeck(width: CGFloat, height: CGFloat) -> MainLayoutMetrics {
        let compact = height < 700
        let column = max(0, width - 32)
        let chrome = compact ? singleDeckCompactChrome : singleDeckChrome
        return MainLayoutMetrics(idiom: compact ? .phoneCompact : .phone, gutter: 16, mixerWidth: column,
                                 columnWidth: column, platter: fitted(min(column - 52, height - chrome)))
    }

    /// iPhone paysage (UX §4.3) : colonnes 236 | 8 | 246 | 8 | 236 et P = 174 sur 734 × 372 (iPhone 15,
    /// zone sûre). Les platines prennent la largeur dont elles ont besoin, la table le reste (≥ 180).
    static func compactSideBySide(width: CGFloat, height: CGFloat) -> MainLayoutMetrics {
        let chrome = MainLayoutMetrics(idiom: .phoneLandscape, gutter: 0, mixerWidth: 0, columnWidth: 0,
                                       platter: 0).columnChrome
        let widest = max(0, (width - 16 - 180) / 2)
        var platter = fitted(min(height - chrome, widest - 52))
        let column = min(widest, max(platter + 52, 236))
        platter = min(platter, fitted(column - 52))
        return MainLayoutMetrics(idiom: .phoneLandscape, gutter: 0, gap: 8, mixerWidth: width - 2 * column - 16,
                                 columnWidth: column, platter: platter)
    }

    /// Hauteur de la table de l'iPad portrait, entre les deux bandes.
    static let stackedMixerHeight: CGFloat = 176
    /// Largeur du panneau d'une bande (en-tête, formes d'onde, transport, résistance).
    static let bandPanelWidth: CGFloat = 280

    /// iPad portrait (UX §4.4) : bandes de 780 × 456 et P = 432 sur 820 × 1136 (zone sûre) ;
    /// `mixerWidth` est la largeur des bandes et de la table.
    static func stacked(width: CGFloat, height: CGFloat) -> MainLayoutMetrics {
        let bandWidth = max(0, width - 40)
        let platter = fitted(min(bandWidth - 8 - 44 - 16 - bandPanelWidth, bandHeight(height: height)))
        return MainLayoutMetrics(idiom: .tablet, gutter: 20, mixerWidth: bandWidth, columnWidth: bandPanelWidth,
                                 platter: platter)
    }

    /// Hauteur d'une bande : marges de 12, table de 176 et écarts de 12.
    static func bandHeight(height: CGFloat) -> CGFloat {
        max(0, (height - 48 - stackedMixerHeight) / 2)
    }

    private static func fitted(_ value: CGFloat) -> CGFloat {
        max(96, min(value, 560).rounded(.down))
    }
}
