import Foundation

/// Reconstruction, à la fréquence audio, de la trajectoire continue du doigt à partir des
/// événements tactiles horodatés (spec 5.1 point 4, SF-77, SF-78 ; architecture ADR-07).
///
/// Les touches arrivent par lots, une fois par image (60 à 120 Hz), avec des horodatages
/// échantillonnés à 120 ou 240 Hz, puis ne sont vues par le fil audio qu'au début d'un tampon.
/// Appliquer chaque angle dès réception produirait une vitesse « en escalier » audible.
///
/// Principe : **rejeu horodaté à retard adaptatif** (tampon de gigue). La tête de rejeu `playhead`
/// avance sur l'horloge de l'appelant au rythme de l'horloge audio, en retard sur le dernier
/// événement connu ; la cible est interpolée linéairement entre les deux événements qui encadrent
/// la tête.
/// - **Marge** : écart entre le dernier événement connu et la tête. Juste avant chaque nouveau lot,
///   la marge est minimale. La cadence de rejeu est régulée (±10 % au plus, en pratique ±2 %) pour
///   que la plus petite marge des 16 derniers lots vaille `targetMargin` : le retard converge vers
///   le plus petit retard sans famine, quelle que soit la cadence d'affichage.
/// - **Famine** (la tête rattrape le dernier événement) : la tête se fige (vitesse nulle, jamais de
///   saut ni de dépassement) jusqu'au lot suivant, ce qui rallonge aussitôt le retard.
/// - Le retard appris (`delay`) sert de retard initial au geste suivant.
/// - Le relâchement (`end`) est lui aussi rejoué : le disque n'est relâché qu'après le dernier
///   mouvement, avec le même retard. Un `begin` reçu pendant ce rejeu (doigt reposé moins d'un
///   retard après le relâchement) prolonge le geste au lieu d'être perdu (story 1.2) : le rejeu va
///   jusqu'au bout, le disque reste tenu entre les deux contacts, puis suit le nouveau doigt depuis
///   le point de relâchement, sans saut.
/// - **Touches prédites** (D-16, story 1.2) : elles ne servent qu'à combler une famine, entre deux
///   lots. Pendant une famine, la tête peut dépasser le dernier événement réel, au plus d'un
///   intervalle de livraison et jusqu'à la touche prédite, à la vitesse du dernier segment réel
///   (jamais plus vite) ; seulement si la prédiction va dans le même sens et si le doigt ne ralentit
///   pas, pour ne jamais dépasser un point d'inversion (SF-77). Quand les touches réelles arrivent,
///   l'écart avec l'extrapolation est résorbé en douceur (constante de 4 ms). Le retard visé ne
///   change pas : une marge négative allonge le retard comme une famine.
///
/// Latence ajoutée = `delay` : ≈ 13 ms avec un affichage à 120 Hz, ≈ 21 ms à 60 Hz
/// (architecture §6.4). Fil audio uniquement, aucune allocation.
struct FingerTrajectory {
    struct Configuration: Equatable, Sendable {
        /// Retard du tout premier geste, avant apprentissage.
        var initialDelay: Double = 0.014
        var minimumDelay: Double = 0.004
        var maximumDelay: Double = 0.040
        /// Marge minimale visée juste avant un lot.
        var targetMargin: Double = 0.0015
        /// Gain de la régulation de cadence, en 1/s d'écart de marge.
        var rateGain: Double = 2.0
        var maximumRateDeviation: Double = 0.1
        /// Lissage exponentiel du retard appris (0…1, par lot).
        var delaySmoothing: Double = 0.1
        /// Comblement des famines par les touches prédites (D-16).
        var usesPredictedTouches = true
        /// Ralentissement relatif, d'un segment réel au suivant, au-delà duquel une prédiction est
        /// refusée (approche d'une inversion).
        var decelerationTolerance: Double = 0.05
        /// Constante de temps de la résorption de l'écart quand le réel remplace l'extrapolation.
        var correctionTimeConstant: Double = 0.004
    }

    private static let capacity = 32
    private static let indexMask = 31
    private static let historyCount = 16

    let configuration: Configuration
    private var samplePeriod: Double

    // Known events, from the one just before the playhead to the newest.
    private var times = SIMD32<Double>(repeating: 0)
    private var angles = SIMD32<Double>(repeating: 0)
    private var oldest = 0
    private var count = 0

    // Smallest margin reached before each of the last 16 deliveries.
    private var marginHistory = SIMD16<Double>(repeating: 0)
    private var historyIndex = 0
    private var marginSinceDelivery = Double.infinity

    /// Position de rejeu, sur l'horloge de l'appelant.
    private(set) var playhead: Double = 0
    /// Retard appris entre le dernier événement reçu et la tête de rejeu (latence ajoutée).
    private(set) var delay: Double
    private var rate: Double = 1
    private var hasFreshEvents = false
    private var isStarving = false
    private var endTime: Double?

