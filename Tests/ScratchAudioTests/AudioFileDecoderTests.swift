import AudioToolbox
import AVFoundation
import Foundation
import ScratchCore
import XCTest
@testable import ScratchAudio

/// Décodeur AVFoundation (story 2.2) : fichiers générés pendant le test dans un dossier temporaire
/// unique, plus un court MP3 libre de droits versionné (`MP3Fixture`).
final class AudioFileDecoderTests: XCTestCase {
    private var directory: URL!
    private let decoder = AudioFileDecoder()

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("decoder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Helpers

    private func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    @discardableResult
    private func writeSine(_ name: String, encoding: AudioFixtureWriter.Encoding = .pcm16, sampleRate: Double = 44_100,
                           channels: Int = 2, seconds: Double = 1, frequency: Double = 1_000,
                           amplitude: Float = 0.5) throws -> URL {
        let file = url(name)
        try AudioFixtureWriter.write(
            to: file, encoding: encoding, sampleRate: sampleRate, channels: channels,
            frames: Int((seconds * sampleRate).rounded()),
            layoutTag: channels > 2 ? kAudioChannelLayoutTag_MPEG_5_1_A : nil,
            signal: AudioFixtureWriter.sine(frequency: frequency, amplitude: amplitude, sampleRate: sampleRate))
        return file
    }

    private func assertError(_ expected: LibraryError, _ message: String = "", file: StaticString = #filePath,
                             line: UInt = #line, _ body: () async throws -> Void) async {
        do {
            try await body()
            XCTFail("expected \(expected) \(message)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? LibraryError, expected, message, file: file, line: line)
        }
    }

    /// Fréquence mesurée par les passages par zéro montants (interpolés), entre 10 % et 90 % du clip.
    private static func measuredFrequency(_ samples: UnsafeBufferPointer<Float>, sampleRate: Double) -> Double {
        var first: Double?, last = 0.0, crossings = 0
        let start = max(1, samples.count / 10), end = samples.count * 9 / 10
        for index in start ..< end {
            let a = samples[index - 1], b = samples[index]
            guard a < 0, b >= 0 else { continue }
            let time = Double(index - 1) + Double(-a / (b - a))
            if first == nil { first = time }
            last = time
            crossings += 1
        }
        guard let first, crossings > 2, last > first else { return 0 }
        return Double(crossings - 1) * sampleRate / (last - first)
    }

    private static func peak(_ samples: UnsafeBufferPointer<Float>) -> Float {
        samples.reduce(Float(0)) { max($0, $1.magnitude) }
    }

    // MARK: - Formats (CA1, CA2)

    /// CA1, CA2 — SF-02, scénario « Format compatible » : WAV, AIFF, M4A (AAC), M4A (ALAC) et MP3
    /// sont sondés (1 s) puis décodés en stéréo, à la fréquence native, à 1 kHz ± 1 Hz.
    /// Codecs avec pertes : la durée tolère le délai et le remplissage du codeur (75 ms).
    func testCompatibleFormatsDecode_SF02() async throws {
        let cases: [(name: String, encoding: AudioFixtureWriter.Encoding?, durationTolerance: Double)] = [
            ("sine.wav", .pcm16, 1 / 44_100),
            ("sine.aiff", .pcm16, 1 / 44_100),
            ("sine-aac.m4a", .aac, 0.075),
            ("sine-alac.m4a", .alac, 1 / 44_100),
            ("sine1k.mp3", nil, 0.075),
        ]
        for testCase in cases {
            let file: URL
            if let encoding = testCase.encoding {
                file = try writeSine(testCase.name, encoding: encoding)
            } else {
                file = try MP3Fixture.write(in: directory, name: testCase.name)
            }
            let info = try await decoder.probe(url: file)
            XCTAssertEqual(info.duration, 1, accuracy: testCase.durationTolerance, testCase.name)
            XCTAssertEqual(info.sampleRate, 44_100, testCase.name)
            XCTAssertEqual(info.channelCount, testCase.encoding == nil ? 1 : 2, testCase.name)

            let clip = try await decoder.decode(url: file, title: "voix_funk_2")
            XCTAssertEqual(clip.title, "voix_funk_2", testCase.name)
            XCTAssertEqual(clip.sampleRate, 44_100, testCase.name)
            XCTAssertEqual(clip.duration, info.duration, accuracy: 1 / 44_100, testCase.name)
            for (side, channel) in [("left", clip.left), ("right", clip.right)] {
                XCTAssertEqual(Self.measuredFrequency(channel, sampleRate: clip.sampleRate), 1_000, accuracy: 1,
                               "\(testCase.name) \(side)")
                XCTAssertEqual(Self.peak(channel), 0.5, accuracy: 0.1, "\(testCase.name) \(side)")
                XCTAssertTrue(channel.allSatisfy(\.isFinite), "\(testCase.name) \(side)")
            }
        }
        let byFileName = try await decoder.decode(url: url("sine.wav"))
        XCTAssertEqual(byFileName.title, "sine", "default title: file name without extension")
    }

    // MARK: - Channels (CA3)

    /// CA3 — SF-80, 6.15 « Lire un son mono » : le mono est dupliqué à niveau égal (sans atténuation).
    func testMonoIsDuplicatedAtEqualLevel_SF80() async throws {
        let file = try writeSine("mono.wav", encoding: .float32, channels: 1)
        let info = try await decoder.probe(url: file)
        XCTAssertEqual(info.channelCount, 1)
        let clip = try await decoder.decode(url: file, title: "mono")
        XCTAssertTrue(clip.left.elementsEqual(clip.right) { $0.bitPattern == $1.bitPattern })
        XCTAssertEqual(Self.peak(clip.left), 0.5, accuracy: 0.001)
        XCTAssertEqual(Self.measuredFrequency(clip.right, sampleRate: clip.sampleRate), 1_000, accuracy: 1)
    }

    /// CA3 — SF-80, 6.15 « Lire un son multicanal » : un 5.1 à 0 dBFS sur tous les canaux est réduit
    /// en stéréo sans dépasser la crête d'entrée.
    func testSurroundIsDownmixedWithoutClipping_SF80() async throws {
        let file = try writeSine("surround.wav", encoding: .float32, sampleRate: 48_000, channels: 6, amplitude: 1)
        let info = try await decoder.probe(url: file)
        XCTAssertEqual(info.channelCount, 6)
        let clip = try await decoder.decode(url: file, title: "5.1")
        for channel in [clip.left, clip.right] {
            XCTAssertLessThanOrEqual(Self.peak(channel), 1.000_01)
            XCTAssertGreaterThan(Self.peak(channel), 0.99)
            XCTAssertEqual(Self.measuredFrequency(channel, sampleRate: clip.sampleRate), 1_000, accuracy: 1)
        }
    }

    /// CA3 : les canaux sont identifiés par le layout du fichier (L R C LFE Ls Rs), la LFE est
    /// ignorée et les coefficients d'ITU-R BS.775 sont normalisés par leur somme.
    func testSurroundChannelsAreIdentifiedByTheFileLayout_SF80() async throws {
        let levels: [Float] = [0.1, 0.2, 0.3, 0.9, 0.4, 0.5] // L R C LFE Ls Rs (MPEG 5.1 A)
        let file = url("dc.wav")
        try AudioFixtureWriter.write(to: file, encoding: .float32, sampleRate: 48_000, channels: 6, frames: 4_800,
                                     layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A) { channel, _ in levels[channel] }
        let clip = try await decoder.decode(url: file, title: "dc")
        let g = ChannelMixdown.surroundGain, scale = 1 + 2 * g
        XCTAssertEqual(clip.left[2_400], (0.1 + g * 0.3 + g * 0.4) / scale, accuracy: 1e-4)
        XCTAssertEqual(clip.right[2_400], (0.2 + g * 0.3 + g * 0.5) / scale, accuracy: 1e-4)
    }

    /// CA3 : matrice de réduction, développement des layouts par AudioToolbox, repli sans layout.
    func testDownmixMatrixFollowsITUBS775() {
        let mpeg51A = ChannelMixdown.labels(of: AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A))
        XCTAssertEqual(mpeg51A, [kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_Center,
                                 kAudioChannelLabel_LFEScreen, kAudioChannelLabel_LeftSurround,
                                 kAudioChannelLabel_RightSurround])
        let mpeg51C = ChannelMixdown.labels(of: AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_C))
        XCTAssertEqual(mpeg51C, [kAudioChannelLabel_Left, kAudioChannelLabel_Center, kAudioChannelLabel_Right,
                                 kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround,
                                 kAudioChannelLabel_LFEScreen])

        let g = ChannelMixdown.surroundGain, scale = 1 + 2 * g
        let reordered = ChannelMixdown(channelCount: 6, labels: mpeg51C)
        XCTAssertEqual(reordered.mode, .matrix)
        let expectedLeft: [Float] = [1, g, 0, g, 0, 0].map { $0 / scale }
        let expectedRight: [Float] = [0, g, 1, 0, g, 0].map { $0 / scale }
        for index in 0 ..< 6 {
            XCTAssertEqual(reordered.leftCoefficients[index], expectedLeft[index], accuracy: 1e-6)
            XCTAssertEqual(reordered.rightCoefficients[index], expectedRight[index], accuracy: 1e-6)
        }
        XCTAssertEqual(ChannelMixdown(channelCount: 6, labels: nil),
                       ChannelMixdown(channelCount: 6, labels: mpeg51A), "WAV/SMPTE order without a layout")
        XCTAssertEqual(ChannelMixdown(channelCount: 1, labels: nil).mode, .mono)
        XCTAssertEqual(ChannelMixdown(channelCount: 2, labels: nil).mode, .stereo)

        // Every channel at full scale: the downmix never exceeds the input peak.
        let frames = 8
        let inputs = (0 ..< 6).map { _ -> UnsafeMutablePointer<Float> in
            let channel = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            channel.initialize(repeating: 1, count: frames)
            return channel
        }
        let left = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let right = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        left.initialize(repeating: 0, count: frames)
        right.initialize(repeating: 0, count: frames)
        defer {
            inputs.forEach { $0.deallocate() }
            left.deallocate()
            right.deallocate()
        }
        inputs.withUnsafeBufferPointer { channels in
            reordered.mix(channels.baseAddress!, frames: frames, left: left, right: right)
        }
        let output = Array(UnsafeBufferPointer(start: left, count: frames))
            + Array(UnsafeBufferPointer(start: right, count: frames))
        XCTAssertTrue(output.allSatisfy { $0 <= 1.000_001 && $0 > 0.999 }, "\(output)")
    }

