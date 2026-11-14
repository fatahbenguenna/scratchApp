import Foundation

/// Géométrie du geste sur un disque : test de saisie, angle `atan2` déplié, zone morte centrale
/// (spec 5.1 point 5, RM-04, RM-60, RM-61 ; UX §5.1, §6.1). Logique pure, testée sous Linux.
///
/// Repère : coordonnées en points, **axe y vers le bas** (UIKit ; une `NSView` de disque renvoie
/// `isFlipped == true`). L'angle est mesuré depuis midi et croît dans le sens horaire, comme les
/// angles du contrat moteur ; gain 1:1 (un tour de doigt = un tour de disque). Le moteur travaille
/// en relatif (prise relative, ADR-08) : seule la variation de l'angle compte.
///
/// - `begin` saisit seulement si le contact commence dans le rayon de saisie (RM-60) ;
/// - `move` déplie l'angle par la plus petite différence (aucun saut à ±π) ;
/// - zone morte (distance < 12 % du rayon du vinyle, RM-61) : l'angle est figé ; à la sortie, le
///   suivi reprend depuis l'angle courant, sans saut. Un segment qui traverse la zone entre deux
///   échantillons est traité de même (aucun demi-tour fictif) ;
/// - `predictedAngle` calcule l'angle d'une touche prédite sans modifier l'état (SF-78) ;
/// - `updateGeometry` recale le dernier point connu dans la nouvelle géométrie, sans saut (6.14).
public struct GestureAngleTracker: Sendable {
    public private(set) var centerX: Double
    public private(set) var centerY: Double
    /// Rayon du vinyle R : sert à la zone morte.
    public private(set) var radius: Double
    /// Rayon de saisie : `min(R + 6, P / 2)` dans l'interface (UX §5.1) ; `radius` par défaut.
    public private(set) var grabRadius: Double
    public let deadZoneRatio: Double

    /// Angle cumulé courant du doigt, en radians (sens horaire positif).
    public private(set) var angle: Double = 0
    /// Un geste est en cours.
    public private(set) var isTracking = false

    private var lastX = 0.0
    private var lastY = 0.0
    /// Angle brut (dans ]−π ; π]) du dernier point réel, référence du dépliement.
    private var lastRawAngle = 0.0
    private var isInDeadZone = false

    public init(centerX: Double, centerY: Double, radius: Double, grabRadius: Double? = nil,
                deadZoneRatio: Double = TurntableConstants.centerDeadZoneRatio) {
        self.centerX = centerX
        self.centerY = centerY
        self.radius = radius
        self.grabRadius = grabRadius ?? radius
        self.deadZoneRatio = deadZoneRatio
    }

    /// Le point est dans la zone de saisie (bord compris).
    public func contains(x: Double, y: Double) -> Bool {
        hypot(x - centerX, y - centerY) <= grabRadius
    }

    /// Début de contact en (`x`, `y`). Renvoie `true` si le disque est saisi (RM-60) ; l'angle
    /// initial est alors dans `angle`. Un contact commencé hors de la zone de saisie est refusé.
    public mutating func begin(x: Double, y: Double) -> Bool {
        guard x.isFinite, y.isFinite, contains(x: x, y: y) else { return false }
        isTracking = true
        lastX = x
        lastY = y
        lastRawAngle = rawAngle(x: x, y: y)
        isInDeadZone = inDeadZone(x: x, y: y)
        angle = lastRawAngle
        return true
    }

    /// Déplacement du contact (échantillon réel). Renvoie l'angle cumulé, inchangé dans la zone morte.
    @discardableResult
    public mutating func move(x: Double, y: Double) -> Double {
        guard isTracking, x.isFinite, y.isFinite else { return angle }
        let raw = rawAngle(x: x, y: y)
        let frozen = inDeadZone(x: x, y: y) || isInDeadZone || crossesDeadZone(toX: x, y: y)
        if !frozen { angle += Self.wrapped(raw - lastRawAngle) }
        lastX = x
        lastY = y
        lastRawAngle = raw
        isInDeadZone = inDeadZone(x: x, y: y)
        return angle
    }

    /// Angle d'une touche prédite, calculé depuis le dernier point réel sans modifier l'état : la
    /// touche réelle suivante est dépliée depuis ce même point, sans erreur cumulée (SF-78).
    public func predictedAngle(x: Double, y: Double) -> Double {
        guard isTracking, x.isFinite, y.isFinite else { return angle }
        if inDeadZone(x: x, y: y) || isInDeadZone || crossesDeadZone(toX: x, y: y) { return angle }
        return angle + Self.wrapped(rawAngle(x: x, y: y) - lastRawAngle)
    }

    /// Fin du contact (relâchement ou annulation).
    public mutating func end() {
        isTracking = false
    }

    /// Nouvelle géométrie du disque (rotation de l'écran, redimensionnement) : le dernier point connu
    /// est réexprimé autour du nouveau centre, l'angle cumulé ne change pas (6.14).
    public mutating func updateGeometry(centerX: Double, centerY: Double, radius: Double, grabRadius: Double? = nil) {
        self.centerX = centerX
        self.centerY = centerY
        self.radius = radius
        self.grabRadius = grabRadius ?? radius
        guard isTracking else { return }
        lastRawAngle = rawAngle(x: lastX, y: lastY)
        isInDeadZone = inDeadZone(x: lastX, y: lastY)
    }

    // MARK: Géométrie

    /// Angle depuis midi, sens horaire positif, dans ]−π ; π] (y vers le bas).
    private func rawAngle(x: Double, y: Double) -> Double {
        atan2(x - centerX, centerY - y)
    }

    private func inDeadZone(x: Double, y: Double) -> Bool {
        hypot(x - centerX, y - centerY) < deadZoneRatio * radius
    }

    /// Le segment entre le dernier point et (`x`, `y`) passe dans la zone morte.
    private func crossesDeadZone(toX x: Double, y: Double) -> Bool {
        let dx = x - lastX
        let dy = y - lastY
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return false }
        let t = min(1, max(0, ((centerX - lastX) * dx + (centerY - lastY) * dy) / lengthSquared))
        return inDeadZone(x: lastX + t * dx, y: lastY + t * dy)
    }

    /// Ramène un écart d'angle dans ]−π ; π].
    static func wrapped(_ delta: Double) -> Double {
        let twoPi = 2 * Double.pi
        var value = delta.truncatingRemainder(dividingBy: twoPi)
        if value > .pi { value -= twoPi } else if value <= -.pi { value += twoPi }
        return value
    }
}
