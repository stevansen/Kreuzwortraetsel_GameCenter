/// Wo der Spieler gerade steht: Zelle plus Laufrichtung.
public struct Caret: Equatable, Sendable, Hashable {
    public var cell: Cell
    public var direction: Direction

    public init(cell: Cell, direction: Direction) {
        self.cell = cell
        self.direction = direction
    }
}

/// Die navigierbare Struktur eines Rätsels: welche Zelle gehört in welcher
/// Richtung zu welchem Wort, und in welcher Reihenfolge stehen die Wörter.
///
/// Wird einmal aus einem `Puzzle` gebaut und dann nur gelesen.
public struct GridNavigation: Sendable {
    public let size: GridSize
    public let kinds: [CellKind]
    /// Zellindex → Slot-ID des waagrechten Worts, `-1` = keins.
    private let acrossSlot: [Int]
    /// Zellindex → Slot-ID des senkrechten Worts, `-1` = keins.
    private let downSlot: [Int]
    /// Slot-ID → Eintrag.
    private let entryBySlot: [Int: Entry]
    /// Slot-IDs in Anzeigereihenfolge: bei `classic` nach Nummer, bei `arrow`
    /// nach Position der Fragezelle.
    public let orderedSlots: [Int]

    public init(puzzle: Puzzle) {
        self.size = puzzle.size
        self.kinds = puzzle.kinds
        var across = [Int](repeating: -1, count: puzzle.size.area)
        var down = [Int](repeating: -1, count: puzzle.size.area)
        var bySlot: [Int: Entry] = [:]
        for e in puzzle.entries {
            bySlot[e.slot.id] = e
            for c in e.slot.cells {
                let i = puzzle.size.index(c)
                guard i >= 0, i < across.count else { continue }
                if e.slot.direction == .across { across[i] = e.slot.id } else { down[i] = e.slot.id }
            }
        }
        self.acrossSlot = across
        self.downSlot = down
        self.entryBySlot = bySlot
        self.orderedSlots = puzzle.entries.sorted { a, b in
            if let na = a.number, let nb = b.number, na != nb { return na < nb }
            if let oa = a.ownerCell, let ob = b.ownerCell, oa != ob { return oa < ob }
            if a.slot.start != b.slot.start { return a.slot.start < b.slot.start }
            return a.slot.direction == .across
        }.map(\.slot.id)
    }

    public func isLetter(_ cell: Cell) -> Bool {
        size.contains(cell) && kinds[size.index(cell)] == .letter
    }

    public func slot(at cell: Cell, direction: Direction) -> Int? {
        guard size.contains(cell) else { return nil }
        let id = direction == .across ? acrossSlot[size.index(cell)] : downSlot[size.index(cell)]
        return id >= 0 ? id : nil
    }

    public func entry(_ slotID: Int) -> Entry? { entryBySlot[slotID] }

    /// Die Richtung, in der diese Zelle überhaupt ein Wort hat — bevorzugt die
    /// gewünschte. Ungekreuzte Buchstaben haben nur eine.
    public func viableDirection(at cell: Cell, preferring wanted: Direction) -> Direction? {
        if slot(at: cell, direction: wanted) != nil { return wanted }
        if slot(at: cell, direction: wanted.opposite) != nil { return wanted.opposite }
        return nil
    }

    /// Erste Buchstabenzelle in Lesereihenfolge — Startposition beim Öffnen.
    public var firstLetterCell: Cell? {
        (0 ..< size.area).first { kinds[$0] == .letter }.map(size.cell)
    }

    public func cells(ofSlot slotID: Int) -> [Cell] {
        entryBySlot[slotID]?.slot.cells ?? []
    }
}
