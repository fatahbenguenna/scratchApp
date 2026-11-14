/// Physique d'une platine : moteur, plateau, feutrine, disque tenu, tête de lecture, CUE et repère
/// (spec 5.1 ; architecture §6.3). Fil audio uniquement, aucune allocation.
///
/// **Squelette (story 1.1, James).** Les réglages et les états discrets sont tenus et bornés, les
/// sauts de position recalent le disque et le repère (IC-09), mais rien ne tourne : `process` renvoie
/// une position constante et une vitesse nulle. À implémenter (PRD 1.1, 1.3 critère 1, 1.5) :
/// 1. Plateau : `ωp` → `ωt = 2π × RPM/60 × (1 + pitch)` moteur actif, → 0 sinon, pentes
///    `ωt / startDuration` et `ωt / brakeDuration` (SF-04, SF-05, 6.2 : START pendant le freinage
///    repart de la vitesse courante).
/// 2. Disque libre : rejoint `ωp` au 1er ordre, τ = slipmatCatchUp / 3 (95 % en T, arbitrage IC-03) ;
///    T = 0 → alignement immédiat. Moteur arrêté : décélération linéaire jusqu'à 0 en
///    `freeSpinStopDuration` au plus (SF-10).
/// 3. Disque tenu : `θd` suit `θf + gripOffset` par un filtre du 2ᵉ ordre à amortissement critique,
///    τ de 2 ms (résistance 0) à 35 ms (résistance 1) ; `θf` vient de `FingerTrajectory`. Le
///    changement de résistance ne crée aucun saut (SF-23). `gripOffset` est fixé à la prise.
/// 4. Tête : `p += ωd / (2π) × 1,8 s × dt` à chaque échantillon, bornée à [−2 s ; durée] ; en butée
///    le disque continue de tourner et un mouvement inverse revient immédiatement dans le son (RM-55) ;
///    à la sortie de butée, `realignDisc()` (IC-09).
/// 5. Vitesse de lecture `ωd / ωref` bornée à ±16 (SF-77).
/// 6. Recalage disque tenu : décaler `gripOffset` de la même correction que `discAngle`, pour que le
///    disque reste sous le doigt sans saut de son (UX §5.1, Q13) ; CUE disque tenu ré-ancre le geste.
struct DeckPhysics {
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

    private var finger: FingerTrajectory

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        self.finger = FingerTrajectory(sampleRate: sampleRate)
    }

    var isHeld: Bool { finger.isActive }

    /// Angle d'écran du repère (`DeckSnapshot.stickerAngle`) : calculé, jamais cumulé.
    var stickerAngle: Double {
        discAngle - 2 * Double.pi * (cueSeconds ?? 0) / TurntableConstants.secondsPerRevolution
    }
    var isAtEnd: Bool { durationSeconds > 0 && positionSeconds >= durationSeconds }
    var isInLeadIn: Bool { positionSeconds < 0 }

    // MARK: Réglages

    mutating func setSampleRate(_ rate: Double) {
        guard rate.isFinite, rate > 0 else { return }
        sampleRate = rate
        finger.setSampleRate(rate)
    }

    mutating func setMotorTimings(_ timings: MotorTimings) { motorTimings = timings.clamped() }
    mutating func setMotor(_ on: Bool) { motorOn = on }
    mutating func setSpeed(_ newSpeed: TurntableSpeed) { speed = newSpeed }

    mutating func setPitch(_ value: Double) {
        guard value.isFinite else { return }
        pitch = value.clamped(to: TurntableConstants.pitchRange, fallback: 0)
    }

    mutating func setResistance(_ value: Double) {
        guard value.isFinite else { return }
        resistance = value.clamped(to: 0...1, fallback: TurntableConstants.defaultResistance)
    }

    /// RM-56 : STOP immédiat, sans rampe (le disque tenu reste tenu).
    mutating func stopMotorImmediately() {
        motorOn = false
        playbackRate = isHeld ? playbackRate : 0
    }

    // MARK: Chargement

    /// Nouveau son (ou platine vidée si `duration` vaut 0) : état initial SF-03.
    mutating func reset(duration: Double) {
        durationSeconds = max(0, duration)
        positionSeconds = 0
        playbackRate = 0
        discAngle = 0
        cueSeconds = nil
        motorOn = false
        finger.cancel()
    }

    // MARK: Geste

    mutating func touchBegan(angle: Double, time: Double) {
        guard !isHeld else { return } // RM-60 : un second doigt est ignoré.
        finger.begin(angle: angle, time: time)
    }

    mutating func touchMoved(angle: Double, time: Double, predicted: Bool) {
        // Predicted touches are accepted by the contract; their use is calibrated in story 1.2.
        guard !predicted else { return }
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

    private mutating func jump(to seconds: Double) {
        guard seconds.isFinite else { return }
        positionSeconds = seconds.clamped(to: -TurntableConstants.leadInSeconds...max(0, durationSeconds), fallback: 0)
        realignDisc()
    }

    /// IC-09 : ramène `discAngle` à `2π × position / 1,8 (mod 2π)` par la plus petite correction
    /// (au plus ±π), après un saut de position ou à la sortie d'une butée.
    mutating func realignDisc() {
        let twoPi = 2 * Double.pi
        let expected = twoPi * positionSeconds / TurntableConstants.secondsPerRevolution
        var correction = (expected - discAngle).truncatingRemainder(dividingBy: twoPi)
        if correction > Double.pi { correction -= twoPi }
        if correction <= -Double.pi { correction += twoPi }
        discAngle += correction
    }

    // MARK: Rendu

    /// Avance de `frameCount` échantillons et écrit, pour chacun, la position de la tête (s) et la
    /// vitesse de lecture signée.
    mutating func process(frameCount: Int, positions: UnsafeMutablePointer<Double>, rates: UnsafeMutablePointer<Double>) {
        finger.prepareBlock()
        for index in 0..<frameCount {
            if finger.isActive { _ = finger.nextTarget() }
            positions[index] = positionSeconds
            rates[index] = 0
        }
    }
}
