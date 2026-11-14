import Foundation
import Observation
#if os(macOS)
import AppKit
import Carbon.HIToolbox
#endif

/// Caractère affiché pour chaque raccourci : celui que produit la touche physique dans la
/// disposition de clavier active (AZERTY, QWERTY…), pour l'aide et les menus (D-08 ; UX §5.22).
/// Mis à jour au changement de disposition. Fil principal.
@MainActor
@Observable
public final class KeyboardLayoutNames {
    /// Change à chaque changement de disposition : les vues et menus qui le lisent se recalculent.
    public private(set) var revision = 0

    @ObservationIgnored private let translate: (UInt16) -> String?
    @ObservationIgnored private var observer: NSObjectProtocol?

    /// - Parameter translate: traduction d'un code de touche ; `nil` pour la disposition active du
    ///   système (Mac), ou la disposition QWERTY de référence ailleurs.
    public init(translate: ((UInt16) -> String?)? = nil) {
        self.translate = translate ?? Self.systemTranslation
        #if os(macOS)
        observer = NotificationCenter.default.addObserver(
            forName: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.revision &+= 1 }
        }
        #endif
    }

    /// Libellé d'une touche : caractère de la disposition active, en capitale, ou flèche.
    public func label(for keyCode: UInt16) -> String {
        _ = revision
        if let arrow = Self.arrows[keyCode] { return arrow }
        if let text = translate(keyCode)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            return text.uppercased()
        }
        return Self.qwerty[keyCode] ?? "?"
    }

    /// Libellé complet d'un raccourci : « ⇧← », « A »…
    public func label(for entry: KeyboardShortcutMap.Entry) -> String {
        (entry.shift ? "⇧" : "") + label(for: entry.keyCode)
    }

    static let arrows: [UInt16: String] = [123: "←", 124: "→", 125: "↓"]
    static let qwerty: [UInt16: String] = [0: "A", 1: "S", 3: "F", 6: "Z", 7: "X", 12: "Q", 35: "P", 37: "L",
                                           38: "J", 40: "K", 43: ",", 47: "."]

    /// Caractère produit par la touche dans la disposition active (`UCKeyTranslate`).
    nonisolated static func systemTranslation(_ keyCode: UInt16) -> String? {
        #if os(macOS)
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        let maxLength = 4
        var characters = [UniChar](repeating: 0, count: maxLength)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, maxLength,
                                  &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
        #else
        return nil
        #endif
    }
}
