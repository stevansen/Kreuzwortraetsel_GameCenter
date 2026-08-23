/// Ein Zähler, der nur wachsen kann.
///
/// Der Wert wird **pro Gerät** geführt und angezeigt wird die Summe. Ein
/// einzelner Skalar würde bei parallelen Erhöhungen zuverlässig falsch werden:
/// zwei Geräte lösen offline je ein Rätsel, beide setzen den Zähler von 7 auf 8,
/// nach dem Sync steht 8 statt 9. Mit einer Map je Gerät ist das Zusammenführen
/// das Maximum je Schlüssel — kommutativ, idempotent und ohne Verlust.
public struct GrowOnlyCounter: Codable, Sendable, Hashable {
    private var byDevice: [UInt32: Int]

    public init() { byDevice = [:] }
    public init(_ byDevice: [UInt32: Int]) { self.byDevice = byDevice }

    public var total: Int { byDevice.values.reduce(0, +) }

    public mutating func increment(_ amount: Int = 1, device: UInt32) {
        byDevice[device, default: 0] += max(0, amount)
    }

    public static func merged(_ a: GrowOnlyCounter, _ b: GrowOnlyCounter) -> GrowOnlyCounter {
        var out = a.byDevice
        for (device, value) in b.byDevice { out[device] = max(out[device] ?? 0, value) }
        return GrowOnlyCounter(out)
    }
}

/// Das synchronisierte Spielerprofil.
///
/// **Game Center ist Anzeige, nicht Quelle der Wahrheit.** GameKit gibt
/// Achievement-Fortschritt nur begrenzt zurück und ist gar nicht verfügbar,
/// solange der Spieler nicht angemeldet ist. Die Wahrheit ist dieses Profil;
/// Game Center wird daraus beschrieben.
///
/// Jedes Feld ist bewusst so gewählt, dass Zusammenführen **konfliktfrei** ist:
/// wachsende Zähler, Mengenvereinigung, logisches Oder. Es gibt keinen Fall, in
/// dem zwei Geräte sich widersprechen könnten — deshalb braucht dieses Profil
/// keine Zeitstempel und keine Tiebreaks.
public struct PlayerProfile: Codable, Sendable {
    public var solved: GrowOnlyCounter
    public var points: GrowOnlyCounter
    /// Nach `PuzzleVariant.rawValue`.
    public var solvedByVariant: [String: GrowOnlyCounter]
    /// Nach `Difficulty.rawValue`.
    public var solvedByDifficulty: [String: GrowOnlyCounter]
    /// Gelöst ohne jede Fehleingabe und ohne Hilfe.
    public var flawless: GrowOnlyCounter
    /// Experte-Rätsel ohne jede Hilfe, nach Variante.
    public var expertClean: [String: GrowOnlyCounter]
    /// Mittel unter vier Minuten, ohne Hilfe.
    public var speedruns: GrowOnlyCounter

    /// Antwort-IDs, die der Spieler je gelöst hat. Vereinigung beim Merge.
    public var seenAnswers: Set<Int32>
    /// Tage (lokale Tagesnummern), an denen ein Tagesrätsel gelöst wurde.
    ///
    /// Die Serie wird **daraus berechnet** statt als Zahl geführt. Ein Zähler
    /// wäre nicht konfliktfrei: zwei Geräte, die denselben Tag lösen, würden ihn
    /// beide erhöhen. Eine Menge von Tagen kennt dieses Problem nicht.
    public var dailyDays: Set<Int>
    /// Varianten, in denen am selben Tag gelöst wurde — für „Beidhändig".
    public var ambidextrousDays: Set<Int>
    /// Tageszeit-Marken: 0–3 Uhr und 4–6 Uhr.
    public var solvedAtNight: Bool
    public var solvedAtDawn: Bool
    /// Nach mindestens 30 Tagen Pause wieder gelöst.
    public var madeComeback: Bool
    /// Plattformen, auf denen gelöst wurde (`tv`, `phone`, …).
    public var platforms: Set<String>
    /// Themenpakete, die vollständig gelöst wurden.
    public var completedTopics: Set<String>

    public init() {
        solved = GrowOnlyCounter()
        points = GrowOnlyCounter()
        solvedByVariant = [:]
        solvedByDifficulty = [:]
        flawless = GrowOnlyCounter()
        expertClean = [:]
        speedruns = GrowOnlyCounter()
        seenAnswers = []
        dailyDays = []
        ambidextrousDays = []
        solvedAtNight = false
        solvedAtDawn = false
        madeComeback = false
        platforms = []
        completedTopics = []
    }

    // MARK: - Buchen

    /// Was beim Abschluss eines Rätsels bekannt ist.
    public struct Completion: Sendable {
        public let variant: PuzzleVariant
        public let difficulty: Difficulty
        public let points: Int
        public let hints: HintUsage
        public let elapsedSeconds: Double
        public let answerIDs: [Int32]
        public let isDaily: Bool
        /// Lokale Tagesnummer. Wird vom Aufrufer berechnet — `PuzzleKit` hat
        /// kein Foundation und damit keine Zeitzonen.
        public let day: Int
        /// Lokale Stunde 0–23, für Nachteule und Frühaufsteher.
        public let hour: Int
        /// Kennung der Fläche, auf der gelöst wurde.
        public let platform: String

