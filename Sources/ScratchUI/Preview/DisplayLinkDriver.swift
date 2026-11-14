import QuartzCore
import ScratchCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Horloge d'affichage : appelle `AppModel.tick()` une fois par image de l'écran (UX §10.1 ; ADR-12).
///
/// `CADisplayLink` sur iOS (80 à 120 Hz demandés), `NSView.displayLink(target:selector:)` sur
/// macOS 14. La boucle se suspend quand l'instantané est au repos (`EngineSnapshot.isIdle`) sans
/// interruption pendant `idleGracePeriod`, si une source de réveil est branchée
/// (`DisplayWakingEngine`) ; elle reprend à la commande suivante. Le délai de grâce couvre le retard
/// de l'instantané sur les commandes quand l'hôte audio rend le son (bug #57) : après un réveil,
/// les premières images lisent encore un instantané au repos. Sans source de réveil, la boucle ne se
/// suspend jamais. Fil principal uniquement.
@MainActor
public final class DisplayLinkDriver {
    private let frameHandler: @MainActor () -> Bool
    private var link: CADisplayLink?
    private let target = DisplayLinkTarget()

    /// Repos continu exigé avant la suspension, compté depuis la dernière image active ou le dernier
    /// réveil : bien plus long que deux périodes de rendu (≤ 23 ms).
    public static let idleGracePeriod = 0.1

    /// Autorise la suspension au repos (une source de réveil appelle `wake()`).
    public var allowsSuspension = false
    public private(set) var isSuspended = false
    /// Début du repos en cours (horloge des images), `nil` si la dernière image n'était pas au repos.
    private var idleSince: Double?

    /// - Parameter onFrame: travail d'une image ; renvoie `true` si rien ne bouge (boucle suspendable).
    public init(onFrame: @escaping @MainActor () -> Bool) {
        frameHandler = onFrame
        target.driver = self
    }

    /// Reprend la boucle suspendue et relance le délai de grâce (à appeler à chaque commande envoyée
    /// au moteur).
    public func wake() {
        idleSince = nil
        guard isSuspended else { return }
        isSuspended = false
        link?.isPaused = false
    }

    /// Arrête l'horloge (vue retirée de la fenêtre).
    public func invalidate() {
        link?.invalidate()
        link = nil
    }

    /// Une image, à l'instant `now` (secondes, horloge monotone des images).
    func step(now: Double) {
        guard frameHandler() else {
            idleSince = nil
            return
        }
        let since = idleSince ?? now
        idleSince = since
        if allowsSuspension, !isSuspended, now - since >= Self.idleGracePeriod {
            isSuspended = true
            link?.isPaused = true
        }
    }

    fileprivate func start(_ newLink: CADisplayLink) {
        invalidate()
        newLink.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        newLink.isPaused = isSuspended
        newLink.add(to: .main, forMode: .common)
        link = newLink
    }

    #if os(macOS)
    fileprivate func attach(to view: NSView) {
        start(view.displayLink(target: target, selector: #selector(DisplayLinkTarget.step(_:))))
    }
    #else
    fileprivate func attach(to view: UIView) {
        start(CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.step(_:))))
    }
    #endif
}

/// Cible Objective-C du `CADisplayLink`, qui retient sa cible : référence faible vers l'horloge.
private final class DisplayLinkTarget: NSObject {
    weak var driver: DisplayLinkDriver?

    @objc func step(_ link: CADisplayLink) {
        MainActor.assumeIsolated { driver?.step(now: link.timestamp) }
    }
}

/// Vue invisible qui porte l'horloge d'affichage : la boucle suit la fenêtre (et son écran).
struct DisplayLinkHost {
    let driver: DisplayLinkDriver
}

#if os(macOS)
extension DisplayLinkHost: NSViewRepresentable {
    func makeNSView(context: Context) -> HostView { HostView(driver: driver) }
    func updateNSView(_ view: HostView, context: Context) {}
    static func dismantleNSView(_ view: HostView, coordinator: ()) { view.driver.invalidate() }

    final class HostView: NSView {
        let driver: DisplayLinkDriver
        init(driver: DisplayLinkDriver) {
            self.driver = driver
            super.init(frame: .zero)
        }
        @available(*, unavailable) required init?(coder: NSCoder) { nil }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil { driver.invalidate() } else { driver.attach(to: self) }
        }
    }
}
#else
extension DisplayLinkHost: UIViewRepresentable {
    func makeUIView(context: Context) -> HostView { HostView(driver: driver) }
    func updateUIView(_ view: HostView, context: Context) {}
    static func dismantleUIView(_ view: HostView, coordinator: ()) { view.driver.invalidate() }

    final class HostView: UIView {
        let driver: DisplayLinkDriver
        init(driver: DisplayLinkDriver) {
            self.driver = driver
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }
        @available(*, unavailable) required init?(coder: NSCoder) { nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { driver.invalidate() } else { driver.attach(to: self) }
        }
    }
}
#endif

/// Relais d'`EngineControlling` qui réveille la boucle d'affichage à chaque commande envoyée.
/// L'`AppModel` le reçoit à la place du moteur ; `RootView` le branche sur son horloge.
public final class DisplayWakingEngine: EngineControlling {
    public let base: any EngineControlling
    /// Appelé sur le fil de contrôle après chaque commande acceptée.
    public var onCommand: (() -> Void)?

    public init(wrapping base: any EngineControlling) {
        self.base = base
    }

    @discardableResult
    public func send(_ command: EngineCommand) -> Bool {
        let accepted = base.send(command)
        if accepted { onCommand?() }
        return accepted
    }

    public func latestSnapshot() -> EngineSnapshot { base.latestSnapshot() }

    @discardableResult
    public func drainReleasedClips() -> Int { base.drainReleasedClips() }

    public func pump() { base.pump() }
}
