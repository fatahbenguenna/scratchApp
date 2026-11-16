import Foundation

/// Physique d'une platine : moteur, plateau, feutrine, disque tenu, tête de lecture, CUE et repère
/// (spec v2.1 §5.1 et §5.4 ; architecture §6.3 ; story 1.1). Intégrée **à chaque échantillon** dans
/// `process` (ADR-06). Fil audio uniquement pour `process` ; les autres méthodes sont appelées par
/// le fil audio entre deux blocs (application des commandes). Aucune allocation, aucun verrou.
///
/// Modèle :
/// 1. **Plateau** : `ωp` → `ωt = 2π × RPM/60 × (1 + pitch)` moteur actif, → 0 sinon, par rampes
///    linéaires de pentes `ωt / startDuration` (accélération) et `ωt / brakeDuration`
///    (décélération), recalculées à chaque bloc : un changement de RPM, de pitch ou de durée, comme
///    START pendant le freinage, repart de la vitesse courante, sans discontinuité (SF-04, SF-05,
///    SF-11, SF-68). `platterAngle` intègre `ωp`.
/// 2. **Disque libre entraîné** (`coupled`) : la feutrine entraîne le disque vers `ωp` par une
///    réponse du premier ordre de constante τ = T/3 (T = `slipmatCatchUp`) : l'écart de vitesse est
///    réduit à 5 % de sa valeur initiale en T (e⁻³ ≈ 4,98 %, D-03) ; T = 0 aligne `ωd` sur `ωp` dès
///    l'échantillon suivant. Discrétisation exacte `α = 1 − e^(−h/τ)`. Le disque libre suit aussi le
///    plateau qui freine après STOP (6.2 « Arrêter la platine »).
/// 3. **Disque libre en roue libre** (`coasting`) : un disque relâché moteur arrêté ralentit par
///    friction constante jusqu'à 0, sans reprise motorisée (SF-10, RM-07, D-03). Choix documenté :
///    la décélération est fixée au relâchement à `|ωd| / freeSpinStopDuration`, si bien que l'arrêt
///    survient **exactement** 150 ms après le relâchement quelle que soit la vitesse (jusqu'à 16 ×
///    ωref). START remet le disque sous l'entraînement de la feutrine.
/// 4. **Disque tenu** (`held`) : `θd` suit `θf + gripOffset` par `CriticallyDampedFollower`,
///    τ = lerp(2 ms, 35 ms, résistance). À la saisie, le filtre part de l'angle et de la vitesse
///    courants et `gripOffset = θd − θf` (aucun saut, SF-06). Le relâchement prend effet quand
///    `FingerTrajectory` a rejoué la fin du geste. La vitesse du disque est bornée à ±16 × ωref
///    (au-delà, le disque glisse sous le doigt, SF-77).
/// 5. **Tête** : `p += Δθd × 1,8 / 2π` à chaque échantillon (`Δθd` est l'angle parcouru pendant
///    l'échantillon : `p` et `discAngle` restent solidaires, RM-13), bornée à [−2 s ; durée]. En
///    butée, le disque continue de tourner ; dès que le mouvement repart vers l'intérieur, la tête
///    revient dans le son sans « dérouler » les tours accumulés et `realignDisc()` recale l'angle du
///    disque (RM-55, IC-09, D-10).
/// 6. **Vitesse de lecture** : `ωd / ωref`, bornée à ±16 (RM-50, SF-77).
/// 7. **Résistance** : un changement pendant la tenue est lissé (τ appliqué varie de 0,12 s/s au
///    plus, #54) ; elle n'agit que sur le disque tenu, jamais sur le plateau, les durées moteur ni
///    le rattrapage (RM-11, RM-54).
struct DeckPhysics {
    /// État du disque vis-à-vis du plateau et du doigt.
    enum DiscMode: Equatable, Sendable {
        /// Libre, entraîné par la feutrine vers la vitesse du plateau.
        case coupled
        /// Libre, relâché moteur arrêté : décélération linéaire jusqu'à l'arrêt.
        case coasting
        /// Tenu : suit le doigt.
        case held
    }

