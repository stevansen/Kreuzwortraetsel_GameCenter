import Testing
@testable import PuzzleKit

/// Tests für die Eingabelogik. Sie ist der Kern des Spielgefühls und läuft ohne
/// jede Oberfläche — deshalb wird sie hier geprüft und nicht per Snapshot.
@Suite("Eingabe")
struct InputRouterTests {
    /// Ein kleines Handgitter, damit die Erwartungen ablesbar sind:
    ///
    /// ```
    /// A B C # E
    /// F # H # J
    /// K L M N O
    /// ```
    /// Waagrechte Wörter: (0,0)–(0,2), (2,0)–(2,4).
    /// Senkrechte Wörter: (0,0)–(2,0), (0,2)–(2,2), (0,4)–(2,4).
    private func fixture() -> (Puzzle, GridNavigation, PuzzleProgress) {
        let size = GridSize(rows: 3, cols: 5)
        let blocks = GridTemplate(rows: ["...#.", ".#.#.", "....."]).kinds.map { $0 == .block }
        func slot(_ id: Int, _ r: Int, _ c: Int, _ dir: Direction, _ len: Int) -> Entry {
            Entry(slot: Slot(id: id, start: Cell(r, c), direction: dir, length: len),
                  answerID: Int32(id), answer: String(repeating: "A", count: len),
                  clueID: Int32(id), clueText: "Frage \(id)", clueShortText: nil,
                  number: id + 1, arrow: nil, ownerCell: nil)
        }
        let entries = [
            slot(0, 0, 0, .across, 3),
            slot(1, 2, 0, .across, 5),
            slot(2, 0, 0, .down, 3),
            slot(3, 0, 2, .down, 3),
            slot(4, 0, 4, .down, 3),
        ]
        let puzzle = Puzzle(seed: 1, variant: .classic, difficulty: .leicht,
                            generatorVersion: 1, catalogVersion: 1, size: size,
                            layout: .classic(blocks: blocks), entries: entries)
        return (puzzle, GridNavigation(puzzle: puzzle), PuzzleProgress(puzzle: puzzle, deviceID: 1))
    }

    private func router() -> (GridInputRouter, PuzzleProgress) {
        let (_, nav, progress) = fixture()
        return (GridInputRouter(navigation: nav), progress)
    }

    @Test func enteringALetterWritesAndAdvances() {
        let (r, p0) = router()
        var p = p0
        var caret = Caret(cell: Cell(0, 0), direction: .across)
        caret = r.apply(.enter(Alphabet.index(of: "B")!), caret: caret, progress: &p)
        #expect(p.letter(at: 0) == Alphabet.index(of: "B"))
        #expect(caret.cell == Cell(0, 1))
    }

    @Test func advancingStopsAtTheEndOfTheWord() {
        let (r, p0) = router()
        var p = p0
        var caret = Caret(cell: Cell(0, 2), direction: .across)
        caret = r.apply(.enter(1), caret: caret, progress: &p)
        // (0,3) ist ein Schwarzfeld — der Cursor bleibt stehen statt hineinzulaufen.
        #expect(caret.cell == Cell(0, 2))
    }

    @Test func movementSkipsNonLetterCells() {
        let (r, p0) = router()
        var p = p0
        let caret = Caret(cell: Cell(1, 0), direction: .across)
        // (1,1) ist schwarz, (1,2) ist die nächste Buchstabenzelle.
        let moved = r.apply(.move(.across, forward: true), caret: caret, progress: &p)
        #expect(moved.cell == Cell(1, 2))
    }

    @Test func movementStopsAtTheEdge() {
        let (r, p0) = router()
        var p = p0
        let caret = Caret(cell: Cell(0, 0), direction: .across)
        let moved = r.apply(.move(.across, forward: false), caret: caret, progress: &p)
        #expect(moved == caret)
    }

    @Test func toggleOnlyWorksWhereTheOtherDirectionHasAWord() {
        let (r, p0) = router()
        var p = p0
        // (0,0) liegt in beiden Richtungen in einem Wort.
        let crossed = r.apply(.toggleDirection,
                              caret: Caret(cell: Cell(0, 0), direction: .across), progress: &p)
        #expect(crossed.direction == .down)
        // (1,0) liegt nur senkrecht in einem Wort — der Wechsel wird verweigert,
        // statt den Cursor in ein Wort zu setzen, das es nicht gibt.
        let single = r.apply(.toggleDirection,
                             caret: Caret(cell: Cell(1, 0), direction: .down), progress: &p)
        #expect(single.direction == .down)
    }

