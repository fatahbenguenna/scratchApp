import Foundation
import ScratchCore
import ScratchLibrary

// MARK: - Préférences et réglages (story 3.4)

extension AppModel {
    /// Applique les préférences enregistrées au moteur, au lancement (SF-17, RM-10, PO-12, D-45).
    /// Sont restaurés : vitesse, pitch, résistance, table de mixage, durées du moteur et rattrapage.
    /// Aucune commande `motor` ni `load` n'est envoyée, et aucun son n'est rechargé.
    func applyPreferences() {
        let loaded = preferences.load()
        for command in loaded.engineCommands { engine.send(command) }
        let now = clock()
        preferencesTracker.didApply(loaded, at: now)
        commandedTimings.command(loaded.motor, at: now)
        motorTimings = loaded.motor
    }

    /// Enregistre tout de suite les réglages en attente (passage en arrière-plan, 6.2).
    public func savePreferencesNow() {
        preferencesSaveTask?.cancel()
        preferencesSaveTask = nil
        pendingPreferences = nil
        let current = AppPreferences(snapshot: engine.latestSnapshot())
        if let changed = preferencesTracker.observe(current, at: clock()) {
            preferences.save(changed)
            preferencesTracker.didSave(changed)
        }
    }

    /// Durée de démarrage, de 0,1 à 5,0 s par pas de 0,1 s (SF-04, D-18), commune aux deux platines.
    public func setStartDuration(_ seconds: Double) {
        setTimings(command: EngineCommand.startDuration) { $0.startDuration = $1 } value: {
            SettingsFormatting.quantized(seconds, step: 0.1, in: TurntableConstants.motorDurationRange)
        }
    }

    /// Durée de freinage, de 0,1 à 5,0 s par pas de 0,1 s (SF-05, D-18).
    public func setBrakeDuration(_ seconds: Double) {
        setTimings(command: EngineCommand.brakeDuration) { $0.brakeDuration = $1 } value: {
            SettingsFormatting.quantized(seconds, step: 0.1, in: TurntableConstants.motorDurationRange)
        }
    }

    /// Temps de rattrapage de la feutrine, de 0 à 300 ms par pas de 10 ms (SF-68).
    public func setSlipmatCatchUp(_ seconds: Double) {
        setTimings(command: EngineCommand.slipmatCatchUp) { $0.slipmatCatchUp = $1 } value: {
            SettingsFormatting.quantized(seconds, step: 0.01, in: TurntableConstants.slipmatCatchUpRange)
        }
    }

    private func setTimings(command: (Double) -> EngineCommand, update: (inout MotorTimings, Double) -> Void,
                            value: () -> Double) {
        let newValue = value()
        guard engine.send(command(newValue)) else { return }
        var timings = motorTimings
        update(&timings, newValue)
        commandedTimings.command(timings, at: clock())
        motorTimings = timings
    }

    /// À chaque image : un changement de réglage est enregistré 0,5 s après le dernier changement,
    /// jamais depuis le fil audio, jamais à chaque image (CA 5).
    func trackPreferences(in snapshot: EngineSnapshot) {
        guard let changed = preferencesTracker.observe(AppPreferences(snapshot: snapshot), at: clock()) else {
            // Back to the saved value (or not yet confirmed): nothing to write.
            preferencesSaveTask?.cancel()
            preferencesSaveTask = nil
            pendingPreferences = nil
            return
        }
        guard changed != pendingPreferences else { return }
        pendingPreferences = changed
        preferencesSaveTask?.cancel()
        let delay = preferencesSaveDelay
        preferencesSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.savePendingPreferences()
        }
    }

    private func savePendingPreferences() {
        guard let pending = pendingPreferences else { return }
        preferences.save(pending)
        preferencesTracker.didSave(pending)
        pendingPreferences = nil
        preferencesSaveTask = nil
    }
}

/// Préférences à enregistrer (story 3.4), en logique pure.
///
/// Rien n'est enregistré avant que l'instantané confirme les préférences appliquées au lancement :
/// une image rendue avant leur application ne doit pas écraser le document enregistré. Passé une
/// seconde sans confirmation (valeur bornée par le moteur), l'instantané fait foi.
struct PreferencesTracker {
    static let confirmationTimeout = 1.0

    private var applied: AppPreferences?
    private var appliedAt = 0.0
    private var confirmed = false
    private(set) var lastSaved: AppPreferences?

    mutating func didApply(_ preferences: AppPreferences, at now: Double) {
        applied = preferences
        appliedAt = now
        confirmed = false
        lastSaved = preferences
    }

    /// Préférences de l'image courante : celles à enregistrer, ou `nil` si rien n'a changé depuis le
    /// dernier enregistrement (ou si les préférences du lancement ne sont pas encore confirmées).
    mutating func observe(_ current: AppPreferences, at now: Double) -> AppPreferences? {
        guard let applied else { return nil }
        if !confirmed {
            guard current == applied || now - appliedAt >= Self.confirmationTimeout else { return nil }
            confirmed = true
        }
        return current == lastSaved ? nil : current
    }

    mutating func didSave(_ preferences: AppPreferences) {
        lastSaved = preferences
    }
}

/// Formats de l'écran Réglages (UX §5.20, §8.1).
enum SettingsFormatting {
    private static let nbsp = "\u{00A0}"

    /// Valeur ramenée à la plage puis au pas (sans erreur d'arrondi binaire : 0,7 et non 0,70…01).
    static func quantized(_ value: Double, step: Double, in range: ClosedRange<Double>) -> Double {
        let bounded = value.clamped(to: range, fallback: range.lowerBound)
        let scale = (1 / step).rounded()
        return ((bounded * scale).rounded() / scale).clamped(to: range, fallback: range.lowerBound)
    }

    /// « 0,7 s », « 1,0 s ».
    static func seconds(_ value: Double) -> String { "\(decimal(value))\(nbsp)s" }

    /// « 60 ms ».
    static func milliseconds(_ value: Double) -> String { "\(Int((value * 1000).rounded()))\(nbsp)ms" }

    /// Valeur du champ numérique Mac : « 0,7 » (secondes) ou « 60 » (millisecondes).
    static func fieldText(_ value: Double, milliseconds: Bool) -> String {
        milliseconds ? "\(Int((value * 1000).rounded()))" : decimal(value)
    }

    /// Lecture du champ numérique Mac (virgule ou point décimal) ; `nil` si la saisie est invalide.
    static func parse(_ text: String, milliseconds: Bool) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let number = Double(cleaned), number.isFinite else { return nil }
        return milliseconds ? number / 1000 : number
    }

    /// VoiceOver : « 0,7 seconde », « 1 seconde », « 2,5 secondes ».
    static func spokenSeconds(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        let text = tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10),\(tenths % 10)"
        return "\(text) \(value >= 2 ? "secondes" : "seconde")"
    }

    /// VoiceOver : « 60 millisecondes », « 0 milliseconde ».
    static func spokenMilliseconds(_ value: Double) -> String {
        let milliseconds = Int((value * 1000).rounded())
        return "\(milliseconds) \(milliseconds >= 2 ? "millisecondes" : "milliseconde")"
    }

    private static func decimal(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        return "\(tenths / 10),\(tenths % 10)"
    }
}
