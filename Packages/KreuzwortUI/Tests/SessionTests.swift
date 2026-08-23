import Testing
import PuzzleKit
@testable import KreuzwortUI

@Suite("Sitzung")
struct SessionTests {
    /// Kleines Handgitter mit echten Lösungswörtern, damit „gelöst" prüfbar ist.
    ///
    /// ```
    /// B R O T
    /// A . . E
    /// U . . E
    /// M E H R
    /// ```
    private func fixture() -> Puzzle {
        let size = GridSize(rows: 4, cols: 4)
        let blocks = GridTemplate(rows: ["....", "..##", "..##", "...."])
            .kinds.map { $0 == .block }
        func entry(_ id: Int, _ r: Int, _ c: Int, _ dir: Direction, _ word: String) -> Entry {
            Entry(slot: Slot(id: id, start: Cell(r, c), direction: dir, length: word.count),
                  answerID: Int32(id), answer: word, clueID: Int32(id),
                  clueText: "Frage zu \(word)", clueShortText: word.prefix(4).description,
                  number: id + 1, arrow: nil, ownerCell: nil)
        }
        // Gitter: Zeile 0 "BROT", Zeile 3 "MEHR", Spalte 0 "BAUM", Spalte 3 "TEER"
        let entries = [
            entry(0, 0, 0, .across, "BROT"),
            entry(1, 3, 0, .across, "MEHR"),
            entry(2, 0, 0, .down, "BAUM"),
            entry(3, 0, 3, .down, "TEER"),
        ]
        return Puzzle(seed: 1, variant: .classic, difficulty: .leicht,
                      generatorVersion: 1, catalogVersion: 1, size: size,
                      layout: .classic(blocks: blocks), entries: entries)
    }

    @Test func startsOnTheFirstLetterCell() {
        let s = PuzzleSession(puzzle: fixture())
        #expect(s.caret.cell == Cell(0, 0))
        #expect(s.caret.direction == .across)
        #expect(!s.isSolved)
        #expect(s.breakdown == nil)
    }

    @Test func activeEntryFollowsTheCaret() throws {
        let s = PuzzleSession(puzzle: fixture())
        #expect(s.activeEntry?.answer == "BROT")
        s.apply(.toggleDirection)
        #expect(s.activeEntry?.answer == "BAUM")
        #expect(s.activeCells.count == 4)
    }

    @Test func solvingComputesTheScoreExactlyOnce() throws {
        let s = PuzzleSession(puzzle: fixture())
        s.fillWithSolution()
        #expect(s.isSolved)
        let breakdown = try #require(s.breakdown)
        #expect(breakdown.total > 0)
        #expect(s.progress.scoreAwarded == breakdown.total)

        // Nochmal füllen darf nicht erneut gutschreiben.
        s.fillWithSolution()
        #expect(s.progress.scoreAwarded == breakdown.total)
    }

    @Test func almostSolvedIsNotSolved() {
        let s = PuzzleSession(puzzle: fixture())
        s.fillWithSolution(except: 1)   // eine Zelle bleibt leer
        #expect(!s.isSolved)
        #expect(s.breakdown == nil)
    }

    @Test func revealingALetterCountsAndCostsTheCleanBonus() throws {
        let s = PuzzleSession(puzzle: fixture())
        #expect(s.canRevealLetter)          // Stufe „Leicht" erlaubt alles
        #expect(s.revealLetter())
        #expect(s.progress.hints.lettersRevealed == 1)
        #expect(s.progress.letter(at: 0) == Alphabet.index(of: "B"))
        s.fillWithSolution()
        let breakdown = try #require(s.breakdown)
        #expect(breakdown.cleanBonus == 1.0)
        #expect(breakdown.hintPenalty == 5)
    }

    @Test func revealingAWordFillsTheWholeSlot() {
        let s = PuzzleSession(puzzle: fixture())
        #expect(s.revealWord())
        for (i, ch) in "BROT".enumerated() {
            #expect(s.progress.letter(at: i) == Alphabet.index(of: ch))
        }
        #expect(s.progress.hints.wordsRevealed == 1)
    }

