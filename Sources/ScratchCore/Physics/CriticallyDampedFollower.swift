import Foundation

/// Filtre du second ordre à amortissement critique : l'angle du disque tenu suit la cible du doigt
/// (spec 5.1 point 3, SF-06, SF-22, SF-23, RM-12 ; architecture §6.3).
///
/// Modèle continu : `θ'' = (cible − θ) / τ² − 2 θ' / τ` (pulsation propre 1/τ, amortissement 1).
/// Cible fixe depuis le repos : convergence sans dépassement ; doigt immobile : vitesse nulle.
///
/// Discrétisation **exacte** pour une cible constante sur l'échantillon (bloqueur d'ordre zéro) :
/// avec `e = θ − cible`, `B = ω + e/τ` et `E = e^(−h/τ)`,
/// `e(h) = (e + B h) E` et `ω(h) = (ω − B h/τ) E`. Inconditionnellement stable quel que soit `h/τ` ;
/// changer τ entre deux échantillons ne modifie ni `θ` ni `ω` (aucune discontinuité, SF-23).
///
/// Fil audio uniquement : aucune allocation ; l'exponentielle est calculée hors de la boucle, une
/// fois par bloc (`Coefficients`). Pas de dénormaux persistants : l'état est ramené exactement sur
/// la cible sous un seuil infime.
struct CriticallyDampedFollower: Equatable, Sendable {
    /// Coefficients d'un pas, calculés une fois par bloc ou par changement de réglage.
    struct Coefficients: Equatable, Sendable {
        let timeConstant: Double
        let dt: Double
        let inverseTimeConstant: Double
        let decay: Double

        /// - Parameters:
        ///   - timeConstant: τ en secondes ; une valeur nulle, négative ou non finie aligne l'état
        ///     sur la cible à chaque pas.
        ///   - dt: période d'échantillonnage, en secondes.
        init(timeConstant: Double, dt: Double) {
            self.timeConstant = timeConstant
            if timeConstant.isFinite, timeConstant > 0, dt.isFinite, dt > 0 {
                self.dt = dt
                inverseTimeConstant = 1 / timeConstant
                decay = exp(-dt / timeConstant)
            } else {
                // Immediate alignment: e(h) = 0 and ω(h) = 0 without any division.
                self.dt = 0
                inverseTimeConstant = 0
                decay = 0
            }
        }
    }

    /// Sous ces seuils (rad, rad/s), l'état est posé exactement sur la cible (anti-dénormaux).
    static let restAngleThreshold = 1e-15
    static let restVelocityThreshold = 1e-12

    /// Dernière cible (rad).
    private(set) var target: Double
    /// Écart `θ − cible` (rad). L'état est tenu en écart, et non en angle absolu : il décroît
    /// sans être arrondi à la précision de l'angle cumulé et atteint exactement 0 au repos.
    private(set) var error: Double = 0
    /// Vitesse angulaire courante (rad/s).
    private(set) var velocity: Double

    /// Angle courant (rad).
    var angle: Double { target + error }

    init(angle: Double = 0, velocity: Double = 0) {
        self.target = angle
        self.velocity = velocity
    }

    /// Réinitialise l'état (saisie du disque : angle et vitesse courants, aucun saut).
    mutating func reset(angle: Double, velocity: Double) {
        target = angle
        error = 0
        self.velocity = velocity
    }

    /// Décale l'angle et la cible sans changer l'écart ni la vitesse (recalage du disque, IC-09).
    mutating func shift(by offset: Double) {
        target += offset
    }

    /// Fil audio uniquement. Avance d'un échantillon vers `newTarget`, tenue constante sur le pas.
    mutating func step(target newTarget: Double, coefficients c: Coefficients) {
        let currentError = error - (newTarget - target)
        target = newTarget
        let b = velocity + currentError * c.inverseTimeConstant
        let nextError = (currentError + b * c.dt) * c.decay
        let nextVelocity = (velocity - b * c.dt * c.inverseTimeConstant) * c.decay
        if abs(nextError) < Self.restAngleThreshold, abs(nextVelocity) < Self.restVelocityThreshold {
            error = 0
            velocity = 0
        } else {
            error = nextError
            velocity = nextVelocity
        }
    }

    /// Variante de commodité (tests, hors boucle de rendu) : calcule les coefficients à chaque appel.
    mutating func step(target: Double, timeConstant: Double, dt: Double) {
        step(target: target, coefficients: Coefficients(timeConstant: timeConstant, dt: dt))
    }

    /// Fil audio uniquement. Borne la vitesse à `±limit` après un pas parti de `previousAngle` :
    /// le déplacement du pas est ramené à `limit × dt` au plus (le disque glisse sous un doigt
    /// plus rapide que la vitesse maximale, SF-77).
    mutating func limitVelocity(to limit: Double, previousAngle: Double, dt: Double) {
        guard abs(velocity) > limit else { return }
        velocity = velocity > 0 ? limit : -limit
        let maximumStep = limit * dt
        let stepAngle = angle - previousAngle
        if stepAngle > maximumStep {
            error = previousAngle + maximumStep - target
        } else if stepAngle < -maximumStep {
            error = previousAngle - maximumStep - target
        }
    }
}
