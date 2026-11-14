import Foundation

/// Court MP3 de test (story 2.2, CA8) : sinusoïde de 1 kHz, 1 s, mono, 44,1 kHz, 32 kbit/s, amplitude 0,5.
///
/// **Provenance et licence.** Contenu généré pour ScratchApp par l'équipe, sans aucune source tierce :
/// `ffmpeg -f lavfi -i "aevalsrc=0.5*sin(2*PI*1000*t):s=44100:d=1" -ac 1
/// -c:a libmp3lame -b:a 32k -map_metadata -1 -id3v2_version 0 -write_xing 1 -fflags +bitexact
/// -flags:a +bitexact sine1k.mp3`. Domaine public (CC0), aucune restriction d'usage.
/// 4 362 octets (crête décodée ≈ 0,48), SHA-256 `bb487a35e53dd9d2555cb55f97391b09f094f6d9b7d3068aeae0355dfffc04fa`.
enum MP3Fixture {
    /// Fréquence de la sinusoïde, en hertz.
    static let frequency = 1_000.0
    /// Fréquence d'échantillonnage du fichier.
    static let sampleRate = 44_100.0

    /// Octets du fichier MP3.
    static var data: Data {
        Data(base64Encoded: base64, options: .ignoreUnknownCharacters)!
    }

    /// Écrit le fichier dans `directory` et renvoie son URL.
    static func write(in directory: URL, name: String = "sine1k.mp3") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    // MARK: - MP3 de 10 min (#61)

    /// Répétitions des trames audio : 574 × 40 × 1 152 / 44 100 ≈ 599,8 s, sous la limite de 10 min
    /// (SF-80) ; 600 répétitions donneraient 627 s.
    static let tenMinuteRepetitions = 574
    /// Échantillons par trame MPEG-1 Layer III.
    static let samplesPerFrame = 1_152

    /// MP3 CBR d'environ 10 min, construit sans encodeur (méthode de la QA, #61) : les trames audio du
    /// fichier, sans la trame `Info` d'en-tête (qui annoncerait 1 s), répétées `repetitions` fois.
    static func tenMinutes(repetitions: Int = tenMinuteRepetitions) -> Data {
        let audio = frames(of: data).filter { !isInfoFrame($0) }
        var result = Data()
        result.reserveCapacity(audio.reduce(0) { $0 + $1.count } * repetitions)
        for _ in 0 ..< repetitions {
            for frame in audio { result.append(frame) }
        }
        return result
    }

    /// Trames MPEG-1 Layer III de `data`, dans l'ordre ; s'arrête au premier octet qui n'est pas un
    /// en-tête de trame.
    static func frames(of data: Data) -> [Data] {
        let bytes = [UInt8](data)
        let bitrates = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320] // kbit/s
        let sampleRates = [44_100, 48_000, 32_000]
        var frames: [Data] = []
        var offset = 0
        while offset + 4 <= bytes.count {
            // Sync, MPEG-1, Layer III (the CRC bit is ignored).
            guard bytes[offset] == 0xFF, bytes[offset + 1] & 0xFE == 0xFA else { break }
            let bitrateIndex = Int(bytes[offset + 2] >> 4)
            let rateIndex = Int((bytes[offset + 2] >> 2) & 0x3)
            guard (1 ..< bitrates.count).contains(bitrateIndex), rateIndex < sampleRates.count else { break }
            let padding = Int((bytes[offset + 2] >> 1) & 0x1)
            let length = 144 * bitrates[bitrateIndex] * 1_000 / sampleRates[rateIndex] + padding
            guard offset + length <= bytes.count else { break }
            frames.append(Data(bytes[offset ..< offset + length]))
            offset += length
        }
        return frames
    }

    /// Trame `Info` ou `Xing` (en-tête LAME, sans audio) : étiquette après les informations
    /// annexes, de 17 octets en mono et 32 sinon.
    static func isInfoFrame(_ frame: Data) -> Bool {
        let bytes = [UInt8](frame)
        guard bytes.count > 40 else { return false }
        let isMono = bytes[3] >> 6 == 0x3
        let tagOffset = 4 + (isMono ? 17 : 32)
        let tag = String(decoding: bytes[tagOffset ..< tagOffset + 4], as: UTF8.self)
        return tag == "Info" || tag == "Xing"
    }

    private static let base64 = """
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
FAzQDD0T1yPvUf//eoWBsoXO/jDzEDjc2zEiiuPL//sSxHwDxHgtJgBvwuCTBaUBv2FEQT8wkANjnNAShbdU7OIfsf//Hhomyxa7
QUOIUQGd/mGJaMcgg05gvAnHXJgIXLWO0yB7CqxMbrcSiLogQRFT4G4pgKSB4YjwE1mAQAPgBALQYAHF//sQxIGDxLAtJg37KiCQ
haUBr2VEq061mPfRTZETL1RyLWmBCJgpoYlUmD3wUa7JCpgZgzAACEdAGVXbdqMKnf//rtPLrseR4AwDkITGPRbGXX+H1Kameo/m
E4CqbIDB8K1Xs/4FxEP/+xLEhgPFPC0gDf9KIJuFpIGv6US7pN9ggLAQuFVFASlSeSUCwGHbpi4C1yFMmGyKSyRvCqDmGQeRV5fK
JLqSSdH5aXGNAuAiPB8QEG/Lkwy7/Ado6EoShKPkMJQOrwEgAjqhCEIx9pL/+xDEh4PEfC0oDXsqII4FpQGvYUQGASTkSJIFBeBT
wo7oroL/FUxBTUUzLjEwMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/7
EsSNA8TELSQAb+Lgk4WkwA34XFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVf/7EMSRgASELTgV14AhCw2qgzbQAFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV//sSxIeDxKgzBhzDAAgAADSA
AAAEVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVV
VVVVVVVVVVVVVVVV
"""
}
