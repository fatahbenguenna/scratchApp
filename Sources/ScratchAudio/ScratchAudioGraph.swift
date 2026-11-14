import AVFoundation
import ScratchCore

/// Graphe audio de ScratchApp (story 2.1 ; ADR-02, architecture §3.1, §6.1) : un `AVAudioSourceNode`
/// stéréo Float32 désentrelacé, branché directement sur la sortie, appelle
/// `ScratchEngine.render(frameCount:left:right:)`.
///
/// Fabrique partagée par la sortie temps réel (`AudioEngineHost`) et par le rendu manuel hors ligne
/// (tests, self-test 2.4, sonde de latence). Le même moteur produit alors la même sortie, à
/// l'échantillon près.
final class ScratchAudioGraph {
    let avEngine: AVAudioEngine
    let sourceNode: AVAudioSourceNode
    let format: AVAudioFormat

    /// Format du rendu : Float32 stéréo désentrelacé.
    static func renderFormat(sampleRate: Double) -> AVAudioFormat? {
        guard sampleRate.isFinite, sampleRate > 0 else { return nil }
        return AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false)
    }

    /// Branche le moteur sur `avEngine`, à `sampleRate` (fréquence matérielle, ou celle du rendu
    /// manuel).
    init(engine: ScratchEngine, sampleRate: Double, avEngine: AVAudioEngine) throws {
        guard let format = Self.renderFormat(sampleRate: sampleRate) else { throw AudioOutputError.invalidFormat }
        let node = AVAudioSourceNode(format: format, renderBlock: Self.renderBlock(for: engine))
        avEngine.attach(node)
        avEngine.connect(node, to: avEngine.outputNode, format: format)
        self.avEngine = avEngine
        self.sourceNode = node
        self.format = format
    }

    /// Graphe en rendu manuel hors ligne (`renderOffline`), à `sampleRate`, par tranches de
    /// `maximumFrameCount` trames au plus. À démarrer avec `avEngine.start()`.
    static func offline(engine: ScratchEngine, sampleRate: Double = 48_000,
                        maximumFrameCount: AVAudioFrameCount = AVAudioFrameCount(ScratchEngine.maximumBlockFrames))
        throws -> ScratchAudioGraph {
        guard let format = renderFormat(sampleRate: sampleRate) else { throw AudioOutputError.invalidFormat }
        let avEngine = AVAudioEngine()
        try avEngine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: maximumFrameCount)
        return try ScratchAudioGraph(engine: engine, sampleRate: sampleRate, avEngine: avEngine)
    }

    /// Bloc de rendu, créé une seule fois par graphe (architecture §6.1). Il ne fait que lire les
    /// deux pointeurs de l'`AudioBufferList` et appeler le moteur : aucune allocation, aucun verrou,
    /// aucun appel Objective-C, aucune journalisation.
    static func renderBlock(for engine: ScratchEngine) -> AVAudioSourceNodeRenderBlock {
        { _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            engine.render(frameCount: Int(frameCount), left: left, right: right)
            return noErr
        }
    }
}

/// Erreurs de démarrage de la sortie audio (`AudioEngineHost` les traduit en `.unavailable`).
enum AudioOutputError: Error, Equatable {
    /// Aucune sortie audio (pas de périphérique, ou format matériel invalide).
    case noOutput
    /// Format de rendu impossible à construire.
    case invalidFormat
    /// La sonde de latence n'a observé aucune réponse du disque.
    case noResponse

    /// Motif affiché dans le diagnostic de la sortie (`AudioOutputStatus.unavailable`).
    var reason: String {
        switch self {
        case .noOutput: return "Aucune sortie audio disponible."
        case .invalidFormat: return "Format de sortie audio non pris en charge."
        case .noResponse: return "Aucune réponse du moteur à la sonde de latence."
        }
    }
}
