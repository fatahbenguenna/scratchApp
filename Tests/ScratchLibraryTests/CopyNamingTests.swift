import Foundation
import XCTest
@testable import ScratchLibrary

/// Nommage des copies (SF-02, SF-60, D-12) : story 3.2, critère 5.
final class CopyNamingTests: XCTestCase {
    /// CA5 : le nom d'origine est conservé (accents, espaces, casse de l'extension) ; un nom que la
    /// bibliothèque refuserait est assaini (validé par l'orchestrateur).
    func testSanitizedNameKeepsTheOriginalWhenSafe() {
        let cases: [(String, String)] = [
            ("voix_funk.wav", "voix_funk.wav"),
            ("Boucle Été 2.WAV", "Boucle Été 2.WAV"),
            ("remix..final.wav", "remix.final.wav"),
            ("a...b....mp3", "a.b.mp3"),
            (".cache.wav", "cache.wav"),
            ("..wav", "wav"),
            ("son.", "son"),
            ("", "son"),
            ("...", "son"),
            ("tab\there.wav", "tab_here.wav"),
            ("back\\slash.wav", "back_slash.wav"),
            ("nul\u{0}.wav", "nul_.wav"),
        ]
        for (original, expected) in cases {
            let name = CopyNaming.sanitizedName(original)
            XCTAssertEqual(name, expected, original.debugDescription)
            XCTAssertTrue(LibraryStore.isSafeFileName(name), name.debugDescription)
        }
    }

    /// CA5 — D-12 : suffixe `_2`, `_3`… avant l'extension, sans écraser un nom pris.
    func testAvailableNameAddsUnderscoreSuffixBeforeTheExtension_D12() {
        var taken: Set<String> = ["voix_funk.wav", "voix_funk_2.wav", "boucle"]
        XCTAssertEqual(CopyNaming.availableName(for: "neuf.wav") { taken.contains($0) }, "neuf.wav")
        XCTAssertEqual(CopyNaming.availableName(for: "voix_funk.wav") { taken.contains($0) }, "voix_funk_3.wav")
        XCTAssertEqual(CopyNaming.availableName(for: "boucle") { taken.contains($0) }, "boucle_2")
        taken.insert("a.b.wav")
        XCTAssertEqual(CopyNaming.availableName(for: "a.b.wav") { taken.contains($0) }, "a.b_2.wav")
    }

    /// CA5 : un nom reste sous 255 octets UTF-8, suffixe et extension compris, et reste sûr.
    func testLongNamesAreShortenedBeforeTheSuffix() {
        let long = String(repeating: "é", count: 200) + ".wav"
        let name = CopyNaming.sanitizedName(long)
        XCTAssertLessThanOrEqual(name.utf8.count, 255)
        XCTAssertTrue(name.hasSuffix(".wav"))
        let suffixed = CopyNaming.availableName(for: name) { $0 == name }
        XCTAssertLessThanOrEqual(suffixed.utf8.count, 255)
        XCTAssertTrue(suffixed.hasSuffix("_2.wav"))
        let dotted = CopyNaming.availableName(for: String(repeating: "a", count: 249) + ".b.wav") { $0.hasSuffix(".b.wav") }
        XCTAssertTrue(LibraryStore.isSafeFileName(dotted), dotted)
        XCTAssertLessThanOrEqual(dotted.utf8.count, 255)
    }

    /// CA5 : la comparaison ignore la casse et la forme de normalisation Unicode (volumes du Mac).
    func testComparisonKeyIgnoresCaseAndNormalization() {
        XCTAssertEqual(CopyNaming.comparisonKey("Voix.WAV"), CopyNaming.comparisonKey("voix.wav"))
        XCTAssertEqual(CopyNaming.comparisonKey("e\u{301}te\u{301}.wav"), CopyNaming.comparisonKey("\u{E9}t\u{E9}.wav"))
        XCTAssertNotEqual(CopyNaming.comparisonKey("voix_2.wav"), CopyNaming.comparisonKey("voix.wav"))
    }
}