    @Test func checkFlagsOnlyWrongLettersNotEmptyOnes() {
        let s = PuzzleSession(puzzle: fixture())
        // Ein falscher Buchstabe, der Rest leer.
        s.apply(.enter(Alphabet.index(of: "X")!))
        let wrong = s.checkGrid()
        #expect(wrong == 1, Comment(rawValue: "\(wrong) markiert — leere Zellen "
            + "dürfen nicht als falsch gelten, sonst leuchtet halb das Gitter"))
        #expect(s.flaggedCells == [0])
        #expect(s.progress.hints.failedChecks == 1)
    }

    @Test func typingClearsAStaleErrorFlag() {
        let s = PuzzleSession(puzzle: fixture())
        s.apply(.enter(Alphabet.index(of: "X")!))
        _ = s.checkGrid()
        #expect(!s.flaggedCells.isEmpty)
        s.apply(.jump(Cell(0, 0)))
        s.apply(.enter(Alphabet.index(of: "B")!))
        #expect(s.flaggedCells.isEmpty)
    }

    @Test func hintPolicyIsHonoured() {
        // Experte erlaubt nur die Endprüfung.
        let hard = Puzzle(seed: 1, variant: .classic, difficulty: .experte,
                          generatorVersion: 1, catalogVersion: 1,
                          size: fixture().size, layout: fixture().layout,
                          entries: fixture().entries)
        let s = PuzzleSession(puzzle: hard)
        #expect(!s.canRevealLetter)
        #expect(!s.canRevealWord)
        #expect(!s.canCheckGrid)
        #expect(s.hasFinalCheckOnly)
        #expect(!s.revealLetter())
        #expect(s.checkGrid() == 0)
        #expect(s.progress.hints.isClean)
    }

    @Test func clockUsesAMonotonicSourceAndPauses() {
        let s = PuzzleSession(puzzle: fixture())
        #expect(s.elapsedSeconds == 0)
        #expect(!s.isRunning)
        s.apply(.enter(1))              // erste Eingabe startet die Uhr
        #expect(s.isRunning)
        s.pause()
        #expect(!s.isRunning)
        let frozen = s.elapsedSeconds
        #expect(s.elapsedSeconds == frozen)
        #expect(s.progress.elapsedSeconds == frozen)
    }

    @Test func solvedSessionIgnoresFurtherInput() {
        let s = PuzzleSession(puzzle: fixture())
        s.fillWithSolution()
        let before = s.caret
        s.apply(.move(.across, forward: true))
        #expect(s.caret == before)
        #expect(!s.isRunning)
    }

    @Test func resumingFromStoredProgressKeepsTimeAndHints() {
        let puzzle = fixture()
        var stored = PuzzleProgress(puzzle: puzzle, deviceID: 3)
        stored.elapsedSeconds = 123
        stored.hints = HintUsage(lettersRevealed: 2)
        stored.set(Alphabet.index(of: "B"), at: 0)

        let s = PuzzleSession(puzzle: puzzle, progress: stored)
        #expect(s.elapsedSeconds == 123)
        #expect(s.progress.hints.lettersRevealed == 2)
        #expect(s.progress.letter(at: 0) == Alphabet.index(of: "B"))
    }
}

@Suite("Fähigkeiten")
struct SurfaceTests {
    @Test func livingRoomDoesNotRenderCluesInCells() {
        // Auf drei Metern ist eine 16-Zeichen-Kurzfrage in einer Zelle nicht
        // lesbar — dort trägt die Clue-Leiste alles.
        #expect(!SurfaceCapabilities.livingRoom.rendersInCellClues)
        #expect(SurfaceCapabilities.livingRoom.clueBarIsPrimary)
        #expect(SurfaceCapabilities.touch.rendersInCellClues)
        #expect(!SurfaceCapabilities.touch.clueBarIsPrimary)
    }

    @Test func touchTargetsAreLargerThanPointerTargets() {
        #expect(SurfaceCapabilities.touch.minimumCellSide
            > SurfaceCapabilities.desktop.minimumCellSide)
        #expect(SurfaceCapabilities.livingRoom.minimumCellSide
            > SurfaceCapabilities.touch.minimumCellSide)
    }
}
