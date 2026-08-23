/// Ein maximaler Lauf zusammenhängender Buchstabenzellen in einer Richtung.
public struct Run: Hashable, Sendable {
    public let start: Cell
    public let direction: Direction
    public let length: Int

    public var cells: [Cell] {
        let d = direction.delta
        return (0 ..< length).map { Cell(start.row + d.dr * $0, start.col + d.dc * $0) }
    }
}

public enum GridRuns {
    /// Alle maximalen Läufe von Buchstabenzellen, in Lesereihenfolge.
    ///
    /// Läufe sind die gemeinsame Sprache beider Layouts: bei `classic` wird
    /// jeder Lauf ein Slot, bei `arrow` jeder Lauf ab Mindestlänge — und Läufe
    /// der Länge 2 sind in **beiden** Varianten verboten, weil zwei
    /// nebeneinanderliegende Buchstaben immer ein Wort bilden müssen.
    public static func runs(size: GridSize, kinds: [CellKind]) -> [Run] {
        var out: [Run] = []
        for dir in Direction.allCases {
            let outer = dir == .across ? size.rows : size.cols
            let inner = dir == .across ? size.cols : size.rows
            for a in 0 ..< outer {
                var i = 0
                while i < inner {
                    let cell = dir == .across ? Cell(a, i) : Cell(i, a)
                    if kinds[size.index(cell)] != .letter { i += 1; continue }
                    var len = 0
                    var j = i
                    while j < inner {
                        let c = dir == .across ? Cell(a, j) : Cell(j, a)
                        if kinds[size.index(c)] != .letter { break }
                        len += 1; j += 1
                    }
                    out.append(Run(start: cell, direction: dir, length: len))
                    i = j
                }
            }
        }
        return out.sorted {
            if $0.direction != $1.direction { return $0.direction == .across }
            return $0.start < $1.start
        }
    }

    /// Sind alle weißen Zellen orthogonal zusammenhängend?
    public static func lettersAreConnected(size: GridSize, kinds: [CellKind]) -> Bool {
        guard let first = (0 ..< size.area).first(where: { kinds[$0] == .letter }) else { return true }
        var seen = [Bool](repeating: false, count: size.area)
        var stack = [first]
        seen[first] = true
        var count = 1
        while let i = stack.popLast() {
            let c = size.cell(i)
            for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let n = c.offset(dr, dc)
                guard size.contains(n) else { continue }
                let ni = size.index(n)
                if kinds[ni] == .letter, !seen[ni] {
                    seen[ni] = true; count += 1; stack.append(ni)
                }
            }
        }
        return count == kinds.count { $0 == .letter }
    }

    /// Slot-Graph zusammenhängend? (Slots, die sich eine Zelle teilen, sind benachbart.)
    public static func slotGraphIsConnected(topology: Topology) -> Bool {
        guard !topology.slots.isEmpty else { return true }
        var adjacency = [[Int]](repeating: [], count: topology.slots.count)
        for ids in topology.slotsByCell where ids.count > 1 {
            for a in ids { for b in ids where a != b { adjacency[a].append(b) } }
        }
        var seen = [Bool](repeating: false, count: topology.slots.count)
        var stack = [0]
        seen[0] = true
        var n = 1
        while let s = stack.popLast() {
            for t in adjacency[s] where !seen[t] { seen[t] = true; n += 1; stack.append(t) }
        }
        return n == topology.slots.count
    }
}
