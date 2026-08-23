/// Ein Schwarzfeldmuster für `classic`. Als Zeilenstrings gespeichert, damit
/// die eingecheckten Templates in `Resources/grids/classic/` von Hand lesbar
/// und reviewbar sind: `#` = Schwarzfeld, `.` = Buchstabenzelle.
public struct GridTemplate: Codable, Sendable, Hashable {
    public let rows: [String]

    public init(rows: [String]) { self.rows = rows }

    public init(size: GridSize, kinds: [CellKind]) {
        self.rows = (0 ..< size.rows).map { r in
            String((0 ..< size.cols).map { c in
                kinds[size.index(Cell(r, c))] == .letter ? "." : "#"
            })
        }
    }

    public var size: GridSize { GridSize(rows: rows.count, cols: rows.first?.count ?? 0) }

    public var kinds: [CellKind] {
        var out: [CellKind] = []
        out.reserveCapacity(size.area)
        for row in rows {
            for ch in row { out.append(ch == "#" ? .block : .letter) }
        }
        return out
    }

    public var blockCount: Int { rows.reduce(0) { $0 + $1.count { $0 == "#" } } }
    public var blockRatio: Double { Double(blockCount) / Double(size.area) }

    public var isWellFormed: Bool {
        guard let w = rows.first?.count, w > 0 else { return false }
        return rows.allSatisfy { $0.count == w && $0.allSatisfy { $0 == "#" || $0 == "." } }
    }

    /// 180°-Rotationssymmetrie — die Auflage, die klassische Gitter „richtig" aussehen lässt.
    public var isRotationallySymmetric: Bool {
        let s = size
        let k = kinds
        for i in 0 ..< s.area {
            let c = s.cell(i)
            let partner = Cell(s.rows - 1 - c.row, s.cols - 1 - c.col)
            if (k[i] == .block) != (k[s.index(partner)] == .block) { return false }
        }
        return true
    }

    public var pretty: String { rows.joined(separator: "\n") }
}

public struct TemplateSet: Codable, Sendable {
    public let templates: [GridTemplate]
    public init(templates: [GridTemplate]) { self.templates = templates }
}
