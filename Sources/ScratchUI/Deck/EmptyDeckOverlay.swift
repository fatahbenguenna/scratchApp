import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// État vide d'une platine, posé sur la feutrine : « Importer », « Charger la démo », « ou déposez un
/// fichier ici » (iPad, Mac) et le texte d'aide (SF-01 ; UX §5.1, §7.2, §8.2).
///
/// Un START sur la platine vide met les deux actions en avant (pulsation 1,0 → 1,05 → 1,0 en 300 ms,
/// supprimée avec « Réduire les animations ») et VoiceOver l'annonce (PO-01, UX §5.2, §8.6).
struct EmptyDeckOverlay: View {
    let model: DeckViewModel
    let intents: any DeckIntents
    /// Diamètre du vinyle D.
    let disc: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let id = "deck.\(model.deck.rawValue.lowercased())"
        VStack(spacing: 8) {
            VStack(spacing: 8) {
                Button { intents.importFile(on: model.deck) } label: {
                    Label("Importer", systemImage: "square.and.arrow.down")
                }
                .disabled(!model.isImportEnabled)
                .accessibilityLabel("Importer, \(model.deckName)")
                .accessibilityIdentifier("\(id).emptyImport")
                Button("Charger la démo") { intents.loadDemo(on: model.deck) }
                    .accessibilityLabel("Charger le son de démonstration, \(model.deckName)")
                    .accessibilityIdentifier("\(id).loadDemo")
            }
            .buttonStyle(RaisedButtonStyle(accent: Theme.deckColor(model.deck)))
            .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? 0 : model.emptyDeckHighlightCount) {
                content, scale in content.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1.05, duration: 0.15)
                    CubicKeyframe(1.0, duration: 0.15)
                }
            }
            if Self.acceptsDrops {
                Text("ou déposez un fichier ici").font(Theme.caption).foregroundStyle(Theme.textSecondary)
            }
            Text("Chargez la démo, appuyez sur START, puis posez le doigt sur le disque.")
                .font(Theme.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: disc * 0.62)
        .onChange(of: model.emptyDeckHighlightCount) {
            AccessibilityNotification.Announcement(model.emptyStartAnnouncement).post()
        }
    }

    /// Le glisser-déposer existe sur iPad et Mac (SF-73).
    @MainActor private static var acceptsDrops: Bool {
        #if os(macOS)
        return true
        #else
        return UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }
}

/// Bouton secondaire de l'écran principal : fond `bg.raised`, enfoncé `bg.pressed`, rayon 8, zone
/// tactile de 44 pt. `compact` : visuel de 26 pt calé en haut de la zone (en-tête de platine).
struct RaisedButtonStyle: ButtonStyle {
    var accent: Color = Theme.textPrimary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        RaisedButtonBody(configuration: configuration, accent: accent, compact: compact)
    }
}

private struct RaisedButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let accent: Color
    let compact: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        configuration.label
            .font(Theme.body.weight(.semibold))
            .foregroundStyle(isEnabled ? accent : Theme.textDisabled)
            .padding(.horizontal, compact ? 10 : 12)
            .frame(minHeight: compact ? 26 : 32)
            .background(
                RoundedRectangle(cornerRadius: Theme.buttonRadius)
                    .fill(configuration.isPressed ? Theme.bgPressed : Theme.bgRaised)
            )
            // Increased contrast: 1.5 pt button outlines (UX §9.2).
            .overlay(
                RoundedRectangle(cornerRadius: Theme.buttonRadius)
                    .strokeBorder(Theme.strokeStrong, lineWidth: contrast == .increased ? 1.5 : 0)
            )
            .frame(minHeight: 44, alignment: compact ? .top : .center)
            .contentShape(Rectangle())
    }
}