        public init(variant: PuzzleVariant, difficulty: Difficulty, points: Int,
                    hints: HintUsage, elapsedSeconds: Double, answerIDs: [Int32],
                    isDaily: Bool, day: Int, hour: Int, platform: String) {
            self.variant = variant
            self.difficulty = difficulty
            self.points = points
            self.hints = hints
            self.elapsedSeconds = elapsedSeconds
            self.answerIDs = answerIDs
            self.isDaily = isDaily
            self.day = day
            self.hour = hour
            self.platform = platform
        }
    }

    public mutating func record(_ completion: Completion, device: UInt32) {
        solved.increment(device: device)
        points.increment(completion.points, device: device)
        solvedByVariant[completion.variant.rawValue, default: GrowOnlyCounter()]
            .increment(device: device)
        solvedByDifficulty[completion.difficulty.rawValue, default: GrowOnlyCounter()]
            .increment(device: device)
        if completion.hints.isClean { flawless.increment(device: device) }
        if completion.difficulty == .experte, completion.hints.isClean {
            expertClean[completion.variant.rawValue, default: GrowOnlyCounter()]
                .increment(device: device)
        }
        if completion.difficulty == .mittel, completion.hints.isClean,
           completion.elapsedSeconds < 240 {
            speedruns.increment(device: device)
        }
        seenAnswers.formUnion(completion.answerIDs)
        platforms.insert(completion.platform)

        if completion.isDaily {
            // Rückkehrer: Lücke von 30 Tagen oder mehr zur letzten Serie.
            if let last = dailyDays.max(), completion.day - last >= 30 { madeComeback = true }
            dailyDays.insert(completion.day)
        }
        if completion.hour < 4 { solvedAtNight = true }
        else if completion.hour < 7 { solvedAtDawn = true }
    }

    /// Zweite Variante am selben Tag — muss der Aufrufer melden, weil dazu die
    /// Rätsel *dieses Tages* bekannt sein müssen, nicht nur das aktuelle.
    public mutating func recordBothVariants(onDay day: Int) {
        ambidextrousDays.insert(day)
    }

    // MARK: - Serie

    /// Aktuelle Serie: die längste Kette aufeinanderfolgender Tage, die auf
    /// `today` oder `today - 1` endet.
    ///
    /// Der Vortag zählt mit, weil eine Serie sonst um Mitternacht reißt, obwohl
    /// der Spieler nichts falsch gemacht hat — er hat heute nur noch nicht gespielt.
    public func currentStreak(today: Int) -> Int {
        let end: Int
        if dailyDays.contains(today) { end = today }
        else if dailyDays.contains(today - 1) { end = today - 1 }
        else { return 0 }

        var length = 0
        var day = end
        while dailyDays.contains(day) { length += 1; day -= 1 }
        return length
    }

    public var bestStreak: Int {
        guard !dailyDays.isEmpty else { return 0 }
        let sorted = dailyDays.sorted()
        var best = 1, run = 1
        for i in 1 ..< sorted.count {
            if sorted[i] == sorted[i - 1] + 1 { run += 1; best = max(best, run) }
            else { run = 1 }
        }
        return best
    }

    // MARK: - Zusammenführen

    /// Alle Felder sind Vereinigung, Maximum oder logisches Oder — deshalb ist
    /// dieser Merge kommutativ und idempotent, ohne einen einzigen Zeitstempel.
    public static func merged(_ a: PlayerProfile, _ b: PlayerProfile) -> PlayerProfile {
        var out = PlayerProfile()
        out.solved = .merged(a.solved, b.solved)
        out.points = .merged(a.points, b.points)
        out.solvedByVariant = mergeMaps(a.solvedByVariant, b.solvedByVariant)
        out.solvedByDifficulty = mergeMaps(a.solvedByDifficulty, b.solvedByDifficulty)
        out.flawless = .merged(a.flawless, b.flawless)
        out.expertClean = mergeMaps(a.expertClean, b.expertClean)
        out.speedruns = .merged(a.speedruns, b.speedruns)
        out.seenAnswers = a.seenAnswers.union(b.seenAnswers)
        out.dailyDays = a.dailyDays.union(b.dailyDays)
        out.ambidextrousDays = a.ambidextrousDays.union(b.ambidextrousDays)
        out.solvedAtNight = a.solvedAtNight || b.solvedAtNight
        out.solvedAtDawn = a.solvedAtDawn || b.solvedAtDawn
        out.madeComeback = a.madeComeback || b.madeComeback
        out.platforms = a.platforms.union(b.platforms)
        out.completedTopics = a.completedTopics.union(b.completedTopics)
        return out
    }

    private static func mergeMaps(_ a: [String: GrowOnlyCounter],
                                  _ b: [String: GrowOnlyCounter]) -> [String: GrowOnlyCounter] {
        var out = a
        for (key, value) in b {
            out[key] = out[key].map { GrowOnlyCounter.merged($0, value) } ?? value
        }
        return out
    }
}
