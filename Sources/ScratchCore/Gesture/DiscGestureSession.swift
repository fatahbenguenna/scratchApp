/// Échantillon de contact dans le repère de la vue du disque (points, axe y vers le bas).
public struct ContactSample: Equatable, Sendable {
    public var x: Double
    public var y: Double
    /// Horodatage sur l'horloge monotone de l'appelant (`UITouch.timestamp`, `NSEvent.timestamp`).
    public var time: Double
    /// Touche prédite par le système (`UIEvent.predictedTouches`, SF-78).
    public var isPredicted: Bool

    public init(x: Double, y: Double, time: Double, isPredicted: Bool = false) {
        self.x = x
        self.y = y
        self.time = time
        self.isPredicted = isPredicted
    }
}

/// Session de geste d'un disque : contact propriétaire, angle déplié, commandes moteur
/// (RM-60, RM-61, SF-19, SF-78 ; UX §6.1). Logique pure, fil principal ; une session par disque.
///
/// - Seul un contact **commencé** dans la zone de saisie devient propriétaire ; tout autre contact
///   commencé pendant la saisie est ignoré jusqu'au relâchement du propriétaire (RM-60).
/// - Chaque échantillon réel, regroupé (`coalescedTouches`), donne un `touchMoved(predicted: false)`
///   dans l'ordre ; chaque échantillon prédit donne un `touchMoved(predicted: true)` calculé sans
///   modifier le dépliement. Un échantillon réel dont l'horodatage ne dépasse pas le précédent est
///   déplié mais pas envoyé (le moteur l'ignorerait).
/// - La fin et l'annulation par le système donnent le même `touchEnded` (RM-60).
///
/// Les tableaux renvoyés sont acceptables ici : ce code ne s'exécute jamais sur le fil audio.
/// L'appelant envoie chaque commande au moteur dans le cycle d'événements qui la reçoit (NFR1).
public struct DiscGestureSession: Sendable {
    public let deck: DeckID
    /// Identifiant du contact propriétaire, fourni par l'appelant (jamais une référence UIKit).
    public private(set) var ownerID: Int?
    public private(set) var tracker: GestureAngleTracker
    private var lastTime = -Double.infinity

    /// - Parameters:
    ///   - vinylRadius: rayon du vinyle R (zone morte : 12 % de R).
    ///   - grabRadius: rayon de saisie, `min(R + 6, P / 2)` (UX §5.1).
    public init(deck: DeckID, centerX: Double, centerY: Double, vinylRadius: Double, grabRadius: Double) {
        self.deck = deck
        tracker = GestureAngleTracker(centerX: centerX, centerY: centerY, radius: vinylRadius, grabRadius: grabRadius)
    }

    /// Le disque est tenu par un contact.
    public var isHolding: Bool { ownerID != nil }

    /// Redimensionnement ou rotation pendant un geste : aucun saut d'angle (6.14).
    public mutating func updateGeometry(centerX: Double, centerY: Double, vinylRadius: Double, grabRadius: Double) {
        tracker.updateGeometry(centerX: centerX, centerY: centerY, radius: vinylRadius, grabRadius: grabRadius)
    }

    /// Début d'un contact : `touchBegan` s'il devient propriétaire, sinon `nil`.
    public mutating func began(contact id: Int, at sample: ContactSample) -> EngineCommand? {
        guard ownerID == nil, !sample.isPredicted, sample.time.isFinite,
              tracker.begin(x: sample.x, y: sample.y) else { return nil }
        ownerID = id
        lastTime = sample.time
        return .touchBegan(deck, angle: tracker.angle, time: sample.time)
    }

    /// Échantillons d'un contact, regroupés puis prédits, dans l'ordre. Ignorés si `id` n'est pas le
    /// propriétaire.
    public mutating func moved(contact id: Int, samples: [ContactSample]) -> [EngineCommand] {
        guard id == ownerID else { return [] }
        var commands: [EngineCommand] = []
        commands.reserveCapacity(samples.count)
        for sample in samples where sample.time.isFinite {
            if sample.isPredicted {
                guard sample.time > lastTime else { continue }
                let angle = tracker.predictedAngle(x: sample.x, y: sample.y)
                commands.append(.touchMoved(deck, angle: angle, time: sample.time, predicted: true))
            } else {
                let angle = tracker.move(x: sample.x, y: sample.y)
                guard sample.time > lastTime else { continue }
                lastTime = sample.time
                commands.append(.touchMoved(deck, angle: angle, time: sample.time, predicted: false))
            }
        }
        return commands
    }

    /// Fin ou annulation du contact : `touchEnded` si c'est le propriétaire (RM-60).
    public mutating func ended(contact id: Int, time: Double) -> EngineCommand? {
        guard id == ownerID else { return nil }
        return release(time: time)
    }

    /// Annule le geste en cours, quel que soit le contact (rotation, changement de disposition ou
    /// de platine affichée : 4.3, 4.4).
    public mutating func cancelAll(time: Double) -> EngineCommand? {
        guard ownerID != nil else { return nil }
        return release(time: time)
    }

    private mutating func release(time: Double) -> EngineCommand {
        ownerID = nil
        tracker.end()
        let releaseTime = time.isFinite ? max(time, lastTime) : lastTime
        lastTime = -Double.infinity
        return .touchEnded(deck, time: releaseTime)
    }
}
