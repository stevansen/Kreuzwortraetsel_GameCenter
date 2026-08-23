/// Welche Hilfen der Spieler benutzt hat.
public struct HintUsage: Codable, Sendable, Hashable {
    public var lettersRevealed: Int
    public var wordsRevealed: Int
    public var gridChecks: Int
    /// Prüfungen, die Fehler gefunden haben — zählen gegen den Clean-Bonus,
    /// kosten aber keine Punkte (der Abzug steckt schon in `gridChecks`).
    public var failedChecks: Int

    public init(lettersRevealed: Int = 0, wordsRevealed: Int = 0,
                gridChecks: Int = 0, failedChecks: Int = 0) {
        self.lettersRevealed = lettersRevealed
        self.wordsRevealed = wordsRevealed
        self.gridChecks = gridChecks
        self.failedChecks = failedChecks
    }

    public static let none = HintUsage()

    public var isClean: Bool {
        lettersRevealed == 0 && wordsRevealed == 0 && gridChecks == 0 && failedChecks == 0
    }

    public var penalty: Int {
        5 * lettersRevealed + 25 * wordsRevealed + 10 * gridChecks
    }

    /// Beim Zusammenführen zweier Geräte gewinnt jeweils der höhere Wert:
    /// eine benutzte Hilfe lässt sich nicht zurücknehmen.
    public static func merged(_ a: HintUsage, _ b: HintUsage) -> HintUsage {
        HintUsage(lettersRevealed: max(a.lettersRevealed, b.lettersRevealed),
                  wordsRevealed: max(a.wordsRevealed, b.wordsRevealed),
                  gridChecks: max(a.gridChecks, b.gridChecks),
                  failedChecks: max(a.failedChecks, b.failedChecks))
    }
}

public struct ScoreInput: Sendable {
    public let variant: PuzzleVariant
    public let difficulty: Difficulty
    public let letterCells: Int
    /// Spieldauer in Sekunden, gemessen mit einer **monotonen** Uhr.
    public let elapsedSeconds: Double
    public let hints: HintUsage
    public let streakDays: Int
    public let isDaily: Bool

    public init(variant: PuzzleVariant, difficulty: Difficulty, letterCells: Int,
                elapsedSeconds: Double, hints: HintUsage, streakDays: Int, isDaily: Bool) {
        self.variant = variant
        self.difficulty = difficulty
        self.letterCells = letterCells
        self.elapsedSeconds = elapsedSeconds
        self.hints = hints
        self.streakDays = streakDays
        self.isDaily = isDaily
    }
}

/// Die Punkte samt Herleitung — der Abschlussbildschirm zeigt sie Zeile für Zeile,
/// und genau deshalb wird sie hier mitgeliefert statt nur die Summe.
public struct ScoreBreakdown: Sendable, Hashable {
    public let base: Int
    public let sizeFactor: Double
    public let timeMultiplier: Double
    public let cleanBonus: Double
    public let streakMultiplier: Double
    public let dailyMultiplier: Double
    public let hintPenalty: Int
    public let total: Int
    /// Wurde der Zeitbonus wegen der Plausibilitätsgrenze gestrichen?
    public let timeBonusSuppressed: Bool

    /// Eine Zeile der Aufschlüsselung.
    ///
    /// Bewusst **ohne** Beschriftungstext: `PuzzleKit` importiert kein Foundation
    /// und kann deshalb nicht lokalisieren. Anzeigetexte gehören in die
    /// Oberflächenschicht — der Kern liefert die Struktur, `KreuzwortUI` die
    /// Sprache. Vorher standen hier deutsche Literale, was die App auf Deutsch
    /// festgenagelt hätte.
    public struct Line: Sendable, Hashable {
        public enum Kind: Sendable, Hashable {
            case base
            case size
            case time
            /// Zeit, aber der Bonus wurde wegen der Plausibilitätsgrenze gestrichen.
            case timeWithoutBonus
            case clean
            case streak
            case daily
            case hints
            case total
        }

