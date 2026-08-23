/// Der Zustand einer Zelle beim Spieler.
///
/// Jede Zelle ist ein eigenes **LWW-Register**: sie trägt ihren eigenen Stempel.
/// Der Grund ist ein Szenario, das ohne das hier Arbeit vernichtet — iPhone und
/// iPad beide offline am selben Rätsel. Last-Writer-Wins auf dem ganzen
/// Datensatz würde die Eingaben eines Geräts wegwerfen, und zwar lautlos.
public struct CellState: Codable, Sendable, Hashable {
    public var letter: Letter?
    /// Als unsicher markiert („Pencil-Modus").
    public var pencil: Bool
    /// Lamport-Zähler des schreibenden Geräts.
    public var stamp: UInt64
    /// Tiebreak bei gleichem Zähler.
    public var deviceID: UInt32

    public init(letter: Letter? = nil, pencil: Bool = false,
                stamp: UInt64 = 0, deviceID: UInt32 = 0) {
        self.letter = letter
        self.pencil = pencil
        self.stamp = stamp
        self.deviceID = deviceID
    }

    public static let empty = CellState()

    /// Höherer Stempel gewinnt, bei Gleichstand die höhere Geräte-ID.
    /// Kommutativ und idempotent — Voraussetzung für reihenfolgeunabhängigen Sync.
    public static func merged(_ a: CellState, _ b: CellState) -> CellState {
        if a.stamp != b.stamp { return a.stamp > b.stamp ? a : b }
        if a.deviceID != b.deviceID { return a.deviceID > b.deviceID ? a : b }
        return a
    }
}

/// Der synchronisierte Spielstand eines Rätsels.
///
/// Enthält **nicht** das Rätsel, nur seinen Seed: jedes Gerät regeneriert das
/// Gitter bit-identisch. Ein Datensatz ist damit rund 20 Bytes plus Buchstaben.
///
/// Bewusst ohne Foundation: keine `Date`, kein `TimeInterval`. Zeiten sind
/// Sekunden als `Double`, Zeitpunkte Sekunden seit Epoche. `PuzzleKit` muss für
/// jede Plattform bauen und in der CLI laufen.
public struct PuzzleProgress: Codable, Sendable {
    public let puzzleID: String
    public let seed: UInt64
    public let variant: PuzzleVariant
    public let difficulty: Difficulty
    public let generatorVersion: Int
    public let catalogVersion: Int

    /// Nach Zellindex. Nicht-Buchstabenzellen bleiben leer.
    public var cells: [CellState]
    /// Spielzeit in Sekunden, monotone Uhr. Merge = Maximum.
    public var elapsedSeconds: Double
    public var hints: HintUsage
    /// Sekunden seit Epoche. Merge = frühester Nicht-Null-Wert.
    public var completedAtEpoch: Double?
    /// Genau einmal gutgeschrieben, gebunden an `completedAtEpoch`.
    public var scoreAwarded: Int?
    /// Lamport-Uhr dieses Geräts.
    public var clock: UInt64
    public let deviceID: UInt32

    public init(puzzle: Puzzle, deviceID: UInt32) {
        self.puzzleID = puzzle.id
        self.seed = puzzle.seed
        self.variant = puzzle.variant
        self.difficulty = puzzle.difficulty
        self.generatorVersion = puzzle.generatorVersion
        self.catalogVersion = puzzle.catalogVersion
        self.cells = [CellState](repeating: .empty, count: puzzle.size.area)
        self.elapsedSeconds = 0
        self.hints = .none
        self.completedAtEpoch = nil
        self.scoreAwarded = nil
        self.clock = 0
        self.deviceID = deviceID
    }

    public init(puzzleID: String, seed: UInt64, variant: PuzzleVariant,
                difficulty: Difficulty, generatorVersion: Int, catalogVersion: Int,
                cells: [CellState], elapsedSeconds: Double, hints: HintUsage,
                completedAtEpoch: Double?, scoreAwarded: Int?, clock: UInt64,
                deviceID: UInt32) {
        self.puzzleID = puzzleID
        self.seed = seed
        self.variant = variant
        self.difficulty = difficulty
        self.generatorVersion = generatorVersion
        self.catalogVersion = catalogVersion
        self.cells = cells
        self.elapsedSeconds = elapsedSeconds
        self.hints = hints
        self.completedAtEpoch = completedAtEpoch
        self.scoreAwarded = scoreAwarded
        self.clock = clock
        self.deviceID = deviceID
    }

