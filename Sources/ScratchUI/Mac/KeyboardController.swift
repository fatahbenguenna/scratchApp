#if os(macOS)
import AppKit
import Observation
import ScratchCore
import SwiftUI

/// Clavier Mac de la fenêtre principale (spec 3.5 ; story 5.1 ; D-06 à D-09, D-25, D-34).
///
/// - Moniteur local (`keyDown`, `keyUp`) : il voit chaque frappe avant les menus. Une frappe de
///   raccourci est traitée ici et consommée : un élément de menu à touche simple ne la voit jamais
///   (aucun double déclenchement) et ne réagit qu'au clic.
/// - Contexte actif seulement si l'app est active, la fenêtre principale clé, sans feuille ni
///   fenêtre modale, et sans saisie de texte en cours. Hors contexte, les frappes vont au champ de
///   texte ou au dialogue, et les menus à touche simple sont désactivés (`context.isActive`).
/// - Coupures `F` / `J` refermées à la perte du focus, au passage en arrière-plan ou à l'ouverture
///   d'une feuille.
/// - Échap retire le focus d'une commande (D-07). Les flèches vont au crossfader ; leur envoi à la
///   commande réglable qui a le focus est complété en 5.3.
@MainActor
public final class KeyboardController {
    public let context = KeyboardContext()
    public let names: KeyboardLayoutNames

    private let model: AppModel
    private var dispatcher = KeyboardDispatcher()
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    /// Fenêtre principale (celle de `RootView`).
    weak var window: NSWindow?
    /// Contexte imposé par les tests unitaires (aucune fenêtre).
    var activeOverride: Bool?

    /// - Parameter names: libellés des touches ; `nil` pour la disposition active du système.
    public init(model: AppModel, names: KeyboardLayoutNames? = nil) {
        self.model = model
        self.names = names ?? KeyboardLayoutNames()
    }

    /// Effet d'un élément de menu : même chemin que le clavier.
    public func perform(_ action: KeyboardAction) {
        KeyboardRouter.apply(.perform(action), to: model)
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? event }
        }
        let center = NotificationCenter.default
        let releasing: [Notification.Name] = [NSWindow.didResignKeyNotification, NSWindow.willBeginSheetNotification,
                                               NSApplication.didResignActiveNotification]
        let refreshing: [Notification.Name] = [NSWindow.didBecomeKeyNotification, NSWindow.didEndSheetNotification,
                                                NSApplication.didBecomeActiveNotification]
        for name in releasing + refreshing {
            let releases = releasing.contains(name)
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if releases { self?.releaseAll() }
                    self?.refreshContext()
                }
            })
        }
        refreshContext()
    }

    func uninstall() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
        releaseAll()
    }

    /// Traite une frappe ; renvoie `nil` si elle est consommée.
    func handle(_ event: NSEvent) -> NSEvent? {
        refreshContext()
        switch event.type {
        case .keyDown:
            if event.keyCode == KeyboardShortcutMap.KeyCode.escape, context.isActive, clearFocus() { return nil }
            let result = dispatcher.keyDown(keyCode: event.keyCode, modifiers: Self.modifiers(event.modifierFlags),
                                            isRepeat: event.isARepeat, isActive: context.isActive)
            result.effects.forEach { KeyboardRouter.apply($0, to: model) }
            return result.consumed ? nil : event
        case .keyUp:
            let result = dispatcher.keyUp(keyCode: event.keyCode)
            result.effects.forEach { KeyboardRouter.apply($0, to: model) }
            return result.consumed ? nil : event
        default:
            return event
        }
    }

    /// Referme les coupures ouvertes.
    func releaseAll() {
        dispatcher.releaseAll().forEach { KeyboardRouter.apply($0, to: model) }
    }

    /// ⇧, ⌘, ⌥, ⌃ ; le verrouillage majuscule et les drapeaux des flèches sont ignorés.
    static func modifiers(_ flags: NSEvent.ModifierFlags) -> KeyModifiers {
        var result: KeyModifiers = []
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }

    private func refreshContext() {
        let active = activeOverride ?? Self.isShortcutContextActive(app: NSApp, window: window)
        if context.isActive != active { context.isActive = active }
    }

    /// Raccourcis actifs : app active, fenêtre principale clé sans feuille ni fenêtre modale, aucun
    /// champ de texte en saisie (D-07, D-34).
    static func isShortcutContextActive(app: NSApplication?, window: NSWindow?) -> Bool {
        guard let app, app.isActive, let window, app.keyWindow === window, window.attachedSheet == nil,
              app.modalWindow == nil else { return false }
        return !(window.firstResponder is NSText)
    }

    /// Échap : retire le focus d'une commande ; renvoie `true` s'il y en avait un.
    private func clearFocus() -> Bool {
        guard let window, let responder = window.firstResponder, responder !== window,
              responder !== window.contentView else { return false }
        return window.makeFirstResponder(nil)
    }
}

/// État partagé avec les menus : les éléments à touche simple sont désactivés hors contexte (D-34).
@MainActor
@Observable
public final class KeyboardContext {
    public internal(set) var isActive = false
}

/// Vue invisible qui installe le contrôleur clavier tant que la fenêtre principale est affichée.
struct KeyboardHost: NSViewRepresentable {
    let controller: KeyboardController

    func makeNSView(context: Context) -> HostView { HostView(controller: controller) }
    func updateNSView(_ view: HostView, context: Context) {}
    static func dismantleNSView(_ view: HostView, coordinator: ()) { view.controller.uninstall() }

    final class HostView: NSView {
        let controller: KeyboardController

        init(controller: KeyboardController) {
            self.controller = controller
            super.init(frame: .zero)
        }

        @available(*, unavailable) required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                controller.window = window
                controller.install()
            } else {
                controller.uninstall()
            }
        }
    }
}
#endif