    private(set) var sampleRate: Double
    private(set) var motorTimings = MotorTimings.defaults

    private(set) var motorOn = false
    private(set) var speed = TurntableSpeed.rpm33
    private(set) var pitch: Double = 0
    private(set) var resistance: Double = TurntableConstants.defaultResistance

    private(set) var durationSeconds: Double = 0
    private(set) var positionSeconds: Double = 0
    private(set) var playbackRate: Double = 0
    private(set) var discAngle: Double = 0
    private(set) var platterAngle: Double = 0
    private(set) var cueSeconds: Double?

    /// Vitesse angulaire du plateau `ωp` (rad/s).
    private(set) var platterVelocity: Double = 0
    /// Vitesse angulaire du disque `ωd` (rad/s).
    private(set) var discVelocity: Double = 0
    private(set) var discMode = DiscMode.coasting
    /// Décalage entre l'angle du disque et celui du doigt, fixé à la saisie, corrigé au recalage.
    private(set) var gripOffset: Double = 0
    /// La tête est bloquée sur une butée par le mouvement du disque (amorce ou sillon fermé).
    private(set) var isPinnedAtBound = false
    /// Position de la tête avant le premier saut (CUE, needle drop) appliqué depuis le dernier bloc :
    /// la voix fond l'ancienne position dans la nouvelle (SF-13, SF-71 ; story 1.3).
    private(set) var pendingJumpOrigin: Double?

    private var follower = CriticallyDampedFollower()
    /// Décélération de la roue libre (rad/s²), fixée au relâchement moteur arrêté.
    private var coastDeceleration: Double = 0
    private var finger: FingerTrajectory

    /// - Parameter fingerConfiguration: réglages du rejeu du doigt (les tests fixent un retard
    ///   constant pour mesurer la cinématique exacte).
    init(sampleRate: Double, fingerConfiguration: FingerTrajectory.Configuration = FingerTrajectory.Configuration()) {
        let rate = sampleRate.isFinite && sampleRate > 0 ? sampleRate : 48_000
        self.sampleRate = rate
        self.finger = FingerTrajectory(sampleRate: rate, configuration: fingerConfiguration)
    }

    var isHeld: Bool { finger.isActive }

    /// Angle d'écran du repère (`DeckSnapshot.stickerAngle`) : calculé, jamais cumulé.
    var stickerAngle: Double {
        discAngle - 2 * Double.pi * (cueSeconds ?? 0) / TurntableConstants.secondsPerRevolution
    }
    var isAtEnd: Bool { durationSeconds > 0 && positionSeconds >= durationSeconds }
    var isInLeadIn: Bool { positionSeconds < 0 }

    /// Vitesse cible du moteur `ωt = 2π × RPM / 60 × (1 + pitch)` (rad/s), moteur actif ou non.
    var nominalPlatterVelocity: Double {
        2 * Double.pi * speed.rpm / 60 * (1 + pitch)
    }

    /// Constante de temps du disque tenu visée par la résistance : lerp(2 ms, 35 ms, résistance)
    /// (5.1 point 3).
    var holdTimeConstant: Double {
        let range = TurntableConstants.resistanceTimeConstantRange
        return range.lowerBound + (range.upperBound - range.lowerBound) * resistance
    }

    /// Vitesse maximale de variation de la constante de temps appliquée au disque tenu (s par s).
    ///
    /// Un changement brutal de résistance pendant la tenue ferait rattraper d'un coup le retard du
    /// disque sur le doigt (2 τ v en rampe), jusqu'à 16× (« zip », #54). Une rampe linéaire de τ limite
    /// cet excès au meilleur rapport durée / crête (simulation : 1,32 × la vitesse du geste à 0,12 s/s,
    /// 1,67 × à 0,2 s/s). Toute la plage (35 → 2 ms) est parcourue en 275 ms, un pas de 1 % du curseur
    /// (0,33 ms) en 2,75 ms. Paramètre de calibrage (D-46).
    static let holdTimeConstantSlewRate = 0.12

