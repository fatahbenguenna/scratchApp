import SwiftUI
import ScratchCore

/// Vue racine de ScratchApp : platine A, table de mixage, platine B (spec v2.0 — 3.4).
///
/// Version de départ (sprint 0) : simple maquette statique. Les vraies vues (disque, commandes,
/// table de mixage, dispositions iPhone/iPad/Mac) sont livrées par les stories de l'épopée UI.
public struct RootView: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 24) {
            DeckPlaceholder(deck: .a)
            VStack(spacing: 12) {
                Text("Table de mixage").font(.headline)
                Text("Crossfader A ↔ B").font(.caption).foregroundStyle(.secondary)
            }
            .frame(minWidth: 160)
            DeckPlaceholder(deck: .b)
        }
        .padding(24)
        .frame(minWidth: 320, minHeight: 320)
    }
}

private struct DeckPlaceholder: View {
    let deck: DeckID

    var body: some View {
        VStack(spacing: 12) {
            Text("Platine \(deck.rawValue)").font(.title2.bold())
            Circle()
                .fill(Color.black)
                .overlay(Circle().fill(Color.orange).frame(width: 60, height: 60))
                .aspectRatio(1, contentMode: .fit)
                .accessibilityLabel("Disque de la platine \(deck.rawValue)")
            Text("33⅓ RPM").font(.caption.monospacedDigit())
        }
    }
}

#Preview {
    RootView()
}
