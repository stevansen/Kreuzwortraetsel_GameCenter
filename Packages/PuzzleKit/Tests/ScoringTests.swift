import Testing
@testable import PuzzleKit

@Suite("Punkte")
struct ScoringTests {
    private func input(_ variant: PuzzleVariant = .classic, _ difficulty: Difficulty = .mittel,
                       cells: Int? = nil, seconds: Double? = nil,
                       hints: HintUsage = .none, streak: Int = 0,
                       daily: Bool = false) -> ScoreInput {
        let p = DifficultyProfile.profile(variant, difficulty)
        return ScoreInput(variant: variant, difficulty: difficulty,
                          letterCells: cells ?? p.referenceLetterCells,
                          elapsedSeconds: seconds ?? p.parSeconds,
                          hints: hints, streakDays: streak, isDaily: daily)
    }

    @Test func parTimeAndReferenceSizeGiveTheBaseValue() {
        // Genau auf Par und Referenzgröße: alle Faktoren 1, Zeit ergibt 1,0.
        let b = Scoring.score(input(.classic, .mittel))
        #expect(b.sizeFactor == 1.0)
        #expect(b.timeMultiplier == 1.0)
        #expect(b.cleanBonus == 1.25)          // ohne Hilfen
        #expect(b.total == Int((250.0 * 1.25).rounded()))
    }

    @Test func fasterIsWorthMoreButBoundedBothWays() {
        let p = DifficultyProfile.profile(.classic, .mittel)
        let quick = Scoring.score(input(seconds: p.parSeconds * 0.2))
        let slow = Scoring.score(input(seconds: p.parSeconds * 5))
        #expect(quick.total > slow.total)
        // Geklemmt: kein Regler darf explodieren.
        #expect(quick.timeMultiplier <= 1.5)
        #expect(slow.timeMultiplier >= 0.75)
    }

    @Test func suspiciouslyFastLosesTheBonusButIsNotPunished() {
        // Plausibilitätsgrenze: Zellen × 0,35 s. Darunter entfällt der Bonus —
        // eine Strafe würde echte Schnellöser treffen.
        let cells = 100
        let tooFast = Scoring.score(input(cells: cells,
                                          seconds: Double(cells) * 0.1))
        #expect(tooFast.timeBonusSuppressed)
        #expect(tooFast.timeMultiplier <= 1.0)
        #expect(tooFast.timeMultiplier >= 0.75)

        let plausible = Scoring.score(input(cells: cells,
                                            seconds: Double(cells) * 0.4))
        #expect(!plausible.timeBonusSuppressed)
        #expect(plausible.total > tooFast.total)
    }

    @Test func hintsCostPointsAndTheCleanBonus() {
        let clean = Scoring.score(input())
        let withHint = Scoring.score(input(hints: HintUsage(lettersRevealed: 2)))
        #expect(clean.cleanBonus == 1.25)
        #expect(withHint.cleanBonus == 1.0)
        #expect(withHint.hintPenalty == 10)
        #expect(withHint.total < clean.total)
    }

    @Test func failedCheckCostsTheBonusButNotTwice() {
        // Eine Prüfung, die Fehler fand, zählt gegen den Clean-Bonus — der Abzug
        // steckt aber schon in gridChecks und darf nicht doppelt greifen.
        let a = Scoring.score(input(hints: HintUsage(gridChecks: 1)))
        let b = Scoring.score(input(hints: HintUsage(gridChecks: 1, failedChecks: 1)))
        #expect(a.hintPenalty == b.hintPenalty)
        #expect(a.total == b.total)
    }

    @Test func streakIsCappedAtFiftyPercent() {
        let ten = Scoring.score(input(streak: 10))
        let hundred = Scoring.score(input(streak: 100))
        #expect(ten.streakMultiplier == 1.5)
        #expect(hundred.streakMultiplier == 1.5)
    }

    @Test func dailyDoubles() {
        let normal = Scoring.score(input())
        let daily = Scoring.score(input(daily: true))
        #expect(daily.dailyMultiplier == 2.0)
        #expect(daily.total > normal.total)
    }

    @Test func neverBelowTheFloor() {
        // Hilfen können die Punkte nicht ins Negative ziehen.
        let ruined = Scoring.score(input(.classic, .leicht,
                                         hints: HintUsage(lettersRevealed: 200,
                                                          wordsRevealed: 50,
                                                          gridChecks: 50)))
        #expect(ruined.total == Scoring.floor)
    }

    @Test func noVariantAdvantage() {
        // Bewusst kein Varianten-Faktor: bei gleicher relativer Größe und Zeit
        // gibt es gleich viele Punkte. Sonst wandern Punktejäger in eine Ecke
        // und ein gemeinsames Leaderboard wird wertlos.
        for difficulty in Difficulty.allCases {
            let classic = Scoring.score(input(.classic, difficulty))
            let arrow = Scoring.score(input(.arrow, difficulty))
            #expect(classic.total == arrow.total,
                    Comment(rawValue: "\(difficulty.rawValue): "
                        + "\(classic.total) gegen \(arrow.total)"))
        }
    }

    @Test func breakdownExplainsTheResult() {
        // Die Zeilen tragen **Arten**, keine Texte: der Kern kann ohne Foundation
        // nicht lokalisieren, und die App gibt es in drei Sprachen.
        let b = Scoring.score(input(hints: HintUsage(lettersRevealed: 1),
                                    streak: 3, daily: true))
        let kinds = b.lines.map(\.kind)
        #expect(kinds.first == .base)
        #expect(kinds.last == .total)
        #expect(kinds.contains(.streak))
        #expect(kinds.contains(.daily))
        #expect(kinds.contains(.hints))
        #expect(b.lines.first(where: { $0.kind == .base })?.value == "100"
            || b.lines.first(where: { $0.kind == .base })?.value == "250")

        // Ohne Hilfen gäbe es keine Hilfen-Zeile — und ohne Serie keine Serienzeile.
        let cleanKinds = Scoring.score(input()).lines.map(\.kind)
        #expect(!cleanKinds.contains(.hints))
        #expect(!cleanKinds.contains(.streak))
        #expect(!cleanKinds.contains(.daily))
    }
}