    /// Constante de temps appliquée au disque tenu : rejoint `holdTimeConstant` à
    /// `holdTimeConstantSlewRate` au plus pendant la tenue ; vaut `holdTimeConstant` sinon (saisie).
    private(set) var appliedHoldTimeConstant: Double = {
        let range = TurntableConstants.resistanceTimeConstantRange
        return range.lowerBound + (range.upperBound - range.lowerBound) * TurntableConstants.defaultResistance
    }()

    /// Dernière cible du doigt (angle cumulé, rad).
    var fingerAngle: Double { finger.output }

    /// Écart de suivi du disque tenu `θd − (θf + gripOffset)` (diagnostic, tests).
    var holdTrackingError: Double { discAngle - (finger.output + gripOffset) }

    // MARK: Réglages

    mutating func setSampleRate(_ rate: Double) {
        guard rate.isFinite, rate > 0 else { return }
        sampleRate = rate
        finger.setSampleRate(rate)
    }

    /// SF-68 : chaque durée est ramenée dans sa plage ; une valeur non finie est ignorée (la valeur
    /// courante est conservée).
    mutating func setMotorTimings(_ timings: MotorTimings) {
        var next = motorTimings
        if timings.startDuration.isFinite { next.startDuration = timings.startDuration }
        if timings.brakeDuration.isFinite { next.brakeDuration = timings.brakeDuration }
        if timings.slipmatCatchUp.isFinite { next.slipmatCatchUp = timings.slipmatCatchUp }
        motorTimings = next.clamped()
    }

    /// START / STOP. RM-53 : indépendant de la tenue du disque. START remet un disque en roue libre
    /// sous l'entraînement de la feutrine.
    mutating func setMotor(_ on: Bool) {
        motorOn = on
        if on, discMode == .coasting { discMode = .coupled }
    }

    mutating func setSpeed(_ newSpeed: TurntableSpeed) { speed = newSpeed }

    mutating func setPitch(_ value: Double) {
        guard value.isFinite else { return }
        pitch = value.clamped(to: TurntableConstants.pitchRange, fallback: 0)
    }

    mutating func setResistance(_ value: Double) {
        guard value.isFinite else { return }
        resistance = value.clamped(to: 0...1, fallback: TurntableConstants.defaultResistance)
    }

    /// RM-56 : STOP immédiat, sans rampe : plateau arrêté, disque libre arrêté ; le disque tenu
    /// reste tenu, sans saut.
    mutating func stopMotorImmediately() {
        motorOn = false
        platterVelocity = 0
        guard discMode != .held else { return }
        discVelocity = 0
        discMode = .coasting
        coastDeceleration = 0
        playbackRate = 0
    }

    // MARK: Chargement

    /// Nouveau son (ou platine vidée si `duration` vaut 0) : état initial SF-03. Le moteur passe à
    /// STOP (le plateau freine), le disque est immobile, le doigt est annulé.
    mutating func reset(duration: Double) {
        durationSeconds = duration.isFinite ? max(0, duration) : 0
        positionSeconds = 0
        playbackRate = 0
        discAngle = 0
        discVelocity = 0
        discMode = .coasting
        coastDeceleration = 0
        gripOffset = 0
        follower.reset(angle: 0, velocity: 0)
        appliedHoldTimeConstant = holdTimeConstant
        isPinnedAtBound = false
        pendingJumpOrigin = nil
        cueSeconds = nil
        motorOn = false
        finger.cancel()
    }

    // MARK: Geste

    mutating func touchBegan(angle: Double, time: Double) {
        // RM-60: a second finger is ignored. A contact that starts while the previous release is
        // still being replayed resumes the gesture instead of being lost (story 1.2).
        guard !isHeld || finger.isReleasing else { return }
        finger.begin(angle: angle, time: time)
    }

    mutating func touchMoved(angle: Double, time: Double, predicted: Bool) {
        // D-16, calibrated in story 1.2: predicted touches are ignored unless lever 3 of #91 is on
        // (`ReplayLatencyOptions.predictedTouches`, off by default).
        guard !predicted else {
            finger.appendPredicted(angle: angle, time: time)
            return
        }
        finger.append(angle: angle, time: time)
    }

