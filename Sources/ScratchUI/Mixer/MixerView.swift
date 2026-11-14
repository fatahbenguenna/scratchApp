import ScratchCore
import SwiftUI

/// Table de mixage des dispositions côte à côte (spec 3.2 ; UX §4.5, §4.6) : badge de sortie et
/// SAT, faders de voie avec VU-mètres, courbe, hamster, crossfader en bas. Sur iPad, Bibliothèque et
/// Réglages en tête ; sur Mac, ils sont dans la barre d'outils et les menus (3.5, 6.2).
struct MixerView: View {
    let mixer: MixerViewModel
    let deckA: DeckViewModel
    let deckB: DeckViewModel
    let intents: any DeckIntents
    let outputStatus: AudioOutputStatus
    let metrics: MainLayoutMetrics

    /// iPhone paysage : courbe et hamster dans le panneau « Table » (D-30, UX §4.3).
    private var isPhone: Bool { metrics.idiom == .phoneLandscape }

    var body: some View {
        VStack(spacing: isPhone ? 8 : 12) {
            #if os(iOS)
            HStack {
                LibraryButton(intents: intents)
                Spacer(minLength: 8)
                if isPhone { MixerSettingsPopover(mixer: mixer).labelStyle(.iconOnly) }
                Spacer(minLength: 8)
                SettingsButton(intents: intents)
            }
            .labelStyle(.iconOnly)
            #endif
            HStack(spacing: 8) {
                OutputBadge(status: outputStatus)
                Spacer(minLength: 0)
                SaturationIndicator(mixer: mixer)
            }
            HStack(alignment: .top) {
                ChannelFader(mixer: mixer, deck: deckA)
                Spacer(minLength: 8)
                ChannelFader(mixer: mixer, deck: deckB)
            }
            .frame(maxHeight: .infinity)
            if !isPhone {
                CrossfaderCurveControl(mixer: mixer)
                HamsterToggle(mixer: mixer)
            }
            CrossfaderView(mixer: mixer, height: metrics.crossfaderHeight)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .macFocusSection()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Table de mixage")
    }
}

/// Bouton « Bibliothèque » (`library.open`) : intention de la 3.5 (Hugo).
struct LibraryButton: View {
    let intents: any DeckIntents

    var body: some View {
        Button { intents.openLibrary() } label: { Label("Bibliothèque", systemImage: "music.note.list") }
            .buttonStyle(RaisedButtonStyle())
            .accessibilityIdentifier("library.open")
    }
}

/// Bouton « Réglages » (`settings.open`).
struct SettingsButton: View {
    let intents: any DeckIntents

    var body: some View {
        Button { intents.openSettings() } label: { Label("Réglages", systemImage: "gearshape") }
            .buttonStyle(RaisedButtonStyle())
            .accessibilityIdentifier("settings.open")
    }
}

#if DEBUG
#Preview("Table, sortie USB, limiteur actif") {
    let environment = PreviewEnvironment(scenario: .playing)
    return MixerView(mixer: environment.model.mixer, deckA: environment.model.deckA, deckB: environment.model.deckB,
                     intents: environment.intents,
                     outputStatus: .running(AudioOutputInfo(name: "MPC Sample (USB)", sampleRate: 48_000,
                                                            bufferFrames: 256, outputLatency: 0.005)),
                     metrics: MainLayoutMetrics(width: 1200, height: 760, idiom: .mac))
        .frame(width: 240, height: 640)
        .background(Theme.bgSurface)
        .preferredColorScheme(.dark)
}
#endif
