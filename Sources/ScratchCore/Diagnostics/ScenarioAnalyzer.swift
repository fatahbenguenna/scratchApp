import Foundation

/// Analyse incrémentale d'un `ScratchScenario` : consomme chaque tampon rendu et l'instantané qui le
/// suit, puis produit un `ScenarioReport` (story 1.5 CA 10). Fil de contrôle uniquement.
///
/// Vérifications (seuil de silence −60 dBFS, soit une crête ≤ 0,001) :
/// - `nominalSpeedReached` : vitesse de lecture de A à 1 ± 0,001 entre 1,0 et 1,4 s ;
/// - `silentWhileHeldStill`, `platterSpinsWhileHeld` : tenue immobile, sortie silencieuse, plateau
///   en rotation (au moins 1 rad parcouru) et moteur à START ;
/// - `rateSignFollowsGesture` : vitesse > 0 pendant la poussée, < 0 pendant le retour ;
/// - `noClickAtReversals` : pendant le baby scratch, la plus grande marche entre échantillons d'un
///   tampon où le sens s'inverse ne dépasse pas celle des tampons voisins (un clic s'y détacherait) ;
/// - `babyScratchReturnsToStart` : doigt revenu à son angle de départ, tête revenue à sa position de
///   la fin de la tenue immobile à ±10 ms de son ;
/// - `catchUpWithinSlipmatTime` : après le relâchement (passage de `isHeld` à faux), vitesse ≥ 95 %
///   de la vitesse nominale en 60 ms, à un tampon près ;
/// - `closedChannelSilent` : voie A fermée au crossfader (deux fenêtres) ≤ −60 dBFS ;
/// - `cutInWithin1ms` : à la réouverture (crossfader, puis coupure momentanée), le gain de la voie
///   a rejoint 1 dès la fin du premier tampon, et le niveau efficace entre 1 ms et la fin de ce
///   tampon vaut au moins 30 % de celui des 20 ms suivantes (mesure indépendante du contenu) ;
/// - `peakAtMost0dBFS`, `noNaN` : sur toute la sortie.
public struct ScenarioAnalyzer {
    private let sampleRate: Double
    private let blockFrames: Int
    private typealias Time = ScratchScenario.Time

    private var peak: Double = 0
    private var nonFinite = 0
    private var previousSample: Float = 0
    private var nominalRates = (minimum: Double.infinity, maximum: -Double.infinity)
    private var heldPeak: Double = 0
    private var heldFlags = true
    private var platterStart: Double?
    private var platterEnd: Double?
    private var pushRates = (minimum: Double.infinity, count: 0)
    private var pullRates = (maximum: -Double.infinity, count: 0)
    private var babySteps: [(step: Double, rate: Double)] = []
    private var startPosition: Double?
    private var returnPosition: Double?
    private var releaseTime: Double?
    private var caughtUpTime: Double?
    private var wasHeld = false
    private var closedPeak: Double = 0
    private var referencePeak: Double = 0
    private var cutInRatios: [Double] = []
    private var cutInGains: [Double] = []
    /// Réouverture en cours de mesure : énergie après 1 ms dans le premier tampon, puis énergie des
    /// 20 ms suivantes.
    private var pendingCutIn: (late: Double, lateCount: Int, reference: Double, referenceCount: Int, end: Int64)?

    init(sampleRate: Double, blockFrames: Int) {
        self.sampleRate = sampleRate
        self.blockFrames = blockFrames
    }