    mutating func touchEnded(time: Double) {
        finger.end(time: time)
    }

    // MARK: CUE et sauts

    mutating func setCue() {
        cueSeconds = positionSeconds
    }

    mutating func recallCue() {
        jump(to: cueSeconds ?? 0)
    }

    /// Needle drop : ignoré disque tenu (SF-71).
    mutating func seek(to seconds: Double) {
        guard !isHeld else { return }
        jump(to: seconds)
    }

    /// Fil audio uniquement. Rend et efface l'origine du saut en attente (une fois par bloc, avant
    /// `process`).
    mutating func takeJumpOrigin() -> Double? {
        defer { pendingJumpOrigin = nil }
        return pendingJumpOrigin
    }

    private mutating func jump(to seconds: Double) {
        guard seconds.isFinite else { return }
        // Several jumps between two blocks: the sound to fade out is the one before the first jump.
        if pendingJumpOrigin == nil { pendingJumpOrigin = positionSeconds }
        positionSeconds = seconds.clamped(to: -TurntableConstants.leadInSeconds...max(0, durationSeconds), fallback: 0)
        isPinnedAtBound = false
        realignDisc()
    }

    /// IC-09 : ramène `discAngle` à `2π × position / 1,8 (mod 2π)` par la plus petite correction
    /// (au plus ±π), après un saut de position ou à la sortie d'une butée. Disque tenu, la même
    /// correction est reportée sur le filtre et sur `gripOffset` : l'écart de suivi, la vitesse et
    /// la position audio ne changent pas (aucun saut sous le doigt ni dans le son, D-10).
    mutating func realignDisc() {
        let twoPi = 2 * Double.pi
        let expected = twoPi * positionSeconds / TurntableConstants.secondsPerRevolution
        var correction = (expected - discAngle).truncatingRemainder(dividingBy: twoPi)
        if correction > Double.pi { correction -= twoPi }
        if correction <= -Double.pi { correction += twoPi }
        discAngle += correction
        if discMode == .held {
            follower.shift(by: correction)
            gripOffset += correction
        }
    }

    // MARK: Rendu

