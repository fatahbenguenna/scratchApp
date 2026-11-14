import CoreGraphics

/// Dimensions de la disposition côte à côte A | table | B (UX §4.1, §4.5 iPad paysage, §4.6 Mac).
///
/// Calcul pur, testé : la table a une largeur fixée par la disposition, les platines prennent le
/// reste ; P = min(colonne − 52, hauteur disponible, 560).
struct MainLayoutMetrics: Equatable {
    enum Idiom: Equatable { case mac, tablet }

    let idiom: Idiom
    /// Marge latérale : 16 (Mac), 20 (iPad).
    let gutter: CGFloat
    /// Écart entre une colonne de platine et la table.
    let gap: CGFloat = 16
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
        let mixerRange: ClosedRange<CGFloat> = idiom == .mac ? 240...320 : 280...320
        let mixerShare: CGFloat = idiom == .mac ? 0.20 : 0.22
        gutter = idiom == .mac ? 16 : 20
        mixerWidth = min(max(mixerShare * width, mixerRange.lowerBound), mixerRange.upperBound)
        columnWidth = max(0, (width - 2 * gutter - mixerWidth - 2 * gap) / 2)
        let chrome = idiom == .mac ? Self.macColumnChrome : Self.tabletColumnChrome
        let fitted = min(columnWidth - pitchWidth - platterSpacing, height - 2 * gutter - chrome, 560)
        platter = max(96, fitted.rounded(.down))
    }

    // MARK: Colonne de platine (arrangement « colonne », UX §4.1)

    /// Hauteur des éléments fixes d'une colonne (hors plateau) : 274 (Mac), 308 (iPad).
    static let macColumnChrome: CGFloat = 274
    static let tabletColumnChrome: CGFloat = 308

    let headerHeight: CGFloat = 52
    var waveformHeight: CGFloat { idiom == .mac ? 56 : 64 }
    let overviewHeight: CGFloat = 32
    var transportHeight: CGFloat { idiom == .mac ? 44 : 56 }
    let resistanceHeight: CGFloat = 44
    let pitchWidth: CGFloat = 44
    let platterSpacing: CGFloat = 8

    /// Espacements entre les rangées : après l'en-tête, la forme d'onde, l'aperçu, le plateau et le
    /// transport (somme : 46 sur Mac, 60 sur iPad).
    var rowSpacings: [CGFloat] { idiom == .mac ? [8, 6, 12, 12, 8] : [12, 12, 12, 12, 12] }

    // MARK: Transport (UX §4.5, §4.6, §5.2, §5.3)

    var startStopWidth: CGFloat { idiom == .mac ? 80 : 104 }
    var speedSegmentWidth: CGFloat { idiom == .mac ? 48 : 56 }
    var setCueWidth: CGFloat { idiom == .mac ? 80 : 104 }
    var cueWidth: CGFloat { idiom == .mac ? 48 : 70 }
    let transportSpacing: CGFloat = 8

    // MARK: Table de mixage (UX §4.5, §4.6, §5.12)

    /// Hauteur du crossfader : 44 (Mac), 56 (iPad).
    var crossfaderHeight: CGFloat { idiom == .mac ? 44 : 56 }

    /// Hauteur du contenu d'une colonne de platine (plateau et éléments fixes).
    var columnContentHeight: CGFloat {
        platter + (idiom == .mac ? Self.macColumnChrome : Self.tabletColumnChrome)
    }

    /// Marge sous le crossfader pour l'aligner sur la rangée de transport (au-dessus de la résistance).
    var crossfaderBottomInset: CGFloat { resistanceHeight + rowSpacings[4] }
}
