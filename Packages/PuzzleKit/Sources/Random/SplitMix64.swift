/// Seedbarer RNG. Der **einzige** erlaubte Zufall im Generatorpfad.
///
/// `SystemRandomNumberGenerator`, `arc4random`, `Date()` und `UUID()` sind dort
/// verboten — `DeterminismScanTests` prüft das per Quellcode-Scan.
///
/// Auch die Ziehalgorithmen sind hier ausformuliert statt aus der Stdlib
/// geliehen: `Array.shuffled(using:)` gibt keine Stabilität über Swift-Versionen
/// zu, und genau davon hängt hier die Reproduzierbarkeit ab.
public struct SplitMix64: Sendable {
    private var state: UInt64

    public init(seed: UInt64) { self.state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Gleichverteilt in `0 ..< n`, per Rejection — kein Modulo-Bias.
    public mutating func int(below n: Int) -> Int {
        precondition(n > 0)
        let bound = UInt64(n)
        let limit = UInt64.max - (UInt64.max % bound) - 1
        var r = next()
        while r > limit { r = next() }
        return Int(r % bound)
    }

    public mutating func double01() -> Double {
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Fisher–Yates, eigene Implementierung (siehe Typkommentar).
    public mutating func shuffle<T>(_ a: inout [T]) {
        guard a.count > 1 else { return }
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            let j = int(below: i + 1)
            if i != j { a.swapAt(i, j) }
        }
    }

    public mutating func shuffled<T>(_ a: [T]) -> [T] {
        var copy = a
        shuffle(&copy)
        return copy
    }

    /// Gewichtete Ziehung ohne Zurücklegen — liefert Indizes in Ziehreihenfolge.
    /// Gewichte <= 0 werden als 0 behandelt und können nur ganz am Ende erscheinen.
    public mutating func weightedOrder(_ weights: [Double], limit: Int) -> [Int] {
        var remaining = Array(weights.indices)
        let w = weights.map { $0 > 0 ? $0 : 0 }
        var out: [Int] = []
        out.reserveCapacity(min(limit, remaining.count))
        while out.count < limit, !remaining.isEmpty {
            var total = 0.0
            for i in remaining { total += w[i] }
            var pick = remaining.count - 1
            if total > 0 {
                var r = double01() * total
                for (k, i) in remaining.enumerated() {
                    r -= w[i]
                    if r <= 0 { pick = k; break }
                }
            } else {
                pick = int(below: remaining.count)
            }
            out.append(remaining[pick])
            remaining.remove(at: pick)
        }
        return out
    }

    /// Leitet einen neuen Seed ab (für Wiederholversuche mit anderem Layout).
    public static func derive(_ seed: UInt64, _ salt: UInt64) -> UInt64 {
        var g = SplitMix64(seed: seed &+ (salt &* 0x9E37_79B9_7F4A_7C15))
        return g.next()
    }
}

public extension SplitMix64 {
    /// Deterministischer Streuschlüssel — für Auswahl ohne Sortier-Instabilität.
    static func mix(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var g = SplitMix64(seed: a &* 0x9E37_79B9_7F4A_7C15 &+ b)
        _ = g.next()
        return g.next()
    }
}
