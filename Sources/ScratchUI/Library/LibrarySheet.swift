import ScratchCore
import ScratchLibrary
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Feuille Bibliothèque (story 3.5 ; SF-74, UX §3.5, §5.19).
///
/// - **Sections** : « Démonstration », puis « Mes sons ».
/// - **Charger** : « Charger sur A » et « Charger sur B » passent par le parcours de 6.1, avec
///   confirmation si la platine porte un son actif (D-40). La feuille se ferme après le chargement.
/// - **Supprimer** : balayage, mode « Modifier » (iOS), menu contextuel, ou ⌫ sur la ligne
///   sélectionnée (Mac). Une confirmation est toujours demandée, et jamais pour la démo.
/// - **Fermeture** : « OK », ou Échap sur Mac. Sur Mac, la feuille mesure au moins 560 × 480.
///
/// Pendant que la feuille est ouverte, elle présente elle-même les alertes et les confirmations
/// de l'`AppModel`.
struct LibrarySheet: View {
    let model: AppModel
    @State private var selection: UUID?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        let list = LibraryListModel(entries: model.libraryEntries) { model.decks(carrying: $0) }
        NavigationStack {
            List(selection: $selection) {
                Section("Démonstration") {
                    ForEach(list.demo) { row in
                        LibraryRow(row: row, compact: compact, onLoad: { load(row, on: $0) }, onDelete: nil)
                            .tag(row.id)
                    }
                }
                Section {
                    ForEach(list.mine) { row in
                        LibraryRow(row: row, compact: compact, onLoad: { load(row, on: $0) },
                                   onDelete: { model.requestDelete(row.entry) })
                            .tag(row.id)
                    }
                    .onDelete { offsets in
                        if let index = offsets.first { model.requestDelete(list.mine[index].entry) }
                    }
                } header: {
                    Text("Mes sons")
                } footer: {
                    if list.mine.isEmpty { Text(LibraryListModel.emptyText(for: idiom)) }
                }
            }
            .navigationTitle("Bibliothèque")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { model.closeLibrary() }
                        .accessibilityIdentifier("library.done")
                }
                #if os(iOS)
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                #endif
            }
            #if os(macOS)
            .onDeleteCommand {
                guard let selection, let row = list.mine.first(where: { $0.id == selection }) else { return }
                model.requestDelete(row.entry)
            }
            .onExitCommand { model.closeLibrary() }
            #endif
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 480)
        #endif
        .accessibilityIdentifier("library.sheet")
        .modifier(AppModelAlerts(model: model, isActive: true))
    }

    private func load(_ row: LibraryRowItem, on deck: DeckID) {
        Task { await model.loadFromLibrary(row.entry, on: deck) }
    }

    private var compact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    private var idiom: LibraryListModel.Idiom {
        #if os(macOS)
        return .mac
        #else
        return UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone
        #endif
    }
}
