/// Géométrie d'un disque dans le repère de sa surface de saisie (UX §5.1) : la surface est le cadre
/// carré du plateau P ; vinyle R = 0,46 P ; zone de saisie `min(R + 6, P / 2)`. Logique pure.
struct DiscGeometry: Equatable {
    let centerX: Double
    let centerY: Double
    let vinylRadius: Double
    let grabRadius: Double

    init(width: Double, height: Double) {
        let platter = max(0, min(width, height))
        centerX = width / 2
        centerY = height / 2
        vinylRadius = 0.46 * platter
        grabRadius = min(vinylRadius + 6, platter / 2)
    }

    /// Le point (repère du traqueur) est dans la zone de saisie.
    func contains(x: Double, y: Double) -> Bool {
        let dx = x - centerX
        let dy = y - centerY
        return dx * dx + dy * dy <= grabRadius * grabRadius
    }

    /// Point d'une vue vers le repère du traqueur (y vers le bas, comme le contrat) : une vue non
    /// retournée (`isFlipped == false`, y vers le haut) est réexprimée par rapport à sa hauteur.
    static func trackerPoint(x: Double, y: Double, height: Double, isFlipped: Bool) -> (x: Double, y: Double) {
        (x, isFlipped ? y : height - y)
    }

    /// Déplacement des doigts dans le repère de la vue (y vers le bas) à partir des deltas de
    /// défilement d'AppKit : avec le « défilement naturel » (`isDirectionInvertedFromDevice`), les
    /// deltas suivent déjà les doigts ; sinon, ils sont inversés (D-24, sens à confirmer sur appareil).
    static func fingerDelta(scrollingDeltaX: Double, scrollingDeltaY: Double,
                            invertedFromDevice: Bool) -> (dx: Double, dy: Double) {
        let sign: Double = invertedFromDevice ? 1 : -1
        return (sign * scrollingDeltaX, sign * scrollingDeltaY)
    }
}
