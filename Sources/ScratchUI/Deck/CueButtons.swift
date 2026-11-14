import ScratchCore
import SwiftUI

/// SET CUE et CUE (SF-13 ; UX §5.6) : deux boutons distincts, action **à l'appui**, utilisables d'un
/// autre doigt pendant que le disque est tenu (6.6), désactivés sur une platine vide. SET CUE : contour
/// et texte `cue`, éclat de 150 ms (supprimé avec « Réduire les animations ») et annonce VoiceOver ;
/// CUE : témoin `cue` allumé quand un CUE est défini.
struct CueButtons: View {
    let model: DeckViewModel
    let setCueSize: CGSize
    let cueSize: CGSize
    var spacing: CGFloat = 8
    /// iPhone paysage : « SET / CUE » sur deux lignes, 10 pt.
    var isCompact = false

    var body: some View {
        let id = "deck.\(model.deck.rawValue.lowercased())"
        let enabled = model.isLoaded
        HStack(spacing: spacing) {
            PressButton(enabled: enabled, action: model.setCue) { pressed in
                SetCueFace(title: isCompact ? "SET\nCUE" : "SET CUE", compact: isCompact, pressed: pressed,
                           enabled: enabled, flash: model.setCueCount)
            }
            .frame(width: setCueSize.width, height: setCueSize.height)
            .accessibilityLabel("Mémoriser le point CUE, \(model.deckName)")
            .accessibilityInputLabels(["SET CUE"])
            .accessibilityIdentifier("\(id).setCue")
            PressButton(enabled: enabled, action: model.recallCue) { pressed in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: Theme.buttonRadius).fill(pressed ? Theme.bgPressed : Theme.bgRaised)
                    Text(verbatim: "CUE")
                        .font(isCompact ? .system(size: 10, weight: .bold) : Theme.controlLabel)
                        .tracking(0.5)
                        .foregroundStyle(enabled ? Theme.textPrimary : Theme.textDisabled)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Circle().fill(model.hasCue ? Theme.cue : Theme.vuOff).frame(width: 8, height: 8).padding(6)
                }
            }
            .frame(width: cueSize.width, height: cueSize.height)
            .accessibilityLabel("Revenir au point CUE, \(model.deckName)")
            .accessibilityValue(model.cueAccessibilityValue)
            .accessibilityInputLabels(["CUE"])
            .accessibilityIdentifier("\(id).cue")
        }
        .onChange(of: model.setCueAnnouncementCount) {
            AccessibilityNotification.Announcement(model.setCueAnnouncement).post()
        }
    }
}

/// Face du bouton SET CUE, avec l'éclat de 150 ms après un SET CUE.
private struct SetCueFace: View {
    let title: String
    let compact: Bool
    let pressed: Bool
    let enabled: Bool
    let flash: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = enabled ? Theme.cue : Theme.textDisabled
        RoundedRectangle(cornerRadius: Theme.buttonRadius)
            .fill(pressed ? Theme.bgPressed : Theme.bgRaised)
            .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius).strokeBorder(color, lineWidth: 1.5))
            .overlay(
                Text(verbatim: title)
                    .font(compact ? .system(size: 10, weight: .bold) : Theme.controlLabel)
                    .tracking(0.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(color)
            )
            .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : flash) { content, glow in
                content.overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius).fill(Theme.cue.opacity(glow)))
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0.35, duration: 0.05)
                    LinearKeyframe(0.0, duration: 0.1)
                }
            }
    }
}

/// Bouton de performance qui agit **à l'appui** (UX §5.0), sans annulation par glissement ; activé
/// par VoiceOver comme un bouton.
struct PressButton<Face: View>: View {
    let enabled: Bool
    let action: @MainActor () -> Void
    @ViewBuilder let face: (_ pressed: Bool) -> Face
    @State private var isPressed = false

    var body: some View {
        face(isPressed)
            .scaleEffect(isPressed ? 0.97 : 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard enabled, !isPressed else { return }
                        isPressed = true
                        action()
                    }
                    .onEnded { _ in isPressed = false }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { if enabled { action() } }
            .keyboardActivatable(enabled: enabled, action: action)
            .disabled(!enabled)
    }
}
