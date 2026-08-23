import Observation
import PuzzleKit

/// Der Spielzustand einer Rätselsitzung: Rätsel, Spielstand, Cursor, Uhr, Hilfen.
///
/// Kennt keine Variante und keine Plattform. Ob die Frage in einer Zelle steht
/// oder in einer Liste, entscheidet die Ansicht anhand von `SurfaceCapabilities`;
/// ob es Pfeile oder Nummern gibt, steckt im `Puzzle`.
@Observable
public final class PuzzleSession {
    public let puzzle: Puzzle
    public let navigation: GridNavigation
    public let profile: DifficultyProfile

    public private(set) var progress: PuzzleProgress
    public private(set) var caret: Caret
    public private(set) var isSolved: Bool = false
    /// Erst nach dem Lösen gesetzt — die Grundlage des Abschlussbildschirms.
    public private(set) var breakdown: ScoreBreakdown?
    /// Zellen, die eine Prüfung als falsch gemeldet hat. Wird bei Eingabe geleert.
    public private(set) var flaggedCells: Set<Int> = []

    private let router: GridInputRouter
    private let solution: [Letter?]
    private let letterCells: Int
    private let clock = ContinuousClock()
    private var runningSince: ContinuousClock.Instant?
    /// Bereits verbuchte Spielzeit. Die laufende Sitzung kommt hinzu.
    private var accumulated: Double

    public init(puzzle: Puzzle, progress: PuzzleProgress? = nil, deviceID: UInt32 = 1) {
        self.puzzle = puzzle
        self.navigation = GridNavigation(puzzle: puzzle)
        self.profile = DifficultyProfile.profile(puzzle.variant, puzzle.difficulty)
        let start = progress ?? PuzzleProgress(puzzle: puzzle, deviceID: deviceID)
        self.progress = start
        self.accumulated = start.elapsedSeconds
        self.router = GridInputRouter(navigation: GridNavigation(puzzle: puzzle))
        self.solution = puzzle.solutionLetters()
        self.letterCells = puzzle.letterCellCount
        self.caret = Caret(cell: navigationStart(puzzle: puzzle), direction: .across)
        self.isSolved = start.completedAtEpoch != nil
    }

    private static func firstCell(of puzzle: Puzzle) -> Cell {
        GridNavigation(puzzle: puzzle).firstLetterCell ?? Cell(0, 0)
    }

    // MARK: - Uhr
    //
    // Monotone Uhr (`ContinuousClock`), nicht die Wanduhr: eine Zeitumstellung
    // oder ein Nutzer, der die Systemzeit dreht, darf die Spielzeit nicht
    // verändern. Das ist gleichzeitig die Grundlage der Plausibilitätsgrenze
    // beim Punktestand.

    public var elapsedSeconds: Double {
        guard let runningSince else { return accumulated }
        let d = clock.now - runningSince
        return accumulated + Double(d.components.seconds)
            + Double(d.components.attoseconds) / 1e18
    }

    public var isRunning: Bool { runningSince != nil }

    public func start() {
        guard runningSince == nil, !isSolved else { return }
        runningSince = clock.now
    }

    public func pause() {
        guard runningSince != nil else { return }
        accumulated = elapsedSeconds
        runningSince = nil
        progress.elapsedSeconds = accumulated
    }

    // MARK: - Eingabe

    public func apply(_ command: GridCommand) {
        guard !isSolved else { return }
        start()
        // Jede Eingabe entwertet eine vorherige Fehlermarkierung: sonst bleiben
        // rote Zellen stehen, die der Spieler längst korrigiert hat.
        if case .enter = command { flaggedCells.removeAll() }
        if case .clear = command { flaggedCells.removeAll() }
        if case .deleteBackward = command { flaggedCells.removeAll() }
        caret = router.apply(command, caret: caret, progress: &progress)
        checkSolved()
    }