    // MARK: - Sample rates (CA4)

    /// CA4 — D-21, D-22, 6.15 : de 22,05 à 48 kHz, la fréquence native est conservée (la voix
    /// rééchantillonne vers la sortie) et la hauteur est intacte.
    func testNativeRateKeptUpTo48kHz_D21() async throws {
        for rate in [22_050.0, 44_100, 48_000] {
            let file = try writeSine("native-\(Int(rate)).wav", sampleRate: rate)
            let clip = try await decoder.decode(url: file, title: "native")
            XCTAssertEqual(clip.sampleRate, rate)
            XCTAssertEqual(clip.frameCount, Int(rate))
            XCTAssertEqual(Self.measuredFrequency(clip.left, sampleRate: clip.sampleRate), 1_000, accuracy: 1, "\(rate)")
        }
    }

    /// CA4 — D-21, scénario « 96 kHz converti à 48 kHz » : 88,2 et 96 kHz deviennent 48 kHz, hauteur
    /// et niveau conservés ; la sonde donne la fréquence native.
    func test96kHzConvertedTo48kHz_D21() async throws {
        for rate in [88_200.0, 96_000] {
            let file = try writeSine("high-\(Int(rate)).wav", sampleRate: rate)
            let info = try await decoder.probe(url: file)
            XCTAssertEqual(info.sampleRate, rate)
            let clip = try await decoder.decode(url: file, title: "high")
            XCTAssertEqual(clip.sampleRate, 48_000)
            XCTAssertEqual(clip.frameCount, 48_000)
            for channel in [clip.left, clip.right] {
                XCTAssertEqual(Self.measuredFrequency(channel, sampleRate: 48_000), 1_000, accuracy: 1, "\(rate)")
                XCTAssertTrue(channel.allSatisfy(\.isFinite))
                XCTAssertEqual(Self.peak(channel), 0.5, accuracy: 0.02, "\(rate)")
            }
        }
    }