    /// Fil audio uniquement. Avance de `frameCount` échantillons et écrit, pour chacun, la position
    /// de la tête (s) et la vitesse de lecture signée, après intégration de l'échantillon.
    mutating func process(frameCount: Int, positions: UnsafeMutablePointer<Double>, rates: UnsafeMutablePointer<Double>) {
        finger.prepareBlock()
        guard frameCount > 0 else { return }
        defer { finger.advanceClock(frameCount: frameCount) } // the replay clock runs between gestures too

        // Per-block coefficients: settings only change between blocks.
        let dt = 1 / sampleRate
        let nominal = nominalPlatterVelocity
        let platterTarget = motorOn ? nominal : 0
        let accelerationStep = nominal / motorTimings.startDuration * dt
        let brakeStep = nominal / motorTimings.brakeDuration * dt
        let catchUpTimeConstant = motorTimings.slipmatCatchUp / 3
        let catchUpGain = catchUpTimeConstant > 0 ? -expm1(-dt / catchUpTimeConstant) : 1
        let targetHoldTimeConstant = holdTimeConstant
        let holdSlewStep = Self.holdTimeConstantSlewRate * dt
        var holdCoefficients = CriticallyDampedFollower.Coefficients(timeConstant: appliedHoldTimeConstant, dt: dt)
        var coastStep = coastDeceleration * dt
        let referenceVelocity = TurntableConstants.referenceAngularVelocity
        let maximumRate = TurntableConstants.maximumPlaybackRate
        let maximumVelocity = maximumRate * referenceVelocity
        let secondsPerRadian = TurntableConstants.secondsPerRevolution / (2 * Double.pi)
        let lowerBound = -TurntableConstants.leadInSeconds
        let upperBound = max(0, durationSeconds)

        for index in 0..<frameCount {
            // 1. Platter: linear ramps toward the motor target (RM-53: independent of the disc).
            let previousPlatterVelocity = platterVelocity
            if platterVelocity < platterTarget {
                platterVelocity = min(platterTarget, platterVelocity + accelerationStep)
            } else if platterVelocity > platterTarget {
                platterVelocity = max(platterTarget, platterVelocity - brakeStep)
            }
            platterAngle += 0.5 * (previousPlatterVelocity + platterVelocity) * dt

            // 2. Disc.
            let previousDiscAngle = discAngle
            if finger.isActive {
                let target = finger.nextTarget()
                if discMode != .held {
                    grab(fingerAngle: target)
                    if appliedHoldTimeConstant != targetHoldTimeConstant {
                        appliedHoldTimeConstant = targetHoldTimeConstant
                        holdCoefficients = CriticallyDampedFollower.Coefficients(timeConstant: appliedHoldTimeConstant, dt: dt)
                    }
                } else if appliedHoldTimeConstant != targetHoldTimeConstant {
                    // Resistance changed while held: slew τ (no catch-up burst, #54).
                    let gap = targetHoldTimeConstant - appliedHoldTimeConstant
                    appliedHoldTimeConstant = abs(gap) <= holdSlewStep
                        ? targetHoldTimeConstant
                        : appliedHoldTimeConstant + (gap > 0 ? holdSlewStep : -holdSlewStep)
                    holdCoefficients = CriticallyDampedFollower.Coefficients(timeConstant: appliedHoldTimeConstant, dt: dt)
                }
                follower.step(target: target + gripOffset, coefficients: holdCoefficients)
                follower.limitVelocity(to: maximumVelocity, previousAngle: previousDiscAngle, dt: dt)
                discAngle = follower.angle
                discVelocity = follower.velocity
                if !finger.isActive {
                    release()
                    coastStep = coastDeceleration * dt
                }
            } else {
                if discMode == .held {
                    // Gesture cancelled outside `reset` (defensive): release where the disc is.
                    release()
                    coastStep = coastDeceleration * dt
                }
                let previousDiscVelocity = discVelocity
                if discMode == .coupled {
                    let gap = platterVelocity - discVelocity
                    discVelocity = abs(gap) < 1e-12 ? platterVelocity : discVelocity + catchUpGain * gap
                } else {
                    let magnitude = abs(discVelocity) - coastStep
                    discVelocity = magnitude > 0.5 * coastStep ? (discVelocity > 0 ? magnitude : -magnitude) : 0
                }
                discAngle += 0.5 * (previousDiscVelocity + discVelocity) * dt
            }

            // 3. Head: follows the disc, pinned at the lead-in and end stops (RM-55).
            let next = positionSeconds + (discAngle - previousDiscAngle) * secondsPerRadian
            if next > upperBound {
                positionSeconds = upperBound
                isPinnedAtBound = true
            } else if next < lowerBound {
                positionSeconds = lowerBound
                isPinnedAtBound = true
            } else {
                let leavesBound = isPinnedAtBound && next != positionSeconds
                positionSeconds = next
                if leavesBound {
                    isPinnedAtBound = false
                    realignDisc()
                }
            }

            positions[index] = positionSeconds
            rates[index] = min(maximumRate, max(-maximumRate, discVelocity / referenceVelocity))
        }
        playbackRate = rates[frameCount - 1]
    }

    /// Saisie : le filtre part de l'angle et de la vitesse courants du disque (SF-06, ADR-08).
    private mutating func grab(fingerAngle: Double) {
        follower.reset(angle: discAngle, velocity: discVelocity)
        gripOffset = discAngle - fingerAngle
        discMode = .held
    }

    /// Relâchement : feutrine si le moteur tourne, roue libre sinon (SF-10, RM-07).
    private mutating func release() {
        if motorOn {
            discMode = .coupled
            coastDeceleration = 0
        } else {
            discMode = .coasting
            coastDeceleration = abs(discVelocity) / TurntableConstants.freeSpinStopDuration
        }
    }
}
