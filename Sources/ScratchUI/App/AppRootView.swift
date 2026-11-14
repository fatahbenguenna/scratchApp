import ScratchCore
import SwiftUI

/// Fenêtre de l'application (story 6.1). Elle affiche `RootView` animée par l'`AppModel`, qui sert
/// aussi d'intentions (`DeckIntents`). Elle porte :
/// - le sélecteur de fichiers ;
/// - les alertes d'erreur (UX §8.3) et la confirmation de remplacement (UX §8.4) ;
/// - le bandeau (UX §5.21) ;
/// - la réconciliation du lancement (`AppModel.launch()`).
public struct AppRootView: View {
    private let model: AppModel

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        RootView(model: model, intents: model)
            .overlay(alignment: .top) { ToastOverlay(center: model.toasts) }
            .modifier(ImportPicker(model: model))
            .alert(model.alert?.title ?? "", isPresented: alertIsPresented, presenting: model.alert) { _ in
                Button("OK") { model.dismissAlert() }
            } message: { alert in
                Text(alert.message)
            }
            .background {
                // A second presenter: SwiftUI shows one alert per view.
                Color.clear
                    .alert(model.confirmation?.title ?? "", isPresented: confirmationIsPresented,
                           presenting: model.confirmation) { _ in
                        Button("Remplacer") { model.resolveConfirmation(replace: true) }
                        Button("Annuler", role: .cancel) { model.resolveConfirmation(replace: false) }
                    } message: { confirmation in
                        Text(confirmation.message)
                    }
            }
            .task { await model.launch() }
    }

    // The buttons resolve the alerts; SwiftUI's dismissal only re-reads the queues.
    private var alertIsPresented: Binding<Bool> {
        Binding(get: { model.alert != nil }, set: { _ in })
    }

    private var confirmationIsPresented: Binding<Bool> {
        Binding(get: { model.confirmation != nil }, set: { _ in })
    }
}