    // MARK: - Eingabe

    /// Setzt einen Buchstaben und stempelt die Zelle.
    public mutating func set(_ letter: Letter?, at cellIndex: Int, pencil: Bool = false) {
        guard cells.indices.contains(cellIndex) else { return }
        clock += 1
        cells[cellIndex] = CellState(letter: letter, pencil: pencil,
                                     stamp: clock, deviceID: deviceID)
    }

    public func letter(at cellIndex: Int) -> Letter? {
        cells.indices.contains(cellIndex) ? cells[cellIndex].letter : nil
    }

    public var filledCells: Int { cells.count { $0.letter != nil } }

    /// Anteil der belegten Buchstabenzellen — für „Weiterspielen: 62 % gefüllt".
    public func completion(letterCells: Int) -> Double {
        letterCells == 0 ? 0 : min(1, Double(filledCells) / Double(letterCells))
    }

    /// Stimmt der Spielstand mit der Lösung überein?
    ///
    /// Vergleicht gegen den Lösungshash statt gegen die Buchstaben, damit dieselbe
    /// Prüfung auch nach einem Sync greift, bei dem nur der Seed übertragen wurde.
    public func isSolved(of puzzle: Puzzle) -> Bool {
        guard puzzle.id == puzzleID else { return false }
        let solution = puzzle.solutionLetters()
        guard solution.count == cells.count else { return false }
        for (i, expected) in solution.enumerated() {
            guard let expected else { continue }
            if cells[i].letter != expected { return false }
        }
        return true
    }

    // MARK: - Zusammenführen

    /// Führt zwei Spielstände desselben Rätsels zusammen.
    ///
    /// Kommutativ und idempotent: `merged(a, b) == merged(b, a)` und
    /// `merged(a, a) == a`. Ohne diese Eigenschaft hängt das Ergebnis davon ab,
    /// in welcher Reihenfolge zwei Geräte sich melden — und das ist genau der
    /// Fehler, den ein Nutzer sofort bemerkt und nicht verzeiht.
    public static func merged(_ a: PuzzleProgress, _ b: PuzzleProgress) -> PuzzleProgress {
        guard a.puzzleID == b.puzzleID, a.cells.count == b.cells.count else { return a }

        var cells = a.cells
        for i in cells.indices { cells[i] = CellState.merged(a.cells[i], b.cells[i]) }

        // Der frühere Abschluss gewinnt, und die Gutschrift folgt ihm: sonst
        // bekäme dasselbe Rätsel auf zwei Geräten zweimal Punkte.
        let completed: Double?
        let awarded: Int?
        switch (a.completedAtEpoch, b.completedAtEpoch) {
        case (nil, nil): completed = nil; awarded = nil
        case (let x?, nil): completed = x; awarded = a.scoreAwarded
        case (nil, let y?): completed = y; awarded = b.scoreAwarded
        case (let x?, let y?):
            if x < y { completed = x; awarded = a.scoreAwarded }
            else if y < x { completed = y; awarded = b.scoreAwarded }
            else { completed = x; awarded = max(a.scoreAwarded ?? 0, b.scoreAwarded ?? 0) }
        }

        return PuzzleProgress(
            puzzleID: a.puzzleID, seed: a.seed, variant: a.variant,
            difficulty: a.difficulty, generatorVersion: a.generatorVersion,
            catalogVersion: a.catalogVersion, cells: cells,
            elapsedSeconds: max(a.elapsedSeconds, b.elapsedSeconds),
            hints: HintUsage.merged(a.hints, b.hints),
            completedAtEpoch: completed, scoreAwarded: awarded,
            clock: max(a.clock, b.clock),
            // Die Geräte-ID des Empfängers bleibt: der zusammengeführte Stand
            // gehört dem Gerät, das ihn hält.
            deviceID: a.deviceID)
    }
}
