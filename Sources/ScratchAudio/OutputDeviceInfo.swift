import Foundation
#if os(macOS)
import CoreAudio
#endif

/// Nature d'une sortie audio, pour son libellé (UX §5.17).
enum OutputPortKind: Equatable, Sendable {
    /// iOS : haut-parleur intégré.
    case builtInSpeaker
    /// iOS : casque filaire.
    case headphones
    case bluetooth
    case usb
    case hdmi
    case airPlay
    /// Autre sortie (macOS : périphérique nommé par le système).
    case other
}

/// Libellés de la sortie audio (story 2.1 CA 7 ; UX §5.17), en logique pure.
///
/// - iOS : « Haut-parleur », « Casque », nom de l'appareil Bluetooth.
/// - macOS : nom fourni par le système.
/// - Partout : « <nom> (USB) », « <nom> (HDMI) », « <nom> (AirPlay) ».
enum OutputNaming {
    static func displayName(kind: OutputPortKind, systemName: String) -> String {
        let name = systemName.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .builtInSpeaker: return "Haut-parleur"
        case .headphones: return "Casque"
        case .usb: return tagged(name, "USB")
        case .hdmi: return tagged(name, "HDMI")
        case .airPlay: return tagged(name, "AirPlay")
        case .bluetooth, .other: return name.isEmpty ? "Sortie audio" : name
        }
    }

    private static func tagged(_ name: String, _ tag: String) -> String {
        let base = name.isEmpty ? "Sortie audio" : name
        return base.hasSuffix("(\(tag))") ? base : "\(base) (\(tag))"
    }

    #if os(macOS)
    /// macOS : type de transport Core Audio → nature de la sortie. Les sorties intégrées gardent le
    /// nom du système (« Haut-parleurs MacBook Pro »).
    static func kind(forTransportType transport: UInt32) -> OutputPortKind {
        switch transport {
        case kAudioDeviceTransportTypeUSB: return .usb
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .hdmi
        case kAudioDeviceTransportTypeAirPlay: return .airPlay
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        default: return .other
        }
    }
    #endif
}

#if os(macOS)
/// Périphérique de sortie par défaut du système (Core Audio), que suit `AVAudioEngine` sur macOS
/// (story 2.1 CA 2, CA 4, CA 7).
struct OutputDevice {
    let id: AudioObjectID

    static func defaultOutput() -> OutputDevice? {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        guard status == noErr, id != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return OutputDevice(id: id)
    }

    /// Nom fourni par le système.
    var name: String? {
        var address = Self.address(kAudioObjectPropertyName)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &name) { pointer in
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let name else { return nil }
        return name.takeRetainedValue() as String
    }

    var transportType: UInt32? { value(kAudioDevicePropertyTransportType) }

    /// Taille de tampon effective, en trames (relue, jamais la valeur demandée).
    var bufferFrameSize: UInt32? { value(kAudioDevicePropertyBufferFrameSize) }

    /// Fréquence réelle mesurée par le système pendant que la sortie tourne, en hertz : elle s'écarte
    /// de la fréquence nominale selon la dérive de l'horloge du périphérique (#129).
    var actualSampleRate: Double? {
        var address = Self.address(kAudioDevicePropertyActualSampleRate)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &rate) == noErr, rate > 0 else { return nil }
        return rate
    }

    /// Demande `frames` trames par tampon, ramenées à la plage du périphérique. Renvoie le tampon
    /// effectif relu, ou `nil` si le périphérique refuse la demande.
    @discardableResult
    func requestBufferFrameSize(_ frames: UInt32) -> UInt32? {
        var address = Self.address(kAudioDevicePropertyBufferFrameSizeRange)
        var range = AudioValueRange()
        var size = UInt32(MemoryLayout<AudioValueRange>.size)
        var wanted = frames
        if AudioObjectGetPropertyData(id, &address, 0, nil, &size, &range) == noErr, range.mMaximum >= range.mMinimum {
            wanted = UInt32(min(max(Double(frames), range.mMinimum), range.mMaximum))
        }
        var sizeAddress = Self.address(kAudioDevicePropertyBufferFrameSize)
        guard AudioObjectSetPropertyData(id, &sizeAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &wanted) == noErr
        else { return nil }
        return bufferFrameSize
    }

    /// Libellé de la sortie (UX §5.17).
    var displayName: String {
        OutputNaming.displayName(kind: transportType.map(OutputNaming.kind(forTransportType:)) ?? .other,
                                 systemName: name ?? "")
    }

    private func value(_ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = Self.address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}
#endif