    // MARK: - Durations (CA5)

    /// CA5 — SF-80, 6.1 « Importer un fichier trop long » : la sonde refuse 25 min (`tooLong`) et
    /// 40 ms (`tooShort`) sans décoder ; 50 ms est accepté.
    func testProbeRejectsTooLongAndTooShort_SF80() async throws {
        let long = try writeSine("long.wav", sampleRate: 8_000, channels: 1, seconds: 25 * 60)
        let start = Date()
        await assertError(.tooLong(duration: 1_500)) { _ = try await decoder.probe(url: long) }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2, "the probe does not decode")
        await assertError(.tooLong(duration: 1_500)) { _ = try await decoder.decode(url: long, title: "long") }

        let short = try writeSine("short.wav", seconds: 0.04)
        do {
            _ = try await decoder.probe(url: short)
            XCTFail("40 ms is too short")
        } catch let LibraryError.tooShort(duration) {
            XCTAssertEqual(duration, 0.04, accuracy: 1e-9)
        }
        let minimum = try writeSine("minimum.wav", seconds: 0.05)
        let info = try await decoder.probe(url: minimum)
        XCTAssertEqual(info.duration, 0.05, accuracy: 1e-9)
    }

    // MARK: - Errors (CA6)

    /// CA6 — 6.1 « Importer un fichier incompatible » : un fichier non audio est refusé.
    func testNonAudioFileIsUnsupported() async throws {
        let text = url("notes.wav")
        try Data("Ceci n'est pas un son.".utf8).write(to: text)
        let pdf = url("document.pdf")
        try Data("%PDF-1.4\n1 0 obj << /Type /Catalog >> endobj\n%%EOF\n".utf8).write(to: pdf)
        for file in [text, pdf] {
            await assertError(.unsupportedFormat, file.lastPathComponent) { _ = try await decoder.probe(url: file) }
            await assertError(.unsupportedFormat, file.lastPathComponent) {
                _ = try await decoder.decode(url: file, title: "x")
            }
        }
    }

    /// CA6 — 6.1 « Importer un fichier corrompu ou vide », scénario « Fichier tronqué » : WAV et
    /// AIFF privés de leurs derniers 40 %, fichier de taille nulle, en-tête sans trame, fichier absent.
    func testTruncatedAndEmptyFilesAreCorrupted() async throws {
        var files: [URL] = []
        for name in ["cut.wav", "cut.aiff"] {
            let file = try writeSine(name)
            let bytes = try Data(contentsOf: file)
            try bytes.prefix(Int(Double(bytes.count) * 0.6)).write(to: file)
            files.append(file)
        }
        let empty = url("empty.wav")
        try Data().write(to: empty)
        let headerOnly = url("header-only.wav")
        try AudioFixtureWriter.write(to: headerOnly, encoding: .pcm16, sampleRate: 44_100, channels: 2, frames: 0) { _, _ in 0 }
        for file in files {
            let size = UInt64(try Data(contentsOf: file).count)
            XCTAssertEqual(AudioContainerIntegrity.status(at: file, fileSize: size), .truncated, file.lastPathComponent)
        }
        let headerOnlySize = UInt64(try Data(contentsOf: headerOnly).count)
        XCTAssertEqual(AudioContainerIntegrity.status(at: headerOnly, fileSize: headerOnlySize), .empty)
        let intact = try writeSine("intact.wav")
        let intactSize = UInt64(try Data(contentsOf: intact).count)
        XCTAssertEqual(AudioContainerIntegrity.status(at: intact, fileSize: intactSize), .complete)

        files += [empty, headerOnly, url("missing.wav")]
        for file in files {
            await assertError(.corrupted, file.lastPathComponent) { _ = try await decoder.probe(url: file) }
            await assertError(.corrupted, file.lastPathComponent) { _ = try await decoder.decode(url: file, title: "x") }
        }
    }

    /// CA6, CA8 — 6.1 « Importer un fichier protégé » : la détection injectée signale un contenu
    /// protégé → `protectedContent`, sans décodage ; la détection réelle accepte un WAV.
    func testProtectedContentIsRejected() async throws {
        struct AlwaysProtected: ProtectedContentChecking {
            func isProtected(_ url: URL) async -> Bool { true }
        }
        let file = try writeSine("drm.wav")
        let protectedDecoder = AudioFileDecoder(protectedContent: AlwaysProtected())
        await assertError(.protectedContent) { _ = try await protectedDecoder.probe(url: file) }
        await assertError(.protectedContent) { _ = try await protectedDecoder.decode(url: file, title: "drm") }
        let detected = await AssetProtectedContentChecker().isProtected(file)
        XCTAssertFalse(detected)
        _ = try await decoder.probe(url: file)
    }

    // MARK: - Cancellation and performance (CA7)

    /// CA7 : un décodage annulé lève `CancellationError` (pas une `LibraryError`) et ne rend aucun clip.
    func testDecodeIsCancellable() async throws {
        let file = try writeSine("long-enough.wav", seconds: 20)
        let decoder = self.decoder
        let task = Task { () async throws -> AudioClip in
            while !Task.isCancelled { await Task.yield() }
            return try await decoder.decode(url: file, title: "cancelled")
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("a cancelled decode must not return a clip")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
    }

    /// CA5, CA7 : un son de 10 min (600 s, limite acceptée) est sondé puis décodé ; mesure indicative.
    /// L'objectif de 3 s vaut pour un MP3 en configuration optimisée sur Mac Apple Silicon ; les
    /// tests tournent en débogage sur un exécuteur partagé : borne large de 15 s.
    func testTenMinuteDecodeTime() async throws {
        let file = try writeSine("ten-minutes.wav", seconds: 600)
        let info = try await decoder.probe(url: file)
        XCTAssertEqual(info.duration, 600, accuracy: 1e-9)
        let start = Date()
        let clip = try await decoder.decode(url: file, title: "dix minutes")
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(clip.frameCount, 26_460_000)
        XCTAssertEqual(clip.left[clip.frameCount - 11], clip.right[clip.frameCount - 11])
        XCTAssertLessThan(elapsed, 15, "indicative bound in debug; target 3 s in release")
        DecodeMetricsLog.write(String(format: "2.2 CA 7 — WAV de 10 min (44,1 kHz, stéréo, 16 bits) décodé en %.2f s (build %@)",
                                      elapsed, DecodeMetricsLog.configuration))
    }

    /// CA 7 — #61 : un vrai MP3 de 10 min, construit sans encodeur à partir de la fixture (méthode de
    /// la QA) : ses 40 trames audio de 32 kbit/s en mono, sans la trame `Info`, répétées 574 fois
    /// (599,8 s, sous la limite de SF-80). AudioToolbox le décode ; l'objectif est de 3 s en release
    /// sur Mac Apple Silicon, et la borne de la CI est de 6 s. La durée figure dans le rapport CI.
    func testTenMinuteMP3DecodeTime() async throws {
        let frames = MP3Fixture.frames(of: MP3Fixture.data)
        XCTAssertEqual(frames.count, 41, "Info frame, then 40 audio frames")
        XCTAssertEqual(frames.map(\.count).reduce(0, +), MP3Fixture.data.count, "the whole fixture is parsed")
        XCTAssertTrue(MP3Fixture.isInfoFrame(frames[0]))
        XCTAssertFalse(frames.dropFirst().contains(where: MP3Fixture.isInfoFrame))

        let file = url("ten-minutes.mp3")
        try MP3Fixture.tenMinutes().write(to: file)
        let expected = Double(MP3Fixture.tenMinuteRepetitions * 40 * MP3Fixture.samplesPerFrame) / MP3Fixture.sampleRate
        let info = try await decoder.probe(url: file)
        XCTAssertEqual(info.duration, expected, accuracy: 0.5)
        XCTAssertLessThanOrEqual(info.duration, 600, "SF-80")

        let start = Date()
        let clip = try await decoder.decode(url: file, title: "dix minutes")
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(clip.sampleRate, MP3Fixture.sampleRate)
        XCTAssertEqual(Double(clip.frameCount) / clip.sampleRate, expected, accuracy: 0.5)
        let middle = clip.frameCount / 2
        XCTAssertEqual(clip.left[middle], clip.right[middle], "mono on both channels")
        let peak = (middle ..< middle + 4_410).map { abs(clip.left[$0]) }.max() ?? 0
        XCTAssertGreaterThan(peak, 0.3, "the sine is decoded all the way through")
        XCTAssertLessThan(elapsed, 6, "CI bound; target 3 s in release (CA 7)")
        DecodeMetricsLog.write(String(format: "2.2 CA 7 — MP3 de 10 min (%.1f s, 32 kbit/s, mono) décodé en %.2f s (build %@)",
                                      Double(clip.frameCount) / clip.sampleRate, elapsed, DecodeMetricsLog.configuration))
    }
}
