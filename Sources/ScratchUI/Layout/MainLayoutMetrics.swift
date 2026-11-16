import CoreGraphics

/// Dimensions d'une disposition et de l'arrangement « colonne » d'une platine (UX §4.1 à §4.6).
///
/// Calcul pur, testé. Côte à côte (iPad paysage, Mac) : la table a une largeur fixée par la
/// disposition, les platines prennent le reste ; P = min(colonne − 52, hauteur disponible, 560). Les
/// dispositions iPhone et iPad portrait sont calculées par `LayoutMetrics` (story 4.4).
struct MainLayoutMetrics: Equatable {
    /// Gabarit des éléments : Mac, iPad, iPhone portrait (normal ou compact) et iPhone paysage.
    enum Idiom: Equatable { case mac, tablet, phone, phoneCompact, phoneLandscape }

    let idiom: Idiom
    /// Marge latérale : 16 (Mac, iPhone portrait), 20 (iPad), 0 (iPhone paysage, zones sûres).
    let gutter: CGFloat
    /// Écart entre une colonne de platine et la table : 16, 8 en iPhone paysage.
    let gap: CGFloat
    /// Largeur de la table de mixage M.
    let mixerWidth: CGFloat
    /// Largeur d'une colonne de platine C.
    let columnWidth: CGFloat
    /// Diamètre du plateau P.
    let platter: CGFloat

    /// Taille minimale de la zone de contenu sur Mac (D-38, UX §4.6).
    static let macMinimumSize = CGSize(width: 960, height: 600)

    init(width: CGFloat, height: CGFloat, idiom: Idiom) {
        self.idiom = idiom
        gap = 16
        let mixerRange: ClosedRange<CGFloat> = idiom == .mac ? 240...320 : 280...320
        let mixerShare: CGFloat = idiom == .mac ? 0.20 : 0.22
        gutter = idiom == .mac ? 16 : 20
        mixerWidth = min(max(mixerShare * width, mixerRange.lowerBound), mixerRange.upperBound)
        columnWidth = max(0, (width - 2 * gutter - mixerWidth - 2 * gap) / 2)
        let chrome = idiom == .mac ? Self.macColumnChrome : Self.tabletColumnChrome
        let fitted = min(columnWidth - pitchWidth - platterSpacing, height - 2 * gutter - chrome, 560)
        platter = max(96, fitted.rounded(.down))
    }

    /// Métriques déjà calculées (dispositions de `LayoutMetrics`).
    init(idiom: Idiom, gutter: CGFloat, gap: CGFloat = 16, mixerWidth: CGFloat, columnWidth: CGFloat,
         platter: CGFloat) {
        self.idiom = idiom
        self.gutter = gutter
        self.gap = gap
        self.mixerWidth = mixerWidth
        self.columnWidth = columnWidth
        self.platter = platter
    }

    private var isPhone: Bool { idiom != .mac && idiom != .tablet }

    // MARK: Colonne de platine (arrangement « colonne », UX §4.1)

    /// Hauteur des éléments fixes d'une colonne (hors plateau) : 274 (Mac), 308 (iPad).
    static let macColumnChrome: CGFloat = 274
    static let tabletColumnChrome: CGFloat = 308

    /// En-tête : 52 (iPad, Mac), 44 (iPhone portrait), 28 sur une ligne (iPhone paysage).
    var headerHeight: CGFloat { isPhone ? (idiom == .phoneLandscape ? 28 : 44) : 52 }
    var waveformHeight: CGFloat {
        switch idiom {
        case .mac: return 56
        case .tablet: return 64
        case .phone: return 48
        case .phoneCompact: return 36
        case .phoneLandscape: return 28
        }
    }
    var overviewHeight: CGFloat {
        switch idiom {
        case .mac, .tablet: return 32
        case .phone: return 28
        case .phoneCompact: return 24
        case .phoneLandscape: return 20
        }
    }
    /// Visuel de l'aperçu (UX §5.8) : 28 sur Mac, centré dans sa rangée de 32 ; sinon toute la rangée.
    /// La zone tactile de 44 déborde vers le haut.
    var overviewVisualHeight: CGFloat { idiom == .mac ? 28 : overviewHeight }
    var transportHeight: CGFloat { idiom == .tablet ? 56 : 44 }
    let resistanceHeight: CGFloat = 44
    let pitchWidth: CGFloat = 44
    let platterSpacing: CGFloat = 8

    /// Espacements entre les rangées : après l'en-tête, la forme d'onde, l'aperçu, le plateau et le
    /// transport (somme : 46 sur Mac, 60 sur iPad).
    var rowSpacings: [CGFloat] {
        switch idiom {
        case .mac: return [8, 6, 12, 12, 8]
        case .tablet: return [12, 12, 12, 12, 12]
        case .phone: return [8, 4, 8, 8, 8]
        case .phoneCompact: return [6, 4, 6, 6, 6]
        case .phoneLandscape: return [4, 4, 10, 8, 8]
        }
    }

    /// Hauteur des éléments fixes d'une colonne (hors plateau) : 274 (Mac), 308 (iPad), 198 (iPhone
    /// paysage).
    var columnChrome: CGFloat {
        headerHeight + waveformHeight + overviewHeight + transportHeight + resistanceHeight
            + rowSpacings.reduce(0, +)
    }

    // MARK: Transport (UX §4.2 à §4.6, §5.2, §5.3)

    var startStopWidth: CGFloat {
        switch idiom {
        case .tablet: return 104
        case .phoneLandscape: return 48
        default: return 80
        }
    }
    var speedSegmentWidth: CGFloat {
        switch idiom {
        case .tablet: return 56
        case .phoneLandscape: return 44
        default: return 48
        }
    }
    var setCueWidth: CGFloat {
        switch idiom {
        case .mac: return 80
        case .tablet: return 104
        case .phone, .phoneCompact: return 88
        case .phoneLandscape: return 44
        }
    }
    var cueWidth: CGFloat {
        switch idiom {
        case .mac: return 48
        case .tablet: return 70
        case .phone, .phoneCompact: return 64
        case .phoneLandscape: return 44
        }
    }
    var transportSpacing: CGFloat {
        switch idiom {
        case .phone: return 11
        case .phoneCompact: return 5
        case .phoneLandscape: return 4
        default: return 8
        }
    }

    // MARK: Table de mixage (UX §4.2 à §4.6, §5.12)

    /// Hauteur du crossfader : 44 (Mac), 56 (iPad, iPhone).
    var crossfaderHeight: CGFloat { idiom == .mac ? 44 : 56 }

    /// Hauteur du contenu d'une colonne de platine (plateau et éléments fixes).
    var columnContentHeight: CGFloat { platter + columnChrome }

    /// Marge sous le crossfader : aligné sur la rangée de transport (iPad, Mac), sur la rangée de
    /// résistance en iPhone paysage (UX §4.3).
    var crossfaderBottomInset: CGFloat { idiom == .phoneLandscape ? 0 : resistanceHeight + rowSpacings[4] }
}
