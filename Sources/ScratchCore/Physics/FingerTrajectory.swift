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
///   mouvement, avec le même retard.
///
/// Latence ajoutée = `delay` : ≈ 13 ms avec un affichage à 120 Hz, ≈ 21 ms à 60 Hz
/// (architecture §6.4). Aucune allocation ; à n'utiliser que sur le fil audio.
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
    /// Nombre de famines depuis la création (diagnostic, tests).
    private(set) var starvationCount = 0

    init(sampleRate: Double, configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.samplePeriod = 1 / sampleRate
        self.delay = configuration.initialDelay
    }

    mutating func setSampleRate(_ sampleRate: Double) {
        guard sampleRate.isFinite, sampleRate > 0 else { return }
        samplePeriod = 1 / sampleRate
    }

    private var newestTime: Double { times[(oldest + count - 1) & Self.indexMask] }
    private var newestAngle: Double { angles[(oldest + count - 1) & Self.indexMask] }

    /// Début d'un geste (un `begin` pendant un rejeu en cours le remplace).
    mutating func begin(angle: Double, time: Double) {
        guard angle.isFinite, time.isFinite else { return }
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
        push(time: time, angle: angle)
        hasFreshEvents = true
    }

    /// Fin du geste : le relâchement prendra effet quand le rejeu atteindra `time`.
    mutating func end(time: Double) {
        guard isActive, endTime == nil else { return }
        let releaseTime = time.isFinite ? max(time, newestTime) : newestTime
        if releaseTime > newestTime {
            push(time: releaseTime, angle: newestAngle)
        }
        endTime = releaseTime
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
    }

    /// Avance d'un échantillon audio et renvoie la cible (angle cumulé du doigt).
    mutating func nextTarget() -> Double {
        guard isActive else { return output }
        var next = playhead + rate * samplePeriod
        let limit = newestTime
        if next >= limit {
            if !isStarving, endTime == nil { starvationCount += 1 }
            isStarving = true
            next = limit
        } else {
            isStarving = false
        }
        playhead = next
        marginSinceDelivery = min(marginSinceDelivery, limit - next)

        // Drop events entirely behind the playhead, keeping the one just before it.
        while count >= 2, times[(oldest + 1) & Self.indexMask] <= playhead {
            oldest = (oldest + 1) & Self.indexMask
            count -= 1
        }
        let t0 = times[oldest]
        if count < 2 || playhead <= t0 {
            output = angles[oldest]
        } else {
            let i1 = (oldest + 1) & Self.indexMask
            let a0 = angles[oldest]
            output = a0 + (angles[i1] - a0) * (playhead - t0) / (times[i1] - t0)
        }
        if let endTime, playhead >= endTime {
            isActive = false
            self.endTime = nil
        }
        return output
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
