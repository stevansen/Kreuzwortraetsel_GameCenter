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
    /// Zur Bauzeit geprüfte Seeds. `nil`, wenn die Datei fehlt oder zu einem
    /// anderen Katalog gehört — dann wird blind gewählt wie vorher.
    private var verifiedSeeds: VerifiedSeeds?
    /// Abdruck des geladenen Katalogs. Wird gebraucht, um veraltete Spielstände
    /// auszusortieren — aus demselben Seed erzeugt ein anderer Katalog ein
    /// anderes Gitter.
    private var catalogVersion = 0
    private var widths: GlyphWidthTable = .bootstrap
    private(set) var store: ProgressStore?
    private var profileStore: ProfileStore?
    private var coordinator: GameCenterCoordinator?
    private var sync: SyncCoordinator?
    private var snapshotStore: SharedSnapshotStore?
    private(set) var syncAvailable = false

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
            catalogVersion = reader.catalogVersion
            verifiedSeeds = Self.loadVerifiedSeeds(
                at: resources.appendingPathComponent("seeds.txt"),
                catalogVersion: reader.catalogVersion)
            resumable = store.mostRecentUnfinished(
                generatorVersion: Generator.currentVersion,
                catalogVersion: reader.catalogVersion)

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
            // Sync: CloudKit nur, wenn der Build das iCloud-Entitlement hat.
            //
            // Das `try?` hier war ein Trugschluss und hat die App im Simulator
            // beim Start abgeschossen: `CKContainer(identifier:)` **trappt**,
            // wenn das Entitlement fehlt — das ist kein Fehler, den `try?`
            // auffangen kann, sondern ein Absturz mitten in
            // `AppEnvironment.load()`. Getroffen hätte es jeden Build ohne
            // iCloud-Berechtigung, also auch den, der jetzt in den Store geht.
            //
            // Der Schalter ist eine Bauzeit-Tatsache und wird zusammen mit dem
            // Entitlement gesetzt (siehe Kreuzwort.entitlements und
            // scripts/make-xcodeproj.py), damit beides nicht auseinanderläuft.
            var backend: any SyncBackend = LocalOnlySyncBackend()
            #if KREUZWORT_CLOUDKIT
            if let cloud = try? CloudKitSyncBackend() { backend = cloud }
            #endif
            let sync = SyncCoordinator(backend: backend, progressStore: store,
                                       profileStore: profileStore,
                                       deviceID: store.deviceID)
            self.sync = sync
            snapshotStore = try? SharedSnapshotStore()

            state = .ready
            Task { [weak self] in
                await sync.start()
                await sync.synchronize()
                await self?.reloadAfterSync()
            }
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
        // Im App-Bundle liegen die Daten unter **Data**, nicht unter Resources.
        // Der Name ist kein Geschmacksurteil: ein Ordner „Resources" im
        // iOS-Bundle bringt codesign dazu, die Dateien in der Bundle-Wurzel für
        // eigenständigen Code zu halten, und der signierte Build scheitert mit
        // „code object is not signed at all". Siehe scripts/make-xcodeproj.py.
        //
        // „Resources" bleibt in der Liste, weil beim Start aus dem
        // Projektverzeichnis genau dieser Ordner daneben liegt.
        for subdirectory in [nil, "Data", "Resources"] as [String?] {
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

    /// Die geprüfte Seed-Liste, oder `nil`.
    ///
    /// Streng bei der Version: ein Seed, der gegen einen anderen Katalog geprüft
    /// wurde, sagt nichts über diesen. Und streng bei der Vollständigkeit — eine
    /// Liste, in der eine Kombination fehlt, würde genau dort still auf blindes
    /// Wählen zurückfallen, und das wäre schwer zu finden.
    private static func loadVerifiedSeeds(at url: URL, catalogVersion: Int) -> VerifiedSeeds? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let parsed = try? VerifiedSeeds.parse(text),
              parsed.catalogVersion == catalogVersion,
              parsed.generatorVersion == Generator.currentVersion,
              parsed.isComplete
        else { return nil }
        return parsed
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

    /// Ein neues Rätsel. Die Uhr wählt weiterhin, aber nur den **Index** in die
    /// geprüfte Liste — damit bleibt die Wahl beliebig und das Ergebnis
    /// erzeugbar. Ohne Liste wie früher direkt aus der Uhr.
    func newPuzzle() throws -> Puzzle {
        let pick = UInt64(Date().timeIntervalSince1970 * 1000) & 0xFFFF_FFFF
        if let seed = verifiedSeeds?.seed(variant: variant, difficulty: difficulty,
                                          pick: pick) {
            return try puzzle(seed: seed)
        }
        return try puzzle(seed: pick)
    }

    /// Das Tagesrätsel: serverlos, weltweit identisch — und erzeugbar.
    ///
    /// Der Seed des Tages war vorher der Hash des Datums selbst. Das war an den
    /// Tagen wertlos, an denen dieser Seed nicht füllbar ist: kein Rätsel, oder
    /// Minuten Wartezeit bis zum Fehlschlag. Jetzt indiziert derselbe Hash die
    /// geprüfte Liste. Das Tagesrätsel bleibt eine Funktion des Datums allein.
    func dailyPuzzle() throws -> Puzzle {
        let date = ISO8601DateFormatter()
        date.formatOptions = [.withFullDate]
        let iso = date.string(from: Date())
        if let seed = verifiedSeeds?.dailySeed(isoDate: iso, variant: variant,
                                               difficulty: difficulty) {
            return try puzzle(seed: seed)
        }
        return try puzzle(seed: Puzzle.dailySeed(isoDate: iso, variant: variant,
                                                 difficulty: difficulty))
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
        resumable = store?.mostRecentUnfinished(
            generatorVersion: Generator.currentVersion, catalogVersion: catalogVersion)
        writeSnapshot()
        if let sync { Task { await sync.push(progress: progress) } }
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
        // Sync ist ein Anhang, der ausfallen darf: nichts hier wartet auf ihn.
        if let sync {
            await sync.push(profile: profile)
            await sync.push(progress: progress)
        }
        writeSnapshot()
    }

    /// Nach einem Sync: lokale Sicht neu aufbauen. Ein fremdes Gerät kann ein
    /// Rätsel beendet oder Punkte beigetragen haben.
    private func reloadAfterSync() async {
        guard let profileStore, let store else { return }
        profile = profileStore.load()
        resumable = store.mostRecentUnfinished()
        syncAvailable = await sync?.isAvailable ?? false
        await coordinator?.reconcile(profile: profile, today: Self.today())
        await refreshGameCenterState()
        writeSnapshot()
    }

    /// Schreibt die Widget-Momentaufnahme. Klein und flach — ein Widget darf
    /// keine 43-MB-Katalogdatei öffnen.
    func writeSnapshot() {
        try? snapshotStore?.update(profile: profile, today: Self.today(),
                                   resumable: resumable,
                                   letterCells: resumable?.cells.count ?? 1,
                                   now: Date().timeIntervalSince1970)
    }

    // MARK: - Verweise und Handoff

    /// Öffnet ein Rätsel aus einem Link. Fehlerhafte Links werden **abgelehnt**,
    /// nicht geraten — ein Tippfehler soll nicht das falsche Rätsel öffnen.
    func puzzle(from link: PuzzleLink) throws -> Puzzle {
        variant = link.variant
        difficulty = link.difficulty
        return try puzzle(seed: link.seed)
    }

    func puzzle(fromURL url: URL) -> Puzzle? {
        guard let link = try? PuzzleLink.parse(url.absoluteString) else { return nil }
        return try? puzzle(from: link)
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
