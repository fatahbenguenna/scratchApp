import Foundation

/// Court MP3 de test (story 2.2, CA8) : sinusoïde de 1 kHz, 1 s, mono, 44,1 kHz, 32 kbit/s, amplitude 0,5.
///
/// **Provenance et licence.** Contenu généré pour ScratchApp par l'équipe, sans aucune source tierce :
/// `ffmpeg -f lavfi -i "sine=frequency=1000:sample_rate=44100:duration=1" -af volume=0.5 -ac 1
/// -c:a libmp3lame -b:a 32k -map_metadata -1 -id3v2_version 0 -write_xing 1 -fflags +bitexact
/// -flags:a +bitexact sine1k.mp3`. Domaine public (CC0), aucune restriction d'usage.
/// 4 362 octets, SHA-256 `8803f7707c58d023cffee5683c0ee592c98c62b769f0603f1479620198000741`.
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

    private static let base64 = """
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
QtcimbkLDmMKHF1mKdPIfPQuJhUAgHimZwQCDSHY//sSxIMDxKQtDgBvwsCbBaHBv2VAhD9J//8FDQ+uhWNZo4BggoMllTDkzaOk
geUwbgXD38zILLqDsEfuc/RVrExutxJouiBBEVPgbimApIHhiPATWYBAA+AEAtBgAcWrTrWY99FNkRMv//sQxIcDxNwtDg37KgCW
BaIBr2VAVHItaYEImCmhiVSYPfBBrskKmBmDMAAIR0AZVdt2owqd/Sr//67Ty67HkeAMA5CExj0Wxl1/h9SmpnqP5hOAqmyAwfCt
V7OI6CQJZLBaLRAAAAD/+xLEigPE4C0OAGviwI8FogANeFgAB/ooJTzU9YBKad66tUW1PtRl/O6uElFFlh++HIXIvE1cf/oelVHI
+hXe//9bYJmSHXUIjwOICFVo6EoShKPkMJQOrwEgFHVCEIRj7SQMAknIkST/+xDEjoPEnC0ODXsqIJkFocG/YUAKC8CnhR3RXQX+
KkxBTUUzLjEwMKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7
EsSSA8TELQwAb+LgmQWhwA34WKqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqv/7EMSVgASELSAV14AhEA6r9zDwAqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq//sSxIqDxKQy7hzDAAgAADSA
AAAEqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq
qqqqqqqqqqqqqqqq
"""
}
