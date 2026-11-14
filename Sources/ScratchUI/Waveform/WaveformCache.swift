import ScratchCore

/// Enveloppes des sons chargés, par identifiant de clip (story 4.6 CA 1 ; RM-57).
///
/// - Chaque platine prend une référence sur le clip qu'elle affiche (`retain`) et la rend quand elle
///   change de son (`release`) : un même clip chargé sur A et B n'est analysé qu'une fois, et son
///   enveloppe est libérée quand il n'est plus chargé sur aucune platine.
/// - L'analyse tourne dans une tâche détachée, annulée quand plus aucune platine ne l'attend.
/// - L'analyse lit la mémoire du clip sans la copier : le cache garde le clip jusqu'à la fin de
///   l'analyse et le rend ensuite sur le fil principal (jamais sur le fil audio).
@MainActor
public final class WaveformCache {
    /// Cache partagé par les platines de l'app.
    public static let shared = WaveformCache()

    typealias Analyzer = @Sendable (WaveformAnalyzer.Samples, () -> Bool) -> WaveformPeaks?

    private struct Entry {
        let clip: AudioClip
        let analysis: Task<WaveformPeaks?, Never>
        var users: Int
    }

    private let analyzer: Analyzer
    private var entries: [AudioClip.ID: Entry] = [:]
    /// Analyses lancées depuis la création (tests de RM-57).
    private(set) var analysisCount = 0
    /// Clips dont l'enveloppe est gardée.
    var cachedClipCount: Int { entries.count }

    public convenience init() {
        self.init(analyzer: { WaveformAnalyzer.analyze($0, isCancelled: $1) })
    }

    init(analyzer: @escaping Analyzer) {
        self.analyzer = analyzer
    }

    /// Prend une référence sur l'enveloppe de `clip` et rend la tâche qui la calcule (déjà terminée
    /// si le clip est chargé sur l'autre platine).
    func retain(_ clip: AudioClip) -> Task<WaveformPeaks?, Never> {
        if var entry = entries[clip.id] {
            entry.users += 1
            entries[clip.id] = entry
            return entry.analysis
        }
        analysisCount += 1
        let samples = WaveformAnalyzer.Samples(left: clip.left, right: clip.right, sampleRate: clip.sampleRate)
        let analyzer = analyzer
        let analysis = Task.detached(priority: .userInitiated) {
            analyzer(samples) { Task.isCancelled }
        }
        entries[clip.id] = Entry(clip: clip, analysis: analysis, users: 1)
        return analysis
    }

    /// Rend une référence ; la dernière annule l'analyse en cours et libère l'enveloppe.
    func release(_ id: AudioClip.ID) {
        guard var entry = entries[id] else { return }
        entry.users -= 1
        guard entry.users <= 0 else {
            entries[id] = entry
            return
        }
        entries[id] = nil
        entry.analysis.cancel()
        // The analysis reads the clip's memory: keep the clip until it stops, then drop it here.
        let clip = entry.clip
        let analysis = entry.analysis
        Task { @MainActor in
            _ = await analysis.value
            withExtendedLifetime(clip) {}
        }
    }
}
