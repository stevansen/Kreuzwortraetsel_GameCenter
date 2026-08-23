/// Ein zu füllendes Wort: Startzelle, Richtung, Länge.
///
/// Slots sind das **einzige**, was die Füll-Engine vom Layout sieht. Ob die
/// Frage in einer Liste steht oder in einer Nachbarzelle mit Pfeil, ist ihr
/// unbekannt — genau darin liegt der Varianten-Seam.
public struct Slot: Hashable, Codable, Sendable {
    public let id: Int
    public let start: Cell
    public let direction: Direction
    public let length: Int

    public init(id: Int, start: Cell, direction: Direction, length: Int) {
        self.id = id
        self.start = start
        self.direction = direction
        self.length = length
    }

    public var cells: [Cell] {
        let d = direction.delta
        return (0 ..< length).map { Cell(start.row + d.dr * $0, start.col + d.dc * $0) }
    }

    public func cell(at i: Int) -> Cell {
        let d = direction.delta
        return Cell(start.row + d.dr * i, start.col + d.dc * i)
    }
}

/// Ein Slot, den eine Fragezelle besitzt (nur `arrow`).
public struct HostedSlot: Hashable, Codable, Sendable {
    public let slotID: Int
    public let arrow: ArrowKind

    public init(slotID: Int, arrow: ArrowKind) {
        self.slotID = slotID
        self.arrow = arrow
    }
}

/// Eine Fragezelle mit ihren 1–2 Slots (nur `arrow`).
public struct ClueCellPlan: Hashable, Codable, Sendable {
    public let cell: Cell
    /// Nach `slotID` sortiert — Determinismus.
    public let hosted: [HostedSlot]

    public init(cell: Cell, hosted: [HostedSlot]) {
        self.cell = cell
        self.hosted = hosted.sorted { $0.slotID < $1.slotID }
    }
}

/// Das Ergebnis eines `LayoutProvider`: Zellklassifikation, Slots, Kreuzungen.
public struct Topology: Sendable {
    public let size: GridSize
    /// Nach Zellindex.
    public let kinds: [CellKind]
    public let slots: [Slot]
    /// Zellindex -> IDs der Slots, die durch diese Zelle laufen.
    public let slotsByCell: [[Int]]
    /// Leer bei `classic`.
    public let cluePlans: [ClueCellPlan]

    public init(size: GridSize, kinds: [CellKind], slots: [Slot], cluePlans: [ClueCellPlan]) {
        self.size = size
        self.kinds = kinds
        self.slots = slots
        self.cluePlans = cluePlans
        var byCell = [[Int]](repeating: [], count: size.area)
        for s in slots {
            for c in s.cells { byCell[size.index(c)].append(s.id) }
        }
        self.slotsByCell = byCell
    }

    public var letterCellCount: Int { kinds.count { $0 == .letter } }

    /// Slot-Paare, die sich eine Zelle teilen: `crossings[slotID] = [(otherSlot, myOffset, otherOffset)]`
    public func crossings() -> [[(other: Int, mine: Int, theirs: Int)]] {
        var out = [[(other: Int, mine: Int, theirs: Int)]](repeating: [], count: slots.count)
        for s in slots {
            for (i, c) in s.cells.enumerated() {
                for otherID in slotsByCell[size.index(c)] where otherID != s.id {
                    let other = slots[otherID]
                    guard let j = other.cells.firstIndex(of: c) else { continue }
                    out[s.id].append((other: otherID, mine: i, theirs: j))
                }
            }
        }
        return out
    }

    /// Anteil der Buchstabenzellen, die von mindestens zwei Slots gedeckt sind.
    public var crossRatio: Double {
        var letters = 0, crossed = 0
        for i in 0 ..< size.area where kinds[i] == .letter {
            letters += 1
            if slotsByCell[i].count >= 2 { crossed += 1 }
        }
        return letters == 0 ? 0 : Double(crossed) / Double(letters)
    }
}
