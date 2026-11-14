import Foundation
import Observation
import ScratchAudio
import ScratchCore
import ScratchLibrary
import XCTest
@testable import ScratchUI

/// Bandeaux de la sortie audio (story 2.3 CA 8 ; UX §8.5) : chaque avis publié par l'hôte devient un
/// bandeau de l'`AppModel`, une seule fois. Hôte simulé qui publie des avis comme `AudioEngineHost`.
@MainActor
final class HostNoticeBannerTests: XCTestCase {
    @MainActor
    @Observable
    final class NoticeHost: AudioOutputHosting, AudioNoticePosting {
        private(set) var status: AudioOutputStatus = .stopped
        private(set) var isRenderingAudio = false
        private(set) var notice: PostedAudioNotice?
        @ObservationIgnored private var count = 0
        /// Avis publié dès `start()` (sortie indisponible au lancement).
        @ObservationIgnored var noticeAtStart: AudioHostNotice?

        func start() {
            isRenderingAudio = true
            status = .unavailable(reason: "Aucune sortie audio.")
            if let noticeAtStart { post(noticeAtStart) }
        }

        func stop() {
            isRenderingAudio = false
            status = .stopped
        }

        func suspend() { stop() }
        func resume() { start() }

        func post(_ value: AudioHostNotice) {
            count += 1
            notice = PostedAudioNotice(id: count, notice: value)
        }

        /// Republie le même avis, même identifiant (aucun nouveau bandeau attendu).
        func repost() {
            if let notice { self.notice = PostedAudioNotice(id: notice.id, notice: notice.notice) }
        }
    }

    private var library: TemporaryLibrary!

    override func setUp() async throws {
        library = try TemporaryLibrary()
    }

    override func tearDown() async throws {
        library.remove()
    }

    private func makeModel(host: NoticeHost) -> AppModel {
        let decoder = FakeDecoder()
        return AppModel(engine: RecordingEngine(), host: host, library: library.makeStore(decoder: decoder),
                        preferences: InMemoryPreferencesStore(), decoder: decoder)
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }

    /// CA 8 : avis au lancement (aucune sortie), puis à chaque transition ; un avis déjà affiché ne
    /// l'est pas deux fois.
    func testHostNoticesBecomeBanners_UX8_5() async {
        let host = NoticeHost()
        host.noticeAtStart = .outputUnavailable
        let model = makeModel(host: host)
        await model.launch()
        XCTAssertEqual(model.toasts.current?.text, "Sortie audio indisponible. ScratchApp réessaiera automatiquement.")

        host.post(.outputAvailable(name: "MPC Sample (USB)"))
        await waitUntil { model.toasts.current?.text == "Sortie audio disponible : MPC Sample (USB)." }

        host.post(.outputDisconnected)
        await waitUntil { model.toasts.current?.text == "Sortie audio déconnectée : les platines sont arrêtées." }

        model.toasts.dismiss()
        host.repost()
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(model.toasts.current, "the same notice is shown once")

        host.post(.interrupted)
        await waitUntil { model.toasts.current?.text == "Lecture interrompue par le système. Appuyez sur START pour reprendre." }
    }
}
