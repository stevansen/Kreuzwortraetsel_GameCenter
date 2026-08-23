public struct AnswerFlags: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let properNoun = AnswerFlags(rawValue: 1 << 0)
    public static let abbreviation = AnswerFlags(rawValue: 1 << 1)
    public static let foreign = AnswerFlags(rawValue: 1 << 2)
    public static let compound = AnswerFlags(rawValue: 1 << 3)
}

public let tierCount = 5

/// Eine Antwort, wie der Generator sie braucht — ohne Clue-Texte.
///
/// `minShortWidthByTier` ist der Grund, dass das Breitenbudget des
/// Schwedenrätsels ein **Füll-Constraint** sein kann und kein Nachfilter:
/// schon bei der Kandidatenauswahl steht fest, ob es für diese Antwort einen
/// Kurzclue gibt, der in die Zelle passt.
public struct LexEntry: Sendable {
    public let answerID: Int32
    public let letters: [Letter]
    public let zipf: Double
    public let flags: AnswerFlags
    /// Index 0 ..< 5 entspricht Tier 1 ... 5. `Int32.max` = kein Kurzclue in diesem Tier.
    public let minShortWidthByTier: [Int32]
    /// Gibt es überhaupt einen (Lang-)Clue in diesem Tier?
    public let hasClueByTier: [Bool]

    public init(answerID: Int32, letters: [Letter], zipf: Double, flags: AnswerFlags,
                minShortWidthByTier: [Int32], hasClueByTier: [Bool]) {
        precondition(minShortWidthByTier.count == tierCount)
        precondition(hasClueByTier.count == tierCount)
        self.answerID = answerID
        self.letters = letters
        self.zipf = zipf
        self.flags = flags
        self.minShortWidthByTier = minShortWidthByTier
        self.hasClueByTier = hasClueByTier
    }

    public var length: Int { letters.count }
    public var surface: String { Alphabet.string(letters) }
}

/// Das Füllvokabular. Wird von `ClueCatalog` aus SQLite gebaut, ist hier aber
/// reine Datenstruktur — `PuzzleKit` kennt keine Datenbank.
public struct Lexicon: Sendable {
    public let entries: [LexEntry]
    /// Länge -> globale Indizes (`gid`), aufsteigend sortiert.
    public let byLength: [Int: [Int]]
    public let catalogVersion: Int

    public init(entries: [LexEntry], catalogVersion: Int) {
        // Stabil sortieren: Länge, dann Oberfläche. Der Generator darf nie von
        // der Einfügereihenfolge der Datenbank abhängen.
        let sorted = entries.sorted {
            $0.letters.count != $1.letters.count
                ? $0.letters.count < $1.letters.count
                : ($0.letters.lexicographicallyPrecedes($1.letters)
                    || ($0.letters == $1.letters && $0.answerID < $1.answerID))
        }
        self.entries = sorted
        var byLength: [Int: [Int]] = [:]
        for (gid, e) in sorted.enumerated() { byLength[e.length, default: []].append(gid) }
        self.byLength = byLength
        self.catalogVersion = catalogVersion
    }

    public var count: Int { entries.count }
    public func countsByLength() -> [(length: Int, count: Int)] {
        byLength.map { (length: $0.key, count: $0.value.count) }.sorted { $0.length < $1.length }
    }
}
