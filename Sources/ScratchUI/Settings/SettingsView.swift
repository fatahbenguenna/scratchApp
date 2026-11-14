import ScratchCore
import SwiftUI

/// Écran Réglages (story 3.4 ; SF-04, SF-05, SF-68, D-18 ; UX §5.20).
///
/// - **Sections** : Moteur (durées de démarrage et de freinage, de 0,1 à 5,0 s par pas de 0,1 s) et
///   Feutrine (temps de rattrapage, de 0 à 300 ms par pas de 10 ms). Valeurs communes aux deux
///   platines, appliquées immédiatement et mémorisées (SF-17).
/// - **Mac** : section Clavier, avec « Afficher les raccourcis clavier » (aide de la 5.1).
/// - **Présentation** : iOS, formulaire groupé dans une feuille avec « OK » (`SettingsSheet`) ; Mac,
///   fenêtre Réglages standard (⌘,), un seul panneau.
public struct SettingsView: View {
    let model: AppModel
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                TimingSetting(title: "Durée de démarrage", spokenTitle: "Durée de démarrage",
                              value: model.motorTimings.startDuration, range: TurntableConstants.motorDurationRange,
                              step: 0.1, unit: .seconds, identifier: "settings.startDuration",
                              onChange: { model.setStartDuration($0) })
                TimingSetting(title: "Durée de freinage", spokenTitle: "Durée de freinage",
                              value: model.motorTimings.brakeDuration, range: TurntableConstants.motorDurationRange,
                              step: 0.1, unit: .seconds, identifier: "settings.brakeDuration",
                              onChange: { model.setBrakeDuration($0) })
            } header: {
                Text("Moteur")
            } footer: {
                Text("S'applique aux deux platines. Démarrage\u{00A0}: temps pour atteindre la vitesse après START. Freinage\u{00A0}: temps pour s'arrêter après STOP.")
            }
            Section {
                TimingSetting(title: "Temps de rattrapage", spokenTitle: "Temps de rattrapage de la feutrine",
                              value: model.motorTimings.slipmatCatchUp, range: TurntableConstants.slipmatCatchUpRange,
                              step: 0.01, unit: .milliseconds, identifier: "settings.catchUp",
                              onChange: { model.setSlipmatCatchUp($0) })
            } header: {
                Text("Feutrine")
            } footer: {
                Text("Temps mis par le disque relâché pour rejoindre la vitesse du plateau.")
            }
            #if os(macOS)
            Section("Clavier") {
                Button("Afficher les raccourcis clavier") { openWindow(id: KeyboardHelpWindow.windowID) }
                    .accessibilityIdentifier("settings.keyboardHelp")
            }
            #endif
        }
        .formStyle(.grouped)
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 360)
        #endif
    }
}

/// Feuille Réglages d'iOS : titre « Réglages » et bouton « OK ».
struct SettingsSheet: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            SettingsView(model: model)
                .navigationTitle("Réglages")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { model.isSettingsPresented = false }
                            .accessibilityIdentifier("settings.done")
                    }
                }
        }
    }
}

/// Un réglage de durée. iOS : curseur et valeur. Mac : curseur, champ numérique (« 0,7 ») avec
/// unité et stepper ; une saisie hors plage est ramenée à la borne, une saisie invalide restaure la
/// valeur précédente (UX §5.20).
struct TimingSetting: View {
    enum Unit {
        case seconds, milliseconds

        var factor: Double { self == .seconds ? 1 : 1000 }
        var symbol: String { self == .seconds ? "s" : "ms" }

        func display(_ value: Double) -> String {
            self == .seconds ? SettingsFormatting.seconds(value) : SettingsFormatting.milliseconds(value)
        }

        func spoken(_ value: Double) -> String {
            self == .seconds ? SettingsFormatting.spokenSeconds(value) : SettingsFormatting.spokenMilliseconds(value)
        }
    }

    let title: String
    let spokenTitle: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: Unit
    let identifier: String
    let onChange: @MainActor (Double) -> Void

    #if os(macOS)
    @State private var text = ""
    @FocusState private var isEditing: Bool
    #endif

    var body: some View {
        #if os(macOS)
        LabeledContent(title) {
            HStack(spacing: 8) {
                slider.frame(minWidth: 160)
                TextField(title, text: $text)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                    .focused($isEditing)
                    .onSubmit(commitText)
                    .accessibilityLabel(spokenTitle)
                Text(unit.symbol).foregroundStyle(.secondary).accessibilityHidden(true)
                Stepper(title, value: scaledValue, in: scaledRange, step: step * unit.factor)
                    .labelsHidden()
                    .accessibilityLabel(spokenTitle)
                    .accessibilityValue(unit.spoken(value))
            }
        }
        .onAppear { text = SettingsFormatting.fieldText(value, milliseconds: unit == .milliseconds) }
        .onChange(of: value) {
            if !isEditing { text = SettingsFormatting.fieldText(value, milliseconds: unit == .milliseconds) }
        }
        .onChange(of: isEditing) {
            if !isEditing { commitText() }
        }
        #else
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(unit.display(value)).monospacedDigit().foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            slider
        }
        #endif
    }

    private var slider: some View {
        Slider(value: scaledValue, in: scaledRange, step: step * unit.factor)
            .accessibilityLabel(spokenTitle)
            .accessibilityValue(unit.spoken(value))
            .accessibilityIdentifier(identifier)
    }

    private var scaledRange: ClosedRange<Double> {
        (range.lowerBound * unit.factor)...(range.upperBound * unit.factor)
    }

    private var scaledValue: Binding<Double> {
        Binding(get: { value * unit.factor }, set: { onChange($0 / unit.factor) })
    }

    #if os(macOS)
    /// Saisie validée : ramenée à la plage et au pas, ou valeur précédente si elle est invalide.
    private func commitText() {
        if let parsed = SettingsFormatting.parse(text, milliseconds: unit == .milliseconds) {
            let bounded = SettingsFormatting.quantized(parsed, step: step, in: range)
            onChange(bounded)
            text = SettingsFormatting.fieldText(bounded, milliseconds: unit == .milliseconds)
        } else {
            text = SettingsFormatting.fieldText(value, milliseconds: unit == .milliseconds)
        }
    }
    #endif
}
