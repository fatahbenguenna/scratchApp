import Foundation

/// Défilement trackpad et molette → rotation du disque (SF-79, RM-60, D-24 ; UX §6.3). Logique pure,
/// fil principal, une instance par disque.
///
/// - Un défilement **commencé** (phase `began`) au-dessus de la zone de saisie saisit le disque par
///   un doigt virtuel ; commencé ailleurs, il ne le saisit pas, même s'il passe dessus (RM-60).
/// - Chaque delta tourne le disque de `Δθ = (rx·dy − ry·dx) / (‖r‖ × max(‖r‖, 0,5 R))`, sens horaire
///   positif, `r` = centre → pointeur, pris en haut du disque à 0,5 R dans la zone centrale. Les
///   deltas sont des déplacements de doigts dans le repère de la vue (y vers le bas), déjà corrigés
///   du « défilement naturel » par la vue (4.3).
/// - L'inertie (`momentum`) est ignorée : elle ne tourne pas le disque et ne prolonge pas la saisie.
/// - Molette sans phases (`none`) : 15° par cran, vers le bas ou la droite = sens horaire.
/// - Relâchement **80 ms après le dernier événement**, phase `ended` comprise : `poll(now:)`, appelé
///   par une horloge de l'appelant, émet `touchEnded` horodaté `dernier événement + 0,080 s`.
public struct ScrollGestureMapper: Sendable {
    /// Phase d'un événement de défilement (`NSEvent.phase`, ou `none` pour une molette classique).
    public enum Phase: Sendable {
        case began, changed, ended, momentum, none
    }

    /// Angle d'un cran de molette sans phases.
    public static let wheelNotchAngle = 15 * Double.pi / 180
    /// Durée attribuée au premier cran d'une saisie à la molette : `touchBegan` est daté d'autant
    /// avant le cran pour que la rotation ne soit pas instantanée.
    public static let wheelNotchDuration = 1.0 / 60

    public let deck: DeckID
    public let releaseDelay: Double
    public private(set) var centerX: Double
    public private(set) var centerY: Double
    public private(set) var vinylRadius: Double
    public private(set) var grabRadius: Double

    /// Le disque est tenu par le défilement.
    public private(set) var isHolding = false
    private var angle = 0.0
    private var lastEventTime = 0.0
    /// Le défilement en cours a commencé hors du disque : ses événements sont ignorés.
    private var isRejected = false

    public init(deck: DeckID, centerX: Double, centerY: Double, vinylRadius: Double, grabRadius: Double,
                releaseDelay: Double = TurntableConstants.trackpadReleaseDelay) {
        self.deck = deck
        self.centerX = centerX
        self.centerY = centerY
        self.vinylRadius = vinylRadius
        self.grabRadius = grabRadius
        self.releaseDelay = releaseDelay
    }

    /// Échéance du relâchement : dernier événement + 0,080 s, ou `nil` si le disque n'est pas tenu.
    public var releaseDeadline: Double? { isHolding ? lastEventTime + releaseDelay : nil }

    public mutating func updateGeometry(centerX: Double, centerY: Double, vinylRadius: Double, grabRadius: Double) {
        self.centerX = centerX
        self.centerY = centerY
        self.vinylRadius = vinylRadius
        self.grabRadius = grabRadius
    }

    /// Un événement de défilement au point (`x`, `y`) de la vue. Émet d'abord un relâchement échu.
    public mutating func scroll(x: Double, y: Double, deltaX: Double, deltaY: Double,
                                phase: Phase, time: Double) -> [EngineCommand] {
        guard x.isFinite, y.isFinite, deltaX.isFinite, deltaY.isFinite, time.isFinite else { return [] }
        var commands: [EngineCommand] = []
        if let release = poll(now: time) { commands.append(release) }
        let isOverDisc = hypot(x - centerX, y - centerY) <= grabRadius
        switch phase {
        case .momentum:
            break
        case .began:
            if isOverDisc {
                isRejected = false
                if !isHolding { commands.append(grab(time: time)) }
                lastEventTime = max(lastEventTime, time)
            } else {
                isRejected = true
                if let release = release() { commands.append(release) }
            }
        case .changed, .ended:
            guard isHolding, !isRejected, time > lastEventTime else { break }
            angle += rotation(x: x, y: y, deltaX: deltaX, deltaY: deltaY)
            lastEventTime = time
            commands.append(.touchMoved(deck, angle: angle, time: time, predicted: false))
        case .none:
            isRejected = false
            if !isHolding {
                guard isOverDisc else { break }
                commands.append(grab(time: time - Self.wheelNotchDuration))
            }
            guard time > lastEventTime else { break }
            let delta = deltaY != 0 ? deltaY : deltaX
            guard delta != 0 else { break }
            let notches = max(1, abs(delta).rounded())
            angle += (delta > 0 ? 1 : -1) * notches * Self.wheelNotchAngle
            lastEventTime = time
            commands.append(.touchMoved(deck, angle: angle, time: time, predicted: false))
        }
        return commands
    }

    /// Émet `touchEnded`, horodaté à l'échéance, quand l'horloge de l'appelant l'a atteinte.
    public mutating func poll(now: Double) -> EngineCommand? {
        guard let deadline = releaseDeadline, now + 1e-9 >= deadline else { return nil }
        return release()
    }

    // MARK: Interne

    private mutating func grab(time: Double) -> EngineCommand {
        isHolding = true
        lastEventTime = time
        return .touchBegan(deck, angle: angle, time: time)
    }

    /// Relâche à l'échéance prévue (dernier événement + délai).
    private mutating func release() -> EngineCommand? {
        guard let deadline = releaseDeadline else { return nil }
        isHolding = false
        return .touchEnded(deck, time: deadline)
    }

    /// Rotation produite par un déplacement des doigts `d` au point `r` (formule UX §6.3).
    func rotation(x: Double, y: Double, deltaX: Double, deltaY: Double) -> Double {
        var rx = x - centerX
        var ry = y - centerY
        var length = hypot(rx, ry)
        if length < TurntableConstants.centerDeadZoneRatio * vinylRadius {
            rx = 0
            ry = -0.5 * vinylRadius
            length = 0.5 * vinylRadius
        }
        guard length > 0 else { return 0 }
        return (rx * deltaY - ry * deltaX) / (length * max(length, 0.5 * vinylRadius))
    }
}
