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
/// macOS 14. La boucle se suspend quand l'instantané est au repos (`EngineSnapshot.isIdle`) si une
/// source de réveil est branchée (`DisplayWakingEngine`) ; elle reprend à la commande suivante.
/// Sans source de réveil, elle ne se suspend jamais. Fil principal uniquement.
@MainActor
public final class DisplayLinkDriver {
    private let frameHandler: @MainActor () -> Bool
    private var link: CADisplayLink?
    private let target = DisplayLinkTarget()

    /// Autorise la suspension au repos (une source de réveil appelle `wake()`).
    public var allowsSuspension = false
    public private(set) var isSuspended = false

    /// - Parameter onFrame: travail d'une image ; renvoie `true` si rien ne bouge (boucle suspendable).
    public init(onFrame: @escaping @MainActor () -> Bool) {
        frameHandler = onFrame
        target.driver = self
    }

    /// Reprend la boucle suspendue (à appeler à chaque commande envoyée au moteur).
    public func wake() {
        guard isSuspended else { return }
        isSuspended = false
        link?.isPaused = false
    }

    /// Arrête l'horloge (vue retirée de la fenêtre).
    public func invalidate() {
        link?.invalidate()
        link = nil
    }

    func step() {
        let isIdle = frameHandler()
        if isIdle, allowsSuspension, !isSuspended {
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
        MainActor.assumeIsolated { driver?.step() }
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
