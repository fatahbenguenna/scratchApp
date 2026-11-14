/// Géométrie du geste sur un disque : test de saisie, angle `atan2` déplié, zone morte centrale
/// (spec 5.1 point 5, RM-60, RM-61). Logique pure, testée sous Linux, utilisée par les vues de
/// disque UIKit et AppKit.
///
/// Repère : coordonnées en points, **axe y vers le bas** (UIKit ; une `NSView` de disque doit
/// renvoyer `isFlipped == true`). Dans ce repère, `atan2(dy, dx)` croît dans le sens horaire :
/// l'angle renvoyé est positif dans le sens horaire, c'est-à-dire le sens de lecture normal.
///
/// **Squelette (story EP4, Léa) : ne saisit rien (`begin` renvoie `false`).** À implémenter :
/// - `begin` : saisit seulement si le point est dans le disque (distance ≤ rayon, RM-60) ;
/// - `move` : angle cumulé sans saut à ±π (dépliement par la plus petite différence d'angle) ;
///   gain 1:1 (un tour de doigt = un tour de disque) ;
/// - zone morte (distance < 12 % du rayon, RM-61) : l'angle renvoyé ne change pas ; à la sortie de
///   la zone, le suivi reprend depuis l'angle courant, sans saut ;
/// - `updateGeometry` : redimensionnement de la fenêtre pendant un geste sans saut (6.14).
public struct GestureAngleTracker: Sendable {
    public private(set) var centerX: Double
    public private(set) var centerY: Double
    public private(set) var radius: Double
    public let deadZoneRatio: Double

    /// Angle cumulé courant du doigt, en radians (sens horaire positif).
    public private(set) var angle: Double = 0
    /// Un geste est en cours.
    public private(set) var isTracking = false

    public init(centerX: Double, centerY: Double, radius: Double,
                deadZoneRatio: Double = TurntableConstants.centerDeadZoneRatio) {
        self.centerX = centerX
        self.centerY = centerY
        self.radius = radius
        self.deadZoneRatio = deadZoneRatio
    }

    /// Début de contact en (`x`, `y`). Renvoie `true` si le disque est saisi (RM-60) ; l'angle
    /// initial est alors disponible dans `angle`.
    public mutating func begin(x: Double, y: Double) -> Bool {
        false
    }

    /// Déplacement du contact. Renvoie l'angle cumulé (inchangé dans la zone morte).
    public mutating func move(x: Double, y: Double) -> Double {
        angle
    }

    /// Fin du contact (relâchement ou annulation).
    public mutating func end() {
        isTracking = false
    }

    /// Nouvelle géométrie du disque (rotation de l'écran, redimensionnement), sans saut d'angle.
    public mutating func updateGeometry(centerX: Double, centerY: Double, radius: Double) {
        self.centerX = centerX
        self.centerY = centerY
        self.radius = radius
    }
}
