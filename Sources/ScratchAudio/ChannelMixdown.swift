import AudioToolbox
import AVFoundation

/// Conversion des canaux d'un fichier en stéréo (SF-80 ; 6.15 « Lire un son mono », « Lire un son
/// multicanal »).
///
/// - **Mono** : dupliqué à niveau égal sur les deux canaux (sans atténuation).
/// - **Stéréo** : conservée telle quelle.
/// - **Multicanal** (ITU-R BS.775) : `L' = L + 0,707·C + 0,707·Ls`, `R' = R + 0,707·C + 0,707·Rs`,
///   LFE ignorée, puis division par la plus grande somme des coefficients (≈ 2,414 en 5.1) : la crête
///   du mixage réduit ne dépasse jamais la crête d'entrée. Les canaux sont identifiés par les
///   étiquettes du layout du fichier, jamais par leur position supposée ; sans layout exploitable,
///   l'ordre WAV/SMPTE (L R C LFE Ls Rs…) est pris par défaut.
struct ChannelMixdown: Equatable {
    enum Mode: Equatable {
        case mono, stereo, matrix
    }

    let channelCount: Int
    let mode: Mode
    /// Coefficients de chaque canal d'entrée vers la sortie gauche (déjà normalisés).
    let leftCoefficients: [Float]
    /// Coefficients de chaque canal d'entrée vers la sortie droite (déjà normalisés).
    let rightCoefficients: [Float]

    /// Gain des canaux centraux et arrière (−3 dB).
    static let surroundGain: Float = 0.707_106_78

    init(channelCount: Int, labels: [AudioChannelLabel]?) {
        precondition(channelCount > 0, "ChannelMixdown: no channel")
        self.channelCount = channelCount
        switch channelCount {
        case 1:
            mode = .mono
            leftCoefficients = [1]
            rightCoefficients = [1]
        case 2:
            mode = .stereo
            leftCoefficients = [1, 0]
            rightCoefficients = [0, 1]
        default:
            mode = .matrix
            var pairs = Self.matrix(labels: labels, channelCount: channelCount)
            var scale = max(pairs.reduce(Float(0)) { $0 + $1.left }, pairs.reduce(Float(0)) { $0 + $1.right })
            if scale <= 0 {
                // Only LFE channels: mix everything equally rather than output silence.
                pairs = Array(repeating: (left: 1, right: 1), count: channelCount)
                scale = Float(channelCount)
            }
            leftCoefficients = pairs.map { $0.left / scale }
            rightCoefficients = pairs.map { $0.right / scale }
        }
    }

    /// Écrit `frames` trames stéréo dans `left` et `right` à partir des canaux désentrelacés `channels`.
    func mix(_ channels: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int,
             left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        guard frames > 0 else { return }
        switch mode {
        case .mono:
            left.update(from: channels[0], count: frames)
            right.update(from: channels[0], count: frames)
        case .stereo:
            left.update(from: channels[0], count: frames)
            right.update(from: channels[1], count: frames)
        case .matrix:
            left.update(repeating: 0, count: frames)
            right.update(repeating: 0, count: frames)
            for channel in 0 ..< channelCount {
                let source = channels[channel]
                let leftGain = leftCoefficients[channel], rightGain = rightCoefficients[channel]
                if leftGain == 0, rightGain == 0 { continue }
                for frame in 0 ..< frames {
                    let value = source[frame]
                    left[frame] += leftGain * value
                    right[frame] += rightGain * value
                }
            }
        }
    }

    // MARK: - Labels

