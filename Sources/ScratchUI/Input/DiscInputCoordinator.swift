import Foundation
import ScratchCore

/// Saisie d'un disque, partagée par les surfaces UIKit et AppKit (story 4.3 ; RM-59 à RM-61, SF-19,
/// SF-78, SF-79 ; UX §6.1 à §6.3). Un coordinateur par platine, porté par `DeckViewModel.discInput`.
///
/// - Contacts (doigt, clic) : `DiscGestureSession` de la 1.2, un seul contact propriétaire,
///   saisie au départ seulement, zone centrale, annulation = relâchement.
/// - Défilement (trackpad, molette) : `ScrollGestureMapper` de la 1.2, relâchement 80 ms après le
///   dernier événement par `ScrollReleaseTimer`.
/// - Chaque commande part vers le moteur par le `DeckViewModel`, dans le cycle d'événements qui la
///   reçoit (NFR1) ; les angles sont ceux du doigt, cumulés (D-48), jamais déduits du disque affiché.
/// - Un disque vide n'est pas saisissable ; un contact et un défilement ne tiennent jamais le même
///   disque en même temps.
/// - La géométrie est relue à chaque événement (redimensionnement pendant un geste, 6.14).
///
/// Fil principal uniquement.
@MainActor
public final class DiscInputCoordinator {
    public let deck: DeckID
    weak var model: DeckViewModel?
    private(set) var geometry = DiscGeometry(width: 0, height: 0)
    private var session: DiscGestureSession
    private var scrollMapper: ScrollGestureMapper
    private let releaseTimer: ScrollReleaseTimer
    /// Horloge des événements (secondes depuis le démarrage, comme `UITouch` et `NSEvent`).
    var clock: () -> Double = { ProcessInfo.processInfo.systemUptime }

    init(deck: DeckID, releaseTimer: ScrollReleaseTimer? = nil) {
        self.deck = deck
        self.releaseTimer = releaseTimer ?? ScrollReleaseTimer()
        session = DiscGestureSession(deck: deck, centerX: 0, centerY: 0, vinylRadius: 0, grabRadius: 0)
        scrollMapper = ScrollGestureMapper(deck: deck, centerX: 0, centerY: 0, vinylRadius: 0, grabRadius: 0)
    }

    /// Le disque est tenu par un contact ou par un défilement.
    public var isHolding: Bool { session.isHolding || scrollMapper.isHolding }
    var isHoldingContact: Bool { session.isHolding }

    /// Le point (repère du traqueur) saisirait le disque : son chargé et zone de saisie (curseur Mac).
    func isGrabbable(x: Double, y: Double) -> Bool {
        model?.isLoaded == true && geometry.contains(x: x, y: y)
    }

    /// Taille courante de la surface (cadre carré du plateau), relue à chaque événement.
    func updateGeometry(width: Double, height: Double) {
        let next = DiscGeometry(width: width, height: height)
        guard next != geometry else { return }
        geometry = next
        session.updateGeometry(centerX: next.centerX, centerY: next.centerY,
                               vinylRadius: next.vinylRadius, grabRadius: next.grabRadius)
        scrollMapper.updateGeometry(centerX: next.centerX, centerY: next.centerY,
                                    vinylRadius: next.vinylRadius, grabRadius: next.grabRadius)
    }

    // MARK: Contacts

    func contactBegan(_ id: Int, at sample: ContactSample) {
        guard model?.isLoaded == true, !scrollMapper.isHolding else { return }
        send(session.began(contact: id, at: sample))
    }

    /// Échantillons regroupés puis prédits d'un contact, dans l'ordre.
    func contactMoved(_ id: Int, samples: [ContactSample]) {
        session.moved(contact: id, samples: samples).forEach { send($0) }
    }

    /// Fin ou annulation du contact par le système (RM-60).
    func contactEnded(_ id: Int, time: Double) {
        send(session.ended(contact: id, time: time))
    }

    /// Annulation programmée (CA 8) : rotation de l'écran, changement de disposition, sélecteur de
    /// platine (4.4). Relâche le contact et le défilement en cours.
    public func cancelAll(time: Double? = nil) {
        send(session.cancelAll(time: time ?? clock()))
        send(scrollMapper.poll(now: .infinity))
        releaseTimer.disarm()
    }

    // MARK: Défilement

    func scroll(x: Double, y: Double, deltaX: Double, deltaY: Double, phase: ScrollGestureMapper.Phase,
                time: Double) {
        guard !session.isHolding else { return }
        let grabs = phase == .began || phase == .none
        if grabs, !scrollMapper.isHolding, model?.isLoaded != true {
            send(scrollMapper.poll(now: time))
            return
        }
        scrollMapper.scroll(x: x, y: y, deltaX: deltaX, deltaY: deltaY, phase: phase, time: time).forEach { send($0) }
        armReleaseTimer()
    }

    /// Échéance de la minuterie : émet le relâchement s'il est dû.
    func pollScroll() {
        send(scrollMapper.poll(now: clock()))
        armReleaseTimer()
    }

    private func armReleaseTimer() {
        guard let deadline = scrollMapper.releaseDeadline else {
            releaseTimer.disarm()
            return
        }
        releaseTimer.arm(after: deadline - clock()) { [weak self] in self?.pollScroll() }
    }

    // MARK: Envoi

    private func send(_ command: EngineCommand?) {
        guard let command, let model else { return }
        switch command {
        case let .touchBegan(_, angle, time): model.touchBegan(angle: angle, time: time)
        case let .touchMoved(_, angle, time, predicted): model.touchMoved(angle: angle, time: time, predicted: predicted)
        case let .touchEnded(_, time): model.touchEnded(time: time)
        default: break
        }
    }
}
