import SwiftUI

/// Emplacement du bandeau, en haut de l'écran principal, au-dessus des en-têtes de platine (UX §5.21).
/// Il n'occupe que le cadre du bandeau : il n'intercepte aucune touche ailleurs et ne recouvre pas
/// les disques.
struct ToastOverlay: View {
    let center: ToastCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let toast = center.current {
                ToastView(toast: toast) { center.dismiss(toast) }
                    .id(toast.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: center.current)
        .padding(.top, 12)
        .padding(.horizontal, 16)
    }
}

/// Bandeau : capsule `bg.raised` à 95 %, filet `stroke.subtle`, icône et texte de 15 pt sur deux
/// lignes au plus, 480 pt de large au plus ; toucher pour fermer ; annoncé par VoiceOver (UX §5.21).
struct ToastView: View {
    let toast: Toast
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle")
                .accessibilityHidden(true)
            Text(toast.text)
                .font(.system(size: 15))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: 480)
        .background(Capsule().fill(Theme.bgRaised.opacity(0.95)))
        .overlay(Capsule().stroke(Theme.strokeSubtle, lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityHint("Touchez deux fois pour fermer.")
        .accessibilityAction(.default, onTap)
        .onAppear {
            AccessibilityNotification.Announcement(toast.text).post()
        }
    }
}
