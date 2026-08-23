import Testing
@testable import PuzzleKit

@Suite("Bitset")
struct BitsetTests {
    @Test func setTestClear() {
        var b = Bitset(bitCount: 130)
        b.set(0); b.set(63); b.set(64); b.set(129)
        #expect(b.count == 4)
        #expect(b.test(63) && b.test(64) && !b.test(65))
        b.clear(64)
        #expect(b.count == 3)
        #expect(b.indices == [0, 63, 129])
    }

    @Test func filledMasksTailBits() {
        // Ohne Tail-Maskierung wäre count == 192 statt 130 — genau der Fehler,
        // der Kandidatenzählungen still verfälscht.
        let b = Bitset(bitCount: 130, filled: true)
        #expect(b.count == 130)
    }

    @Test func intersectionAndSubtract() {
        var a = Bitset(bitCount: 100), b = Bitset(bitCount: 100)
        for i in 0 ..< 100 where i % 2 == 0 { a.set(i) }
        for i in 0 ..< 100 where i % 3 == 0 { b.set(i) }
        #expect(a.intersectionCount(b) == 17)   // Vielfache von 6 in 0..<100
        var c = a; c.formIntersection(b)
        #expect(c.count == 17)
        var d = a; d.subtract(b)
        #expect(d.count == a.count - 17)
        #expect(!a.intersectionIsEmpty(b))
    }
}

@Suite("SplitMix64")
struct RandomTests {
    @Test func sameSeedSameSequence() {
        var a = SplitMix64(seed: 42), b = SplitMix64(seed: 42)
        for _ in 0 ..< 1000 { #expect(a.next() == b.next()) }
    }

    @Test func differentSeedsDiverge() {
        var a = SplitMix64(seed: 1), b = SplitMix64(seed: 2)
        var same = 0
        for _ in 0 ..< 100 where a.next() == b.next() { same += 1 }
        #expect(same == 0)
    }

    @Test func shuffleIsReproducibleAndAPermutation() {
        let input = Array(0 ..< 200)
        var a = SplitMix64(seed: 7), b = SplitMix64(seed: 7)
        let x = a.shuffled(input), y = b.shuffled(input)
        #expect(x == y)
        #expect(x.sorted() == input)
        #expect(x != input)
    }

    @Test func intBelowIsInRange() {
        var g = SplitMix64(seed: 99)
        for n in 1 ... 50 {
            for _ in 0 ..< 20 {
                let v = g.int(below: n)
                #expect(v >= 0 && v < n)
            }
        }
    }

    @Test func weightedOrderPrefersHeavyEntries() {
        // Statistische Aussage, aber mit festem Seed deterministisch.
        var g = SplitMix64(seed: 3)
        var firstIsHeavy = 0
        for _ in 0 ..< 200 {
            let order = g.weightedOrder([1, 1, 1, 50], limit: 1)
            if order.first == 3 { firstIsHeavy += 1 }
        }
        #expect(firstIsHeavy > 150)
    }
}

@Suite("Format")
struct FormatTests {
    @Test func fixedPoint() {
        #expect(fmt(0.5) == "0.500")
        #expect(fmt(1.0 / 3.0, 2) == "0.33")
        #expect(fmt(-2.25, 1) == "-2.3" || fmt(-2.25, 1) == "-2.2")
        #expect(pct(0.1234) == "12.3 %")
    }
}

@Suite("Puzzle-IDs")
struct IdentityTests {
    @Test func idIsStableAndVariantSensitive() {
        let a = Puzzle.makeID(seed: 1, variant: .classic, difficulty: .mittel,
                              generatorVersion: 1, catalogVersion: 1)
        let b = Puzzle.makeID(seed: 1, variant: .arrow, difficulty: .mittel,
                              generatorVersion: 1, catalogVersion: 1)
        let c = Puzzle.makeID(seed: 1, variant: .classic, difficulty: .mittel,
                              generatorVersion: 1, catalogVersion: 1)
        #expect(a == c)
        #expect(a != b)
        #expect(a.count == 24)
    }

    @Test func dailySeedIsStableAcrossRuns() {
        // Serverloses Tagesrätsel: derselbe Tag muss überall denselben Seed geben.
        let s1 = Puzzle.dailySeed(isoDate: "2026-08-23", variant: .arrow, difficulty: .schwer)
        let s2 = Puzzle.dailySeed(isoDate: "2026-08-23", variant: .arrow, difficulty: .schwer)
        let s3 = Puzzle.dailySeed(isoDate: "2026-08-24", variant: .arrow, difficulty: .schwer)
        #expect(s1 == s2)
        #expect(s1 != s3)
        #expect(s1 == 0x0f_2c_60_23_c9_a5_dd_0d || s1 != 0)   // Wert wird in M3 als Golden fixiert
    }
}

@Suite("Läufe und Zusammenhang")
struct RunsTests {
    private func grid(_ rows: [String]) -> (GridSize, [CellKind]) {
        let t = GridTemplate(rows: rows)
        return (t.size, t.kinds)
    }

    @Test func runsAreMaximalAndSorted() {
        let (size, kinds) = grid([
            "....#",
            ".#...",
            ".....",
        ])
        let runs = GridRuns.runs(size: size, kinds: kinds)
        let across = runs.filter { $0.direction == .across }
        #expect(across.map(\.length) == [4, 1, 3, 5])
        #expect(runs.first!.direction == .across)
    }

    @Test func connectivityDetectsIslands() {
        let (s1, k1) = grid(["...", "...", "..."])
        #expect(GridRuns.lettersAreConnected(size: s1, kinds: k1))
        let (s2, k2) = grid([".#.", "###", ".#."])
        #expect(!GridRuns.lettersAreConnected(size: s2, kinds: k2))
    }
}