    /// Appelé après chaque tampon rendu, avec la sortie et l'instantané qui suit le rendu.
    public mutating func consume(frame: Int64, left: UnsafePointer<Float>, right: UnsafePointer<Float>,
                                 count: Int, snapshot: EngineSnapshot) {
        guard count > 0 else { return }
        let start = Double(frame) / sampleRate
        let end = Double(frame + Int64(count)) / sampleRate
        let deck = snapshot[.a]

        // Whole output: peak, NaN, largest step of this buffer.
        var bufferPeak: Double = 0
        var bufferStep: Double = 0
        var bufferEnergy: Double = 0
        var lateEnergy: Double = 0
        let oneMillisecond = Int((0.001 * sampleRate).rounded())
        for index in 0..<count {
            let l = left[index], r = right[index]
            if !l.isFinite || !r.isFinite { nonFinite += 1; continue }
            let level = Double(max(abs(l), abs(r)))
            bufferPeak = max(bufferPeak, level)
            let energy = Double(l) * Double(l) + Double(r) * Double(r)
            bufferEnergy += energy
            if index >= oneMillisecond { lateEnergy += energy }
            bufferStep = max(bufferStep, Double(abs(l - previousSample)))
            previousSample = l
        }
        peak = max(peak, bufferPeak)

        func within(_ range: ClosedRange<Double>) -> Bool { start >= range.lowerBound && end <= range.upperBound }

        if within(Time.nominal) {
            nominalRates = (min(nominalRates.minimum, deck.playbackRate), max(nominalRates.maximum, deck.playbackRate))
        }
        if within(Time.heldStill) {
            heldPeak = max(heldPeak, bufferPeak)
            heldFlags = heldFlags && deck.isHeld && deck.motorOn
            if platterStart == nil { platterStart = deck.platterAngle }
            platterEnd = deck.platterAngle
            // Finger at rest at angle 0, as after the baby scratch: the reference position.
            startPosition = deck.positionSeconds
        }
        if within(Time.pushCheck) { pushRates = (min(pushRates.minimum, deck.playbackRate), pushRates.count + 1) }
        if within(Time.pullCheck) { pullRates = (max(pullRates.maximum, deck.playbackRate), pullRates.count + 1) }
        if start >= Time.babyBegin, end <= Time.babyEnd + 0.05 { babySteps.append((bufferStep, deck.playbackRate)) }
        if start < Time.returnCheck, end >= Time.returnCheck { returnPosition = deck.positionSeconds }

        if wasHeld, !deck.isHeld, releaseTime == nil, start >= Time.release { releaseTime = end }
        if releaseTime != nil, caughtUpTime == nil, deck.playbackRate >= 0.95 { caughtUpTime = end }
        wasHeld = deck.isHeld

        if within(Time.closedFirst) || within(Time.closedSecond) { closedPeak = max(closedPeak, bufferPeak) }
        if within(Time.reference) { referencePeak = max(referencePeak, bufferPeak) }

        // Re-opening: level after 1 ms in the first buffer versus the next 20 ms.
        if var pending = pendingCutIn {
            pending.reference += bufferEnergy
            pending.referenceCount += count
            if frame + Int64(count) >= pending.end {
                let late = pending.late / Double(max(1, pending.lateCount))
                let reference = pending.reference / Double(max(1, pending.referenceCount))
                cutInRatios.append(reference > 0 ? (late / reference).squareRoot() : 0)
                pendingCutIn = nil
            } else {
                pendingCutIn = pending
            }
        }
        for opening in [Time.openCrossfader, Time.cutOpen] where start <= opening && opening < end {
            cutInGains.append(snapshot.mixer.channelGains.a)
            let referenceEnd = frame + Int64(count) + Int64((0.020 * sampleRate).rounded())
            pendingCutIn = (lateEnergy, max(0, count - oneMillisecond), 0, 0, referenceEnd)
        }
    }

    public func report() -> ScenarioReport {
        let threshold = 0.001
        let platterTravel = (platterEnd ?? 0) - (platterStart ?? 0)
        let catchUp = (caughtUpTime ?? .infinity) - (releaseTime ?? 0)
        let bufferDuration = Double(blockFrames) / sampleRate
        let returnError = abs((returnPosition ?? .infinity) - (startPosition ?? 0))

        var reversalsChecked = 0
        var clickAtReversal = false
        if babySteps.count > 4 {
            for index in 2..<(babySteps.count - 2) {
                let previous = babySteps[index - 1].rate
                guard previous.sign != babySteps[index].rate.sign else { continue }
                reversalsChecked += 1
                let neighbours = [babySteps[index - 2], babySteps[index - 1], babySteps[index + 1], babySteps[index + 2]]
                if babySteps[index].step > (neighbours.map(\.step).max() ?? 0) + 1e-6 { clickAtReversal = true }
            }
        }

        let checks: [String: Bool] = [
            "nominalSpeedReached": nominalRates.minimum >= 0.999 && nominalRates.maximum <= 1.001,
            "silentWhileHeldStill": heldPeak <= threshold,
            "platterSpinsWhileHeld": heldFlags && platterTravel > 1,
            "rateSignFollowsGesture": pushRates.count > 0 && pullRates.count > 0 && pushRates.minimum > 0 && pullRates.maximum < 0,
            "noClickAtReversals": reversalsChecked >= 8 && !clickAtReversal,
            "catchUpWithinSlipmatTime": catchUp <= TurntableConstants.defaultSlipmatCatchUp + bufferDuration + 1e-9,
            "closedChannelSilent": closedPeak <= threshold,
            "cutInWithin1ms": cutInRatios.count == 2 && cutInRatios.allSatisfy { $0 >= 0.3 }
                && cutInGains.count == 2 && cutInGains.allSatisfy { $0 >= 1 - 1e-9 } && referencePeak > threshold,
            "peakAtMost0dBFS": peak <= 1,
            "noNaN": nonFinite == 0,
            "babyScratchReturnsToStart": returnError <= 0.010,
        ]
        func decibels(_ value: Double) -> Double { value > 0 ? 20 * log10(value) : -400 }
        let details: [String: Double] = [
            "nominalRateMinimum": nominalRates.minimum,
            "nominalRateMaximum": nominalRates.maximum,
            "heldPeakDBFS": decibels(heldPeak),
            "platterTravelWhileHeld": platterTravel,
            "pushRateMinimum": pushRates.minimum,
            "pullRateMaximum": pullRates.maximum,
            "reversalsChecked": Double(reversalsChecked),
            "catchUpSeconds": catchUp,
            "closedPeakDBFS": decibels(closedPeak),
            "cutInRatioMinimum": cutInRatios.min() ?? 0,
            "peakDBFS": decibels(peak),
            "nonFiniteSamples": Double(nonFinite),
            "babyReturnErrorSeconds": returnError,
        ]
        return ScenarioReport(checks: checks, details: details)
    }
}