    /// Dernière cible produite (angle cumulé du doigt).
    private(set) var output: Double = 0
    /// Un geste est en cours de rejeu (le disque est tenu).
    private(set) var isActive = false
    /// Nombre de famines (tête figée) depuis la création (diagnostic, tests).
    private(set) var starvationCount = 0
    /// Nombre de famines comblées par une touche prédite (diagnostic, tests).
    private(set) var extrapolationCount = 0

    // Predicted touches (D-16): famine filling past the newest real event.
    private var lastRealVelocity = 0.0
    private var previousRealVelocity = 0.0
    private var lastDeliveryTime = -Double.infinity
    /// Span between the newest events of the last two deliveries (≈ one delivery interval).
    private var deliverySpan = 0.0
    private var fillVelocity = 0.0
    /// The playhead may run up to here; equals the newest real time when no fill is allowed.
    private var fillLimit = 0.0
    private var isExtrapolating = false
    private var needsRebase = false
    private var correction = 0.0
    private var correctionDecay = 0.0
    /// Shift applied to the angles of a gesture resumed during the previous release replay.
    private var angleOffset = 0.0

    init(sampleRate: Double, configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.samplePeriod = 1 / sampleRate
        self.delay = configuration.initialDelay
        updateCorrectionDecay()
    }

    mutating func setSampleRate(_ sampleRate: Double) {
        guard sampleRate.isFinite, sampleRate > 0 else { return }
        samplePeriod = 1 / sampleRate
        updateCorrectionDecay()
    }

    private mutating func updateCorrectionDecay() {
        let tau = configuration.correctionTimeConstant
        correctionDecay = tau > 0 ? exp(-samplePeriod / tau) : 0
    }

    /// Le geste est fini et son relâchement est en cours de rejeu.
    var isReleasing: Bool { isActive && endTime != nil }

    private var newestTime: Double { times[(oldest + count - 1) & Self.indexMask] }
    private var newestAngle: Double { angles[(oldest + count - 1) & Self.indexMask] }

    /// Début d'un geste. Pendant le rejeu d'un relâchement, le nouveau geste prolonge l'ancien ;
    /// pendant un geste en cours, il le remplace (`DeckPhysics` ignore alors un second doigt, RM-60).
    mutating func begin(angle: Double, time: Double) {
        guard angle.isFinite, time.isFinite else { return }
        if isReleasing {
            resume(angle: angle, time: time)
            return
        }
        angleOffset = 0
        lastRealVelocity = 0
        previousRealVelocity = 0
        lastDeliveryTime = time
        deliverySpan = 0
        fillVelocity = 0
        fillLimit = time
        isExtrapolating = false
        needsRebase = false
        correction = 0
        oldest = 0
        count = 1
        times[0] = time
        angles[0] = angle
        playhead = time - delay
        rate = 1
        marginHistory = SIMD16(repeating: configuration.targetMargin)
        historyIndex = 0
        marginSinceDelivery = .infinity
        hasFreshEvents = false
        isStarving = false
        endTime = nil
        output = angle
        isActive = true
    }

    /// Nouvel événement. Les temps non strictement croissants et les valeurs non finies sont ignorés.
    mutating func append(angle: Double, time: Double) {
        guard isActive, endTime == nil, angle.isFinite, time.isFinite, time > newestTime else { return }
        let shifted = angle + angleOffset
        previousRealVelocity = lastRealVelocity
        lastRealVelocity = (shifted - newestAngle) / (time - newestTime)
        push(time: time, angle: shifted)
        hasFreshEvents = true
        dropPrediction()
    }

    /// Touche prédite (D-16) : autorise, en cas de famine, un comblement jusqu'à elle. Les temps qui
    /// ne dépassent pas le dernier événement réel et les valeurs non finies sont ignorés.
    mutating func appendPredicted(angle: Double, time: Double) {
        guard isActive, endTime == nil, configuration.usesPredictedTouches, angle.isFinite, time.isFinite,
              time > newestTime else { return }
        let predictedVelocity = (angle + angleOffset - newestAngle) / (time - newestTime)
        let decelerating = abs(lastRealVelocity)
            < abs(previousRealVelocity) * (1 - configuration.decelerationTolerance)
        dropPrediction()
        guard deliverySpan > 0, predictedVelocity * lastRealVelocity > 0, !decelerating else { return }
        let speed = min(abs(predictedVelocity), abs(lastRealVelocity))
        fillVelocity = lastRealVelocity > 0 ? speed : -speed
        fillLimit = min(time, newestTime + deliverySpan)
    }