    /// Der Eintrag, in dem der Cursor gerade steht — Quelle für Clue-Leiste
    /// und Hervorhebung.
    public var activeEntry: Entry? {
        navigation.slot(at: caret.cell, direction: caret.direction)
            .flatMap(navigation.entry)
    }

    public var activeCells: [Cell] {
        guard let id = navigation.slot(at: caret.cell, direction: caret.direction)
        else { return [caret.cell] }
        return navigation.cells(ofSlot: id)
    }

    // MARK: - Hilfen

    public var canRevealLetter: Bool { profile.hints.contains(.revealLetter) && !isSolved }
    public var canRevealWord: Bool { profile.hints.contains(.revealWord) && !isSolved }
    public var canCheckGrid: Bool { profile.hints.contains(.checkGrid) && !isSolved }
    /// Auf den harten Stufen gibt es nur die Prüfung am Ende.
    public var hasFinalCheckOnly: Bool { profile.hints.contains(.finalCheckOnly) }

    @discardableResult
    public func revealLetter() -> Bool {
        guard canRevealLetter else { return false }
        let index = puzzle.size.index(caret.cell)
        guard let expected = solution[index] else { return false }
        progress.hints.lettersRevealed += 1
        progress.set(expected, at: index)
        flaggedCells.remove(index)
        checkSolved()
        return true
    }

    @discardableResult
    public func revealWord() -> Bool {
        guard canRevealWord, let entry = activeEntry else { return false }
        progress.hints.wordsRevealed += 1
        for cell in entry.slot.cells {
            let i = puzzle.size.index(cell)
            if let expected = solution[i] { progress.set(expected, at: i) }
            flaggedCells.remove(i)
        }
        checkSolved()
        return true
    }

    /// Markiert falsch belegte Zellen. Leere Zellen gelten nicht als falsch —
    /// sonst leuchtet beim ersten Klick das halbe Gitter rot.
    @discardableResult
    public func checkGrid() -> Int {
        guard canCheckGrid else { return 0 }
        progress.hints.gridChecks += 1
        var wrong: Set<Int> = []
        for (i, expected) in solution.enumerated() {
            guard let expected, let actual = progress.letter(at: i) else { continue }
            if actual != expected { wrong.insert(i) }
        }
        flaggedCells = wrong
        if !wrong.isEmpty { progress.hints.failedChecks += 1 }
        return wrong.count
    }

    // MARK: - Abschluss

    private func checkSolved() {
        guard !isSolved, progress.filledCells >= letterCells else { return }
        guard progress.isSolved(of: puzzle) else { return }
        finish()
    }

    /// Rechnet die Punkte ab — genau einmal, gebunden an den Abschlusszeitpunkt.
    private func finish(nowEpoch: Double? = nil, streakDays: Int = 0, isDaily: Bool = false) {
        guard progress.scoreAwarded == nil else { return }
        pause()
        isSolved = true
        flaggedCells.removeAll()
        let input = ScoreInput(variant: puzzle.variant, difficulty: puzzle.difficulty,
                               letterCells: letterCells, elapsedSeconds: elapsedSeconds,
                               hints: progress.hints, streakDays: streakDays, isDaily: isDaily)
        let result = Scoring.score(input)
        breakdown = result
        progress.completedAtEpoch = nowEpoch ?? 0
        progress.scoreAwarded = result.total
    }

    /// Für Tests und die Vorschau: den Spielstand auf die Lösung setzen.
    public func fillWithSolution(except skipped: Int = 0) {
        var remaining = skipped
        for (i, expected) in solution.enumerated() {
            guard let expected else { continue }
            if remaining > 0 { remaining -= 1; continue }
            progress.set(expected, at: i)
        }
        checkSolved()
    }
}

private func navigationStart(puzzle: Puzzle) -> Cell {
    GridNavigation(puzzle: puzzle).firstLetterCell ?? Cell(0, 0)
}
