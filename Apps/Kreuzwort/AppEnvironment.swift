import Foundation
import Observation
import PuzzleKit
import ClueCatalog
import KreuzwortUI
import SyncKit
import GameServices

/// Alles, was die App einmal aufbaut und dann behält: Katalog, Pattern-Index,
/// Templates, Breitentabelle, Spielstand-Speicher.
///
/// Der Aufbau ist teuer (der Index über 126.000 Antworten braucht rund eine
/// halbe Sekunde), die Nutzung danach nicht. Deshalb genau einmal.
@Observable
@MainActor
final class AppEnvironment {
    enum State {
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var resumable: PuzzleProgress?
    /// Die Wahrheit über Punkte, Serie und Achievements — nicht Game Center.
    private(set) var profile = PlayerProfile()
    private(set) var gameCenterAvailable = false
    private(set) var pendingSubmissions = 0

    var variant: PuzzleVariant = .classic
    var difficulty: Difficulty = .mittel
    /// `nil` = Systemsprache.
    var language: String? {
        didSet { Loc.forcedLanguage = language }
    }

    private var index: PatternIndex?
    private var clues: CatalogClueSource?
    private var templates: [GridTemplate] = []
    private var widths: GlyphWidthTable = .bootstrap
    private(set) var store: ProgressStore?
    private var profileStore: ProfileStore?
    private var coordinator: GameCenterCoordinator?

    func load() async {
        state = .loading
        do {
            let store = try ProgressStore()
            self.store = store
            let resources = try Self.resourceRoot()

            let reader = try CatalogReader(
                path: resources.appendingPathComponent("catalog.sqlite").path)
            let lexicon = try reader.loadLexicon()
            guard lexicon.count > 0 else {
                state = .failed(Loc.string("error.emptyCatalog"))
                return
            }
            if let data = try? Data(contentsOf:
                resources.appendingPathComponent("glyphwidths.json")),
               let table = try? JSONDecoder().decode(GlyphWidthTable.self, from: data) {
                widths = table
            }
            index = PatternIndex(lexicon: lexicon)
            clues = CatalogClueSource(reader: reader, widths: widths)
            templates = Self.loadTemplates(in: resources.appendingPathComponent("grids/classic"))
            resumable = store.mostRecentUnfinished()

            let profileStore = try ProfileStore()
            self.profileStore = profileStore
            profile = profileStore.load()

            // Game Center im Hintergrund: die App ist ohne Anmeldung vollständig
            // spielbar, also darf hier nichts warten.
            let coordinator = GameCenterCoordinator(
                service: LiveGameCenterService(),
                outbox: try SubmissionOutbox(),
                deviceID: store.deviceID)
            self.coordinator = coordinator
            state = .ready
            Task { [weak self] in
                await coordinator.start()
                await self?.refreshGameCenterState()
                await coordinator.reconcile(profile: self?.profile ?? PlayerProfile(),
                                            today: Self.today())
                await self?.refreshGameCenterState()
            }
        } catch {
            state = .failed("\(error)")
        }
    }

    /// Der Katalog liegt im App-Bundle. In der Entwicklung — etwa beim Start aus
    /// dem Projektverzeichnis — auch daneben; deshalb beide Orte versuchen,
    /// statt mit einer nichtssagenden Meldung zu scheitern.
    private static func resourceRoot() throws -> URL {
        // Im App-Bundle: entweder direkt in Resources/ oder — bei einem
        // Ordnerverweis im Xcode-Projekt — eine Ebene tiefer.
        for subdirectory in [nil, "Resources"] as [String?] {
            if let bundled = Bundle.main.url(forResource: "catalog", withExtension: "sqlite",
                                             subdirectory: subdirectory) {
                return bundled.deletingLastPathComponent()
            }
        }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for candidate in [cwd.appendingPathComponent("Resources"),
                          cwd.appendingPathComponent("../Resources")] {
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("catalog.sqlite").path) {
                return candidate
            }
        }
        throw AppError.catalogMissing
    }

