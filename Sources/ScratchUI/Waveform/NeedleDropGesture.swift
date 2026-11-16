/// Machine d'états du needle drop sur l'aperçu complet (story 4.6 CA 4 ; SF-71, D-33 ; UX §5.8),
/// en calcul pur.
///
/// 1. Appui : tête fantôme et bulle de temps sous le doigt, sauf si le disque de la platine est
///    tenu : le geste entier est alors ignoré, sans tête fantôme.
/// 2. Glisser : la tête fantôme suit. Plus de 44 pt au-dessus ou au-dessous de la zone tactile, elle
///    disparaît (le relâchement y annulera le geste) ; elle revient si le doigt revient.
/// 3. Relâcher : la tête se place à la position fantôme, sauf hors de la zone (annulation) ou si
///    le disque est tenu à ce moment (geste ignoré).
struct NeedleDropGesture: Equatable {
    enum Phase: Equatable {
        case idle
        /// Doigt dans la zone : tête fantôme affichée.
        case tracking
        /// Doigt sorti de plus de 44 pt verticalement : relâcher annule.
        case outside
        /// Disque tenu à l'appui : rien n'est affiché jusqu'au relâchement.
        case ignored
    }

    /// Distance verticale hors de la zone tactile au-delà de laquelle le relâchement annule.
    static let cancelDistance = 44.0

    private(set) var phase = Phase.idle
    /// Abscisse de la tête fantôme, pendant `tracking`.
    private(set) var ghostX: Double?

    var isActive: Bool { phase != .idle }

    /// Appui à (`x`, `y`) ; `zoneHeight` : hauteur de la zone tactile (origine en haut).
    mutating func begin(x: Double, y: Double, zoneHeight: Double, isHeld: Bool) {
        if isHeld {
            phase = .ignored
            ghostX = nil
            return
        }
        phase = .tracking
        track(x: x, y: y, zoneHeight: zoneHeight)
    }

    mutating func move(x: Double, y: Double, zoneHeight: Double) {
        guard phase == .tracking || phase == .outside else { return }
        track(x: x, y: y, zoneHeight: zoneHeight)
    }

    /// Relâchement : abscisse où placer la tête, ou `nil` (annulé, ignoré).
    mutating func end(x: Double, y: Double, zoneHeight: Double, isHeld: Bool) -> Double? {
        defer { reset() }
        guard phase == .tracking || phase == .outside else { return nil }
        track(x: x, y: y, zoneHeight: zoneHeight)
        guard phase == .tracking, !isHeld else { return nil }
        return ghostX
    }

    /// Annulation par le système (geste interrompu).
    mutating func reset() {
        phase = .idle
        ghostX = nil
    }

    private mutating func track(x: Double, y: Double, zoneHeight: Double) {
        let outside = y < -Self.cancelDistance || y > zoneHeight + Self.cancelDistance
        phase = outside ? .outside : .tracking
        ghostX = outside || !x.isFinite ? nil : x
    }
}
