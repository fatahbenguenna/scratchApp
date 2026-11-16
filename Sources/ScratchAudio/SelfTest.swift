import AVFoundation
import Foundation
import ScratchCore
import ScratchLibrary

/// Auto-test hors ligne du pipeline audio complet, lancé par `ScratchApp --selftest` dans la CI
/// (story 2.4 ; architecture §9.3 ; spec §7, P0).
///
/// Le graphe réel de l'app — la fabrique partagée `ScratchAudioGraph` de la story 2.1 : un
/// `AVAudioSourceNode` stéréo Float32 désentrelacé qui appelle `ScratchEngine.render`, branché
/// directement sur la sortie — est rendu en **mode manuel hors ligne** d'`AVAudioEngine`, à 48 kHz,
/// par tranches de 256 trames, à l'échantillon près comme le rendu direct : aucun périphérique de sortie n'est
/// nécessaire (runners de CI). Il joue `ScratchScenario` (story 1.5) avec le son de démonstration
/// sur A et sur B et publie les vérifications nommées de `ScratchScenario.checkNames`, plus
/// `renderedThroughAVAudioEngine`.
///
/// La sortie standard de l'app ne contient que le rapport JSON (`ScratchAppMain`) ; le code de retour
/// est non nul si une vérification échoue.
public enum SelfTest {
    public struct Report: Codable, Sendable {
        public var passed: Bool
        public var checks: [String: Bool]
        public var details: [String: Double]
    }

    /// Taille des tranches de rendu : celle des tampons du scénario (mêmes frontières de commandes).
    public static let sliceFrames = 256

    /// Joue le scénario de scratch complet. `clip` remplace le son de démonstration (tests).
    public static func run(sampleRate: Double = 48_000, clip: AudioClip? = nil) throws -> Report {
        let started = Date()
        let sound = clip ?? DemoSound.makeClip()
        let engine = ScratchEngine(outputSampleRate: sampleRate)
        let scenario = ScratchScenario(clipA: sound, clipB: sound, sampleRate: sampleRate, blockFrames: sliceFrames)

        let graph = try ScratchAudioGraph.offline(engine: engine, sampleRate: sampleRate, maximumFrameCount: 512)
        let audioEngine = graph.avEngine
        try audioEngine.start()
        defer { audioEngine.stop() }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: audioEngine.manualRenderingFormat,
                                            frameCapacity: audioEngine.manualRenderingMaximumFrameCount),
              audioEngine.manualRenderingFormat.channelCount == 2,
              !audioEngine.manualRenderingFormat.isInterleaved else {
            throw NSError(domain: "ScratchAudio.SelfTest", code: 2)
        }

        var analyzer = scenario.makeAnalyzer()
        var frame: Int64 = 0
        var rendered = true
        while frame < scenario.totalFrames {
            for command in scenario.events(forBlockStartingAt: frame) { engine.send(command) }
            let count = Int(min(Int64(sliceFrames), scenario.totalFrames - frame))
            let status = try audioEngine.renderOffline(AVAudioFrameCount(count), to: buffer)
            guard status == .success, Int(buffer.frameLength) == count, let channels = buffer.floatChannelData else {
                rendered = false
                break
            }
            analyzer.consume(frame: frame, left: channels[0], right: channels[1], count: count,
                             snapshot: engine.latestSnapshot())
            engine.drainReleasedClips()
            frame += Int64(count)
        }

        let scenarioReport = analyzer.report()
        var checks = scenarioReport.checks
        checks["renderedThroughAVAudioEngine"] = rendered && frame == scenario.totalFrames
        var details = scenarioReport.details
        details["framesRendered"] = Double(frame)
        details["durationSeconds"] = Date().timeIntervalSince(started)
        // JSON cannot carry non-finite numbers: a measurement that never happened is reported as −1.
        details = details.mapValues { $0.isFinite ? $0 : -1 }
        let passed = ScratchScenario.checkNames.allSatisfy { checks[$0] == true }
            && checks["renderedThroughAVAudioEngine"] == true
        return Report(passed: passed, checks: checks, details: details)
    }
}