    private static func loadTemplates(in directory: URL) -> [GridTemplate] {
        var out: [GridTemplate] = []
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names.sorted() where name.hasSuffix(".json") {
            if let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
               let set = try? JSONDecoder().decode(TemplateSet.self, from: data) {
                out += set.templates
            }
        }
        return out
    }

    // MARK: - Rätsel

    /// Ein neues Rätsel. Der Seed kommt aus der Uhr, damit aufeinanderfolgende
    /// Aufrufe verschiedene Rätsel liefern — die **Erzeugung** bleibt
    /// deterministisch, nur die Wahl des Seeds ist es nicht.
    func newPuzzle() throws -> Puzzle {
        try puzzle(seed: UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFF_FFFF)
    }

    /// Das Tagesrätsel: serverlos, weltweit identisch.
    func dailyPuzzle() throws -> Puzzle {
        let date = ISO8601DateFormatter()
        date.formatOptions = [.withFullDate]
        return try puzzle(seed: Puzzle.dailySeed(isoDate: date.string(from: Date()),
                                                 variant: variant, difficulty: difficulty))
    }

    func puzzle(seed: UInt64) throws -> Puzzle {
        guard let index, let clues else { throw AppError.notReady }
        let layout: any LayoutProvider = variant == .classic
            ? ClassicLayout(templates: templates) : ArrowLayout()
        let generator = Generator(layout: layout, index: index, clues: clues, widths: widths)
        return try generator.generate(seed: seed, difficulty: difficulty).puzzle
    }

    /// Ein angefangenes Rätsel wiederherstellen: aus dem Spielstand steht nur der
    /// Seed da, das Gitter wird neu erzeugt.
    func restore(_ progress: PuzzleProgress) throws -> Puzzle {
        let saved = (variant, difficulty)
        variant = progress.variant
        difficulty = progress.difficulty
        defer { if progress.completedAtEpoch != nil { (variant, difficulty) = saved } }
        return try puzzle(seed: progress.seed)
    }

    func persist(_ progress: PuzzleProgress) {
        try? store?.save(progress)
        resumable = store?.mostRecentUnfinished()
    }

    // MARK: - Abschluss verbuchen

    /// Lokale Tagesnummer. `PuzzleKit` hat kein Foundation und damit keine
    /// Zeitzonen — die Umrechnung gehört hierher, wo die Zeitzone bekannt ist.
    static func today() -> Int {
        let seconds = Date().timeIntervalSince1970
            + Double(TimeZone.current.secondsFromGMT())
        return Int(seconds / 86_400)
    }

    /// Nach einem gelösten Rätsel: Profil fortschreiben, Game Center beliefern.
    func recordCompletion(puzzle: Puzzle, progress: PuzzleProgress,
                          breakdown: ScoreBreakdown, isDaily: Bool) async {
        let hour = Calendar.current.component(.hour, from: Date())
        let completion = PlayerProfile.Completion(
            variant: puzzle.variant, difficulty: puzzle.difficulty,
            points: breakdown.total, hints: progress.hints,
            elapsedSeconds: progress.elapsedSeconds,
            answerIDs: puzzle.entries.map(\.answerID), isDaily: isDaily,
            day: Self.today(), hour: hour, platform: Self.platformTag)

        if let coordinator {
            profile = await coordinator.record(completion, profile: profile,
                                               today: Self.today()).profile
        } else {
            profile.record(completion, device: store?.deviceID ?? 1)
        }
        try? profileStore?.save(profile)
        await refreshGameCenterState()
    }

    private func refreshGameCenterState() async {
        guard let coordinator else { return }
        gameCenterAvailable = await coordinator.canPresentDashboard
        pendingSubmissions = await coordinator.pendingSubmissions
    }

    var currentStreak: Int { profile.currentStreak(today: Self.today()) }

    /// Kennung der Fläche für das Plattform-Achievement.
    static var platformTag: String {
        #if os(tvOS)
        "tv"
        #elseif os(macOS)
        "mac"
        #else
        "phone"
        #endif
    }

    enum AppError: LocalizedError {
        case catalogMissing
        case notReady

        var errorDescription: String? {
            switch self {
            case .catalogMissing: Loc.string("error.catalogMissing")
            case .notReady: Loc.string("error.notReady")
            }
        }
    }
}
