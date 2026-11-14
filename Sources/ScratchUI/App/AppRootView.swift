import ScratchCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Fenêtre de l'application (stories 6.1, 3.5, 6.2). Elle affiche `RootView` animée par l'`AppModel`,
/// qui sert aussi d'intentions (`DeckIntents`). Elle porte :
/// - le sélecteur de fichiers ;
/// - la feuille Bibliothèque, et sur Mac son bouton dans la barre d'outils ;
/// - les réglages (3.4) : feuille sur iOS, fenêtre Réglages sur Mac ;
/// - les alertes et confirmations ;
/// - le bandeau (UX §5.21) ;
/// - le lancement (`AppModel.launch()` : réconciliation, puis hôte audio) ;
/// - le cycle de vie (6.2) : sur iPhone et iPad, arrière-plan, premier plan et verrouillage de
///   l'écran (D-37) ; sur Mac, la fermeture de la fenêtre quitte l'app (D-38).
public struct AppRootView: View {
    @Bindable private var model: AppModel
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    private let keyboard: KeyboardController?
    #else
    @Environment(\.scenePhase) private var scenePhase
    #endif

    public init(model: AppModel) {
        self.model = model
        #if os(macOS)
        keyboard = nil
        #endif
    }

    #if os(macOS)
    /// Mac : `keyboard` est le contrôleur clavier partagé avec les menus (`ScratchCommands`), créé une
    /// seule fois par l'app (story 6.2).
    public init(model: AppModel, keyboard: KeyboardController) {
        self.model = model
        self.keyboard = keyboard
    }
    #endif

    public var body: some View {
        root
            .overlay(alignment: .top) { ToastOverlay(center: model.toasts) }
            .modifier(ImportPicker(model: model))
            // While the library sheet is open, it presents the alerts itself.
            .modifier(AppModelAlerts(model: model, isActive: !model.isLibraryPresented))
            .sheet(isPresented: $model.isLibraryPresented) {
                LibrarySheet(model: model)
            }
            #if os(iOS)
            .background {
                // A second sheet presenter: Settings (3.4).
                Color.clear.sheet(isPresented: $model.isSettingsPresented) {
                    SettingsSheet(model: model)
                }
            }
            #else
            .onChange(of: model.isSettingsPresented) {
                // Mac: the standard Settings window (⌘,) of the Settings scene.
                guard model.isSettingsPresented else { return }
                model.isSettingsPresented = false
                openSettings()
            }
            #endif
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { model.openLibrary() } label: {
                        Label("Bibliothèque", systemImage: "music.note.list")
                    }
                    .help("Bibliothèque (⌘L)")
                    .accessibilityIdentifier("library.open")
                }
            }
            .background(MainWindowCloseHost().accessibilityHidden(true))
            #else
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: model.enterBackground()
                case .active: model.enterForeground()
                default: break
                }
            }
            .onChange(of: model.keepsScreenAwake, initial: true) { _, awake in
                UIApplication.shared.isIdleTimerDisabled = awake
            }
            #endif
            .task { await model.launch() }
    }

    @ViewBuilder
    private var root: some View {
        #if os(macOS)
        if let keyboard {
            RootView(model: model, intents: model, keyboard: keyboard)
        } else {
            RootView(model: model, intents: model)
        }
        #else
        RootView(model: model, intents: model)
        #endif
    }
}

#if os(macOS)
/// Mac : la fermeture de la fenêtre principale quitte l'app (D-38, SF-81), même si la fenêtre d'aide
/// des raccourcis ou les réglages restent ouverts. Une fenêtre inactive ne change rien : la lecture
/// continue.
struct MainWindowCloseHost: NSViewRepresentable {
    func makeNSView(context: Context) -> HostView { HostView() }
    func updateNSView(_ view: HostView, context: Context) {}

    final class HostView: NSView {
        private var observer: (any NSObjectProtocol)?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            guard let window else { return }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                              queue: .main) { _ in
                // Quit once the close has completed.
                Task { @MainActor in NSApp.terminate(nil) }
            }
        }
    }
}
#endif

/// Alertes de l'`AppModel` : erreur (UX §8.3), confirmation de remplacement et de suppression
/// (UX §8.4). Les boutons répondent ; la fermeture par SwiftUI ne fait que relire les files.
/// `isActive` choisit la vue qui présente : la fenêtre, ou la feuille Bibliothèque ouverte.
struct AppModelAlerts: ViewModifier {
    let model: AppModel
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .alert(model.alert?.title ?? "", isPresented: presented { model.alert != nil }, presenting: model.alert) { _ in
                Button("OK") { model.dismissAlert() }
            } message: { alert in
                Text(alert.message)
            }
            .background {
                // One alert per view: the confirmations use their own presenters.
                Color.clear
                    .alert(model.confirmation?.title ?? "", isPresented: presented { model.confirmation != nil },
                           presenting: model.confirmation) { _ in
                        Button("Remplacer") { model.resolveConfirmation(replace: true) }
                        Button("Annuler", role: .cancel) { model.resolveConfirmation(replace: false) }
                    } message: { confirmation in
                        Text(confirmation.message)
                    }
            }
            .background {
                Color.clear
                    .alert(model.deletionConfirmation?.title ?? "", isPresented: presented { model.deletionConfirmation != nil },
                           presenting: model.deletionConfirmation) { _ in
                        Button("Supprimer", role: .destructive) { model.resolveDeletion(confirm: true) }
                        Button("Annuler", role: .cancel) { model.resolveDeletion(confirm: false) }
                    } message: { confirmation in
                        Text(confirmation.message)
                    }
            }
    }

    private func presented(_ isPending: @escaping () -> Bool) -> Binding<Bool> {
        let isActive = self.isActive
        return Binding(get: { isActive && isPending() }, set: { _ in })
    }
}
