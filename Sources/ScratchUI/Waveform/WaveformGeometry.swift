import ScratchCore

/// Géométrie de la forme d'onde zoomée (UX §5.7), en calcul pur.
///
/// Fenêtre de ±1,8 s (un tour de disque de chaque côté) sur toute la largeur, tête fixe au centre.
/// Le contenu est découpé en tuiles de 512 pt numérotées depuis 0 s (indices négatifs dans l'amorce) :
/// chaque tuile est rendue une fois, puis seulement translatée à chaque image (UX §10.2).
struct ZoomGeometry: Equatable {
    /// 3,6 s sur toute la largeur.
    static let windowSeconds = 2 * TurntableConstants.secondsPerRevolution
    static let tileWidth = 512.0

    let width: Double

    var secondsPerPoint: Double { Self.windowSeconds / max(width, 1) }
    var tileSeconds: Double { Self.tileWidth * secondsPerPoint }

    /// Fenêtre affichée pour une tête à `position` : [p − 1,8 ; p + 1,8].
    func window(position: Double) -> ClosedRange<Double> {
        (position - Self.windowSeconds / 2)...(position + Self.windowSeconds / 2)
    }

    /// Abscisse de contenu (origine à 0 s) du bord gauche de la vue.
    func leftEdge(position: Double) -> Double {
        position / secondsPerPoint - width / 2
    }

    /// Tuiles qui recouvrent la vue (deux ou trois).
    func visibleTiles(position: Double) -> ClosedRange<Int> {
        guard position.isFinite else { return 0...0 }
        let left = leftEdge(position: position)
        let first = Int((left / Self.tileWidth).rounded(.down))
        let last = Int(((left + width) / Self.tileWidth).rounded(.down))
        return first...max(first, last)
    }

    /// Décalage horizontal de la tuile `index` dans la vue.
    func tileOffset(_ index: Int, position: Double) -> Double {
        Double(index) * Self.tileWidth - leftEdge(position: position)
    }

    /// Abscisse d'un instant dans la vue (le CUE, par exemple).
    func x(of seconds: Double, position: Double) -> Double {
        width / 2 + (seconds - position) / secondsPerPoint
    }

    /// Intervalle de temps couvert par la tuile `index`.
    func tileRange(_ index: Int) -> Range<Double> {
        let start = Double(index) * tileSeconds
        return start..<(start + tileSeconds)
    }

    /// Parties de `range` hors du son ([0 ; durée]) : amorce et zone après la fin, hachurées.
    static func outsideRanges(of range: Range<Double>, duration: Double) -> [Range<Double>] {
        var ranges: [Range<Double>] = []
        if range.lowerBound < 0 { ranges.append(range.lowerBound..<min(range.upperBound, 0)) }
        let end = max(duration, 0)
        if range.upperBound > end { ranges.append(max(range.lowerBound, end)..<range.upperBound) }
        return ranges.filter { !$0.isEmpty }
    }
}

/// Géométrie de l'aperçu complet (UX §5.8), en calcul pur : [−2 s ; durée] sur toute la largeur,
/// l'amorce occupant une zone proportionnelle au début.
struct OverviewGeometry: Equatable {
    let width: Double
    let duration: Double

    var start: Double { -TurntableConstants.leadInSeconds }
    var span: Double { max(duration, 0) - start }

    /// Abscisse d'un instant (bornée à la vue).
    func x(of seconds: Double) -> Double {
        guard span > 0, seconds.isFinite else { return 0 }
        return min(max((seconds - start) / span, 0), 1) * width
    }

    /// Instant visé par une abscisse (bornée à la vue), amorce comprise.
    func seconds(atX x: Double) -> Double {
        guard width > 0, x.isFinite else { return start }
        return start + min(max(x / width, 0), 1) * span
    }
}
