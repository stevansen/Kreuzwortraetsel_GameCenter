/// Eine Gitterposition. `Comparable` in Lesereihenfolge — wird überall zum
/// **deterministischen** Sortieren gebraucht.
public struct Cell: Hashable, Comparable, Codable, Sendable {
    public var row: Int
    public var col: Int

    public init(_ row: Int, _ col: Int) { self.row = row; self.col = col }

    public static func < (a: Cell, b: Cell) -> Bool {
        a.row != b.row ? a.row < b.row : a.col < b.col
    }

    public func offset(_ dr: Int, _ dc: Int) -> Cell { Cell(row + dr, col + dc) }
}

public struct GridSize: Hashable, Codable, Sendable {
    public var rows: Int
    public var cols: Int

    public init(rows: Int, cols: Int) { self.rows = rows; self.cols = cols }
    public init(square n: Int) { self.init(rows: n, cols: n) }

    public var area: Int { rows * cols }

    public func contains(_ c: Cell) -> Bool {
        c.row >= 0 && c.row < rows && c.col >= 0 && c.col < cols
    }

    public func index(_ c: Cell) -> Int { c.row * cols + c.col }
    public func cell(_ i: Int) -> Cell { Cell(i / cols, i % cols) }

    /// Alle Zellen in Lesereihenfolge.
    public var allCells: [Cell] { (0 ..< area).map(cell) }

    public var label: String { "\(cols)×\(rows)" }
}

public enum Direction: UInt8, Codable, Sendable, CaseIterable {
    case across, down

    public var delta: (dr: Int, dc: Int) { self == .across ? (0, 1) : (1, 0) }
    public var opposite: Direction { self == .across ? .down : .across }
    /// Nur für CLI-Ausgabe und Debugging, siehe `PuzzleVariant.debugLabel`.
    public var debugLabel: String { self == .across ? "waagrecht" : "senkrecht" }
}

public enum CellKind: UInt8, Codable, Sendable {
    /// Buchstabenzelle — der Spieler trägt hier ein.
    case letter
    /// Schwarzfeld (nur `classic`).
    case block
    /// Fragezelle (nur `arrow`) — trägt 1–2 Kurzfragen mit Pfeil.
    case clue
}