        public let kind: Kind
        /// Der Zahlenwert, sprachunabhängig formatiert.
        public let value: String
    }

    public var lines: [Line] {
        var out: [Line] = [Line(kind: .base, value: "\(base)")]
        out.append(Line(kind: .size, value: "×" + fmt(sizeFactor, 2)))
        out.append(Line(kind: timeBonusSuppressed ? .timeWithoutBonus : .time,
                        value: "×" + fmt(timeMultiplier, 2)))
        if cleanBonus > 1 { out.append(Line(kind: .clean, value: "×" + fmt(cleanBonus, 2))) }
        if streakMultiplier > 1 {
            out.append(Line(kind: .streak, value: "×" + fmt(streakMultiplier, 2)))
        }
        if dailyMultiplier > 1 {
            out.append(Line(kind: .daily, value: "×" + fmt(dailyMultiplier, 1)))
        }
        if hintPenalty > 0 { out.append(Line(kind: .hints, value: "−\(hintPenalty)")) }
        out.append(Line(kind: .total, value: "\(total)"))
        return out
    }
}

/// Punkte für ein gelöstes Rätsel.
///
/// Multiplikativ mit geklemmten Faktoren: kein einzelner Regler kann
/// explodieren, aber jeder ist spürbar. Bewusst **kein** Varianten- und kein
/// Plattform-Faktor — beides würde Punktejäger in eine Ecke treiben und ein
/// gemeinsames Leaderboard entwerten. Die Variante wirkt nur über
/// `referenceLetterCells` und `parSeconds`, also über die Normierung.
public enum Scoring {
    /// Untergrenze, damit ein gelöstes Rätsel nie nichts wert ist.
    public static let floor = 10

    /// Mindestdauer je Buchstabenzelle. Wer schneller „fertig" ist, hat nicht
    /// gespielt — dann entfällt der Zeitbonus. Serverseitig ist das nicht
    /// verifizierbar; es ist eine Plausibilitätsgrenze, kein Schutzversprechen.
    public static let minSecondsPerCell = 0.35

    public static func score(_ input: ScoreInput) -> ScoreBreakdown {
        let profile = DifficultyProfile.profile(input.variant, input.difficulty)
        let base = input.difficulty.basePoints

        let reference = Double(max(profile.referenceLetterCells, 1))
        let sizeFactor = min(max(Double(input.letterCells) / reference, 0.8), 1.25)

        let plausibleMinimum = Double(input.letterCells) * minSecondsPerCell
        let tooFast = input.elapsedSeconds < plausibleMinimum
        let rawTime = 1.5 - 0.5 * (input.elapsedSeconds / max(profile.parSeconds, 1))
        // Zu schnell: kein Bonus, aber auch keine Strafe — der Faktor wird auf 1
        // gedeckelt statt auf den (hohen) Rohwert.
        let timeMultiplier = tooFast ? min(max(rawTime, 0.75), 1.0)
                                     : min(max(rawTime, 0.75), 1.5)

        let cleanBonus = input.hints.isClean ? 1.25 : 1.0
        let streakMultiplier = 1 + min(0.50, 0.05 * Double(max(input.streakDays, 0)))
        let dailyMultiplier = input.isDaily ? 2.0 : 1.0

        let product = Double(base) * sizeFactor * timeMultiplier * cleanBonus
            * streakMultiplier * dailyMultiplier
        let total = max(floor, Int(product.rounded()) - input.hints.penalty)

        return ScoreBreakdown(base: base, sizeFactor: sizeFactor,
                              timeMultiplier: timeMultiplier, cleanBonus: cleanBonus,
                              streakMultiplier: streakMultiplier,
                              dailyMultiplier: dailyMultiplier,
                              hintPenalty: input.hints.penalty, total: total,
                              timeBonusSuppressed: tooFast && rawTime > 1.0)
    }
}