    @Test func tappingTheActiveCellSwitchesDirection() {
        let (r, p0) = router()
        var p = p0
        let caret = Caret(cell: Cell(0, 0), direction: .across)
        let again = r.apply(.jump(Cell(0, 0)), caret: caret, progress: &p)
        #expect(again.direction == .down)
    }

    @Test func tappingABlockIsIgnored() {
        let (r, p0) = router()
        var p = p0
        let caret = Caret(cell: Cell(0, 0), direction: .across)
        #expect(r.apply(.jump(Cell(0, 3)), caret: caret, progress: &p) == caret)
    }

    @Test func backspaceClearsThenStepsBack() {
        let (r, p0) = router()
        var p = p0
        var caret = Caret(cell: Cell(0, 0), direction: .across)
        caret = r.apply(.enter(1), caret: caret, progress: &p)   // (0,0) belegt, Cursor (0,1)
        // Leere Zelle: zurückgehen und dort löschen.
        caret = r.apply(.deleteBackward, caret: caret, progress: &p)
        #expect(caret.cell == Cell(0, 0))
        #expect(p.letter(at: 0) == nil)

        // Belegte Zelle: nur leeren, stehen bleiben — so korrigiert man einen
        // einzelnen Buchstaben, ohne die Position zu verlieren.
        caret = r.apply(.enter(2), caret: Caret(cell: Cell(0, 1), direction: .across),
                        progress: &p)
        let before = Caret(cell: Cell(0, 1), direction: .across)
        let after = r.apply(.deleteBackward, caret: before, progress: &p)
        #expect(after == before)
        #expect(p.letter(at: 1) == nil)
    }

    @Test func slotSteppingCyclesAndLandsOnTheFirstEmptyCell() {
        let (r, p0) = router()
        var p = p0
        var caret = Caret(cell: Cell(0, 0), direction: .across)
        // Erstes Wort halb füllen, dann weiterspringen und zurück.
        caret = r.apply(.enter(1), caret: caret, progress: &p)
        let next = r.apply(.nextSlot, caret: Caret(cell: Cell(0, 0), direction: .across),
                           progress: &p)
        #expect(next.cell != Cell(0, 0))
        // Zurück ins erste Wort: der Cursor landet auf der ersten *leeren* Zelle.
        let back = r.apply(.selectSlot(0), caret: next, progress: &p)
        #expect(back.cell == Cell(0, 1))
        #expect(back.direction == .across)
    }

    @Test func slotSteppingWrapsAround() {
        let (r, p0) = router()
        var p = p0
        let slots = r.navigation.orderedSlots
        var caret = r.apply(.selectSlot(slots.last!),
                            caret: Caret(cell: Cell(0, 0), direction: .across), progress: &p)
        caret = r.apply(.nextSlot, caret: caret, progress: &p)
        let first = r.apply(.selectSlot(slots.first!),
                            caret: Caret(cell: Cell(0, 0), direction: .across), progress: &p)
        #expect(caret.cell == first.cell)
    }

    @Test func pencilModeSurvivesTheNextLetter() {
        let (r, p0) = router()
        var p = p0
        var caret = Caret(cell: Cell(0, 0), direction: .across)
        caret = r.apply(.togglePencil, caret: caret, progress: &p)
        #expect(p.cells[0].pencil)
        _ = r.apply(.enter(5), caret: caret, progress: &p)
        // Eine unsicher markierte Zelle bleibt unsicher, bis der Spieler das ändert.
        #expect(p.cells[0].pencil)
        #expect(p.letter(at: 0) == 5)
    }

    @Test func navigationOrdersSlotsByNumber() {
        let (_, nav, _) = fixture()
        #expect(nav.orderedSlots == [0, 1, 2, 3, 4])
        #expect(nav.firstLetterCell == Cell(0, 0))
        #expect(nav.isLetter(Cell(0, 0)))
        #expect(!nav.isLetter(Cell(0, 3)))
        #expect(nav.slot(at: Cell(1, 0), direction: .across) == nil)
        #expect(nav.slot(at: Cell(1, 0), direction: .down) == 2)
    }
}
