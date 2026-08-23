/// Klassische Kreuzwortnummerierung: in Lesereihenfolge bekommt jede Zelle, die
/// ein Wort beginnt, die nächste Nummer. Beginnen dort zwei Wörter (waagrecht
/// und senkrecht), teilen sie sich die Nummer.
public enum Numbering {
    public static func numbers(topology: Topology) -> [Int: Int] {
        var starts: [Cell: [Int]] = [:]
        for s in topology.slots { starts[s.start, default: []].append(s.id) }

        var result: [Int: Int] = [:]
        var next = 1
        for i in 0 ..< topology.size.area {
            let cell = topology.size.cell(i)
            guard let ids = starts[cell] else { continue }
            for id in ids.sorted() { result[id] = next }
            next += 1
        }
        return result
    }
}