    /// Contribution d'un canal étiqueté aux sorties gauche et droite, avant normalisation ; `nil`
    /// pour une étiquette inconnue.
    static func coefficients(for label: AudioChannelLabel) -> (left: Float, right: Float)? {
        switch label {
        case kAudioChannelLabel_Left, kAudioChannelLabel_LeftCenter, kAudioChannelLabel_LeftWide,
             kAudioChannelLabel_LeftTotal:
            return (1, 0)
        case kAudioChannelLabel_Right, kAudioChannelLabel_RightCenter, kAudioChannelLabel_RightWide,
             kAudioChannelLabel_RightTotal:
            return (0, 1)
        case kAudioChannelLabel_Center, kAudioChannelLabel_Mono, kAudioChannelLabel_CenterSurround:
            return (surroundGain, surroundGain)
        case kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RearSurroundLeft,
             kAudioChannelLabel_LeftSurroundDirect:
            return (surroundGain, 0)
        case kAudioChannelLabel_RightSurround, kAudioChannelLabel_RearSurroundRight,
             kAudioChannelLabel_RightSurroundDirect:
            return (0, surroundGain)
        case kAudioChannelLabel_LFEScreen, kAudioChannelLabel_LFE2:
            return (0, 0)
        default:
            return nil
        }
    }

    private static func matrix(labels: [AudioChannelLabel]?, channelCount: Int) -> [(left: Float, right: Float)] {
        if let labels, labels.count == channelCount {
            let known = labels.map(coefficients(for:))
            if known.contains(where: { $0 != nil }) {
                // Unknown channels (height, discrete…) go to both sides at half level.
                return known.map { $0 ?? (left: 0.5, right: 0.5) }
            }
        }
        return defaultLabels(channelCount).map { coefficients(for: $0) ?? (left: 0.5, right: 0.5) }
    }

    /// Ordre WAV/SMPTE, pris seulement quand le fichier ne décrit pas ses canaux.
    private static func defaultLabels(_ count: Int) -> [AudioChannelLabel] {
        let order: [AudioChannelLabel] = [
            kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_Center, kAudioChannelLabel_LFEScreen,
            kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround,
            kAudioChannelLabel_RearSurroundLeft, kAudioChannelLabel_RearSurroundRight,
        ]
        return (0 ..< count).map { $0 < order.count ? order[$0] : kAudioChannelLabel_Unknown }
    }

    /// Étiquettes des canaux décrits par un layout (descriptions explicites, masque de bits ou tag
    /// développé par AudioToolbox) ; `nil` si le layout est absent ou ne décrit pas ses canaux.
    static func labels(of layout: AVAudioChannelLayout?) -> [AudioChannelLabel]? {
        guard let layout else { return nil }
        let tag = layout.layoutTag
        if tag == kAudioChannelLayoutTag_UseChannelDescriptions {
            return descriptionLabels(layout.layout)
        }
        if tag == kAudioChannelLayoutTag_UseChannelBitmap {
            var bitmap = layout.layout.pointee.mChannelBitmap.rawValue
            return expandedLabels(property: kAudioFormatProperty_ChannelLayoutForBitmap, specifier: &bitmap)
        }
        var specifier = tag
        return expandedLabels(property: kAudioFormatProperty_ChannelLayoutForTag, specifier: &specifier)
    }

    private static func expandedLabels(property: AudioFormatPropertyID, specifier: inout UInt32) -> [AudioChannelLabel]? {
        let specifierSize = UInt32(MemoryLayout<UInt32>.size)
        var size: UInt32 = 0
        guard AudioFormatGetPropertyInfo(property, specifierSize, &specifier, &size) == noErr,
              Int(size) >= MemoryLayout<AudioChannelLayout>.size
        else { return nil }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                       alignment: MemoryLayout<AudioChannelLayout>.alignment)
        defer { storage.deallocate() }
        guard AudioFormatGetProperty(property, specifierSize, &specifier, &size, storage) == noErr else { return nil }
        return descriptionLabels(UnsafePointer(storage.bindMemory(to: AudioChannelLayout.self, capacity: 1)))
    }

    private static func descriptionLabels(_ layout: UnsafePointer<AudioChannelLayout>) -> [AudioChannelLabel]? {
        let count = Int(layout.pointee.mNumberChannelDescriptions)
        guard count > 0 else { return nil }
        let offset = MemoryLayout<AudioChannelLayout>.offset(of: \AudioChannelLayout.mChannelDescriptions) ?? 12
        let first = (UnsafeRawPointer(layout) + offset).assumingMemoryBound(to: AudioChannelDescription.self)
        return (0 ..< count).map { first[$0].mChannelLabel }
    }
}
