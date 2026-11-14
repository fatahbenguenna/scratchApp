import ScratchCore
import SwiftUI

/// Fenêtre de l'application (stories 6.1, 3.5). Elle affiche `RootView` animée par l'`AppModel`,
/// qui sert aussi d'intentions (`DeckIntents`). Elle porte :
/// - le sélecteur de fichiers ;
/// - la feuille Bibliothèque, et sur Mac son bouton dans la barre d'outils ;
/// - les alertes et confirmations ;
/// - le bandeau (UX §5.21) ;
/// - la réconciliation du lancement (`AppModel.launch()`).
public struct AppRootView: View {
    @Bindable private var model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        RootView(model: model, intents: model)
            .overlay(alignment: .top) { ToastOverlay(center: model.toasts) }
            .modifier(ImportPicker(model: model))
            // While the library sheet is open, it presents the alerts itself.
            .modifier(AppModelAlerts(model: model, isActive: !model.isLibraryPresented))
            .sheet(isPresented: $model.isLibraryPresented) {
                LibrarySheet(model: model)
            }
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { model.openLibrary() } label: {
                        Label("Bibliothèque", systemImage: "books.vertical")
                    }
                    .help("Bibliothèque (⌘L)")
                    .accessibilityIdentifier("library.open")
                }
            }
            #endif
            .task { await model.launch() }
    }
}

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