    /// Fin du geste : le relâchement prendra effet quand le rejeu atteindra `time`.
    mutating func end(time: Double) {
        guard isActive, endTime == nil else { return }
        let releaseTime = time.isFinite ? max(time, newestTime) : newestTime
        if releaseTime > newestTime {
            push(time: releaseTime, angle: newestAngle)
        }
        endTime = releaseTime
        lastRealVelocity = 0
        dropPrediction()
    }

    /// Reprise pendant le rejeu du relâchement : le nouveau doigt part du point de relâchement.
    private mutating func resume(angle: Double, time: Double) {
        endTime = nil
        angleOffset = newestAngle - angle
        lastRealVelocity = 0
        previousRealVelocity = 0
        if time > newestTime {
            push(time: time, angle: newestAngle)
            hasFreshEvents = true
        }
        dropPrediction()
    }

    /// Les touches prédites d'un lot sont remplacées par les touches réelles du lot suivant.
    private mutating func dropPrediction() {
        fillVelocity = 0
        fillLimit = newestTime
        if isExtrapolating { needsRebase = true }
    }

    /// Arrêt immédiat, sans rejouer la fin (chargement d'un autre son, remise à zéro).
    mutating func cancel() {
        isActive = false
        endTime = nil
        count = 0
    }

    /// À appeler une fois par bloc, après l'ajout des événements du bloc.
    mutating func prepareBlock() {
        guard isActive, hasFreshEvents else { return }
        hasFreshEvents = false
        if marginSinceDelivery.isFinite {
            marginHistory[historyIndex] = marginSinceDelivery
            historyIndex = (historyIndex + 1) % Self.historyCount
        }
        marginSinceDelivery = .infinity
        let marginError = marginHistory.min() - configuration.targetMargin
        let deviation = configuration.rateGain * marginError
        rate = 1 + min(configuration.maximumRateDeviation, max(-configuration.maximumRateDeviation, deviation))
        let lag = newestTime - playhead
        let learned = delay + configuration.delaySmoothing * (lag - delay)
        delay = min(configuration.maximumDelay, max(configuration.minimumDelay, learned))
        if lastDeliveryTime.isFinite, newestTime > lastDeliveryTime { deliverySpan = newestTime - lastDeliveryTime }
        lastDeliveryTime = newestTime
    }

    /// Avance d'un échantillon audio et renvoie la cible (angle cumulé du doigt).
    mutating func nextTarget() -> Double {
        guard isActive else { return output }
        if needsRebase {
            // New data replaced the extrapolation under the playhead: keep the output continuous.
            needsRebase = false
            correction = output - base(at: playhead)
        }
        var next = playhead + rate * samplePeriod
        let limit = newestTime
        let reach = max(limit, fillLimit)
        if next >= reach {
            if !isStarving, endTime == nil { starvationCount += 1 }
            isStarving = true
            next = max(reach, playhead)   // a revoked fill freezes the playhead, never moves it back
        } else {
            isStarving = false
        }
        let extrapolating = next > limit
        if extrapolating, !isExtrapolating { extrapolationCount += 1 }
        isExtrapolating = extrapolating
        playhead = next
        marginSinceDelivery = min(marginSinceDelivery, limit - next)

        // Drop events entirely behind the playhead, keeping the one just before it.
        while count >= 2, times[(oldest + 1) & Self.indexMask] <= playhead {
            oldest = (oldest + 1) & Self.indexMask
            count -= 1
        }
        output = base(at: playhead) + correction
        if correction != 0 {
            correction *= correctionDecay
            if abs(correction) < 1e-12 { correction = 0 }
        }
        if let endTime, playhead >= endTime {
            isActive = false
            self.endTime = nil
        }
        return output
    }

    /// Trajectoire réelle interpolée à `time`, prolongée au-delà du dernier événement réel par le
    /// comblement autorisé (nul sans touche prédite). Au plus 32 itérations.
    private func base(at time: Double) -> Double {
        var index = oldest
        var remaining = count
        while remaining >= 2, times[(index + 1) & Self.indexMask] <= time {
            index = (index + 1) & Self.indexMask
            remaining -= 1
        }
        let t0 = times[index]
        let a0 = angles[index]
        guard time > t0 else { return a0 }
        if remaining >= 2 {
            let i1 = (index + 1) & Self.indexMask
            return a0 + (angles[i1] - a0) * (time - t0) / (times[i1] - t0)
        }
        return a0 + fillVelocity * (min(time, fillLimit) - t0)
    }

    private mutating func push(time: Double, angle: Double) {
        if count == Self.capacity {
            // Overflow (should not happen: 32 events ≫ delay × touch rate). Drop the oldest and
            // keep the playhead inside the known span.
            oldest = (oldest + 1) & Self.indexMask
            count -= 1
            playhead = max(playhead, times[oldest])
        }
        let index = (oldest + count) & Self.indexMask
        times[index] = time
        angles[index] = angle
        count += 1
    }
}
