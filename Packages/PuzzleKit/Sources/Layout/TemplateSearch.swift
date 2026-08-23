/// Deterministische Suche nach gültigen `classic`-Templates.
///
/// Ich zeichne Gitter nicht von Hand — schlechter und langsamer als eine
/// gesteuerte Suche. Der Validator ist das Qualitätsmaß, das Ergebnis wird
/// eingecheckt und ab dann nur noch geladen.
///
/// Die Suche läuft in **zwei Phasen**, und das ist der Kern:
///
/// 1. **Skelett** — symmetrische Schwarzfeldpaare setzen, solange *alle* Läufe
///    mindestens `minWord` lang bleiben, bis kein Lauf mehr länger als `maxWord`
///    ist. Ergebnis: ein voll verzahntes Gitter, Kreuzungsanteil 1,0.
/// 2. **Auflockern** — weiter Paare setzen, jetzt mit erlaubten Läufen der Länge 1
///    (einzelne ungekreuzte Buchstaben), bis der Kreuzungsanteil **in** das
///    Zielband des Profils gefallen ist.
///
/// Phase 2 ist nicht Kosmetik. Ein voll verzahntes Gitter braucht Wortlisten in
/// der Größenordnung 50.000 pro Schwierigkeitsband; der Katalog hat bei
/// zipf >= 4,5 rund 1.250 Antworten. Ohne Phase 2 füllt der Generator nichts.
public enum TemplateSearch {
    public enum FailureReason: String, Sendable, CaseIterable, Error {
        case longRunsRemain, blockRatioLow, blockRatioHigh, crossRatioHigh, crossRatioLow
        case notSymmetric, disconnected, isolatedLetter, illegalRun
    }

    public struct SearchResult: Sendable {
        public let templates: [GridTemplate]
        public let attempts: Int
        public let failures: [FailureReason: Int]
    }

    public static func search(size: GridSize, ratio: ClosedRange<Double>,
                              minWord: Int, maxWord: Int,
                              crossRatio: ClosedRange<Double>,
                              count: Int, seed: UInt64,
                              attemptsPerTemplate: Int = 14) -> [GridTemplate] {
        detailedSearch(size: size, ratio: ratio, minWord: minWord, maxWord: maxWord,
                       crossRatio: crossRatio, count: count, seed: seed,
                       attemptsPerTemplate: attemptsPerTemplate).templates
    }

    public static func detailedSearch(size: GridSize, ratio: ClosedRange<Double>,
                                      minWord: Int, maxWord: Int,
                                      crossRatio: ClosedRange<Double>,
                                      count: Int, seed: UInt64,
                                      attemptsPerTemplate: Int = 14) -> SearchResult {
        var found: [GridTemplate] = []
        var seen = Set<String>()
        var failures: [FailureReason: Int] = [:]
        var attempt = 0
        while found.count < count, attempt < count * attemptsPerTemplate {
            var rng = SplitMix64(seed: SplitMix64.derive(seed, UInt64(attempt)))
            attempt += 1
            switch attemptOne(size: size, ratio: ratio, minWord: minWord, maxWord: maxWord,
                              crossRatio: crossRatio, rng: &rng) {
            case .success(let t):
                if seen.insert(t.rows.joined()).inserted { found.append(t) }
            case .failure(let r):
                failures[r, default: 0] += 1
            }
        }
        return SearchResult(templates: found.sorted { $0.rows.joined() < $1.rows.joined() },
                            attempts: attempt, failures: failures)
    }

    /// Symmetriepaare in seedbarer Reihenfolge. Selbstpartner in der Mitte.
    static func symmetryPairs(size: GridSize, rng: inout SplitMix64) -> [[Int]] {
        var pairs: [[Int]] = []
        var used = Set<Int>()
        for i in 0 ..< size.area where !used.contains(i) {
            let c = size.cell(i)
            let p = size.index(Cell(size.rows - 1 - c.row, size.cols - 1 - c.col))
            used.insert(i); used.insert(p)
            pairs.append(i == p ? [i] : [i, p])
        }
        pairs.sort { $0[0] < $1[0] }
        rng.shuffle(&pairs)
        return pairs
    }

    /// Konstruktiv statt blind: ein **Diagonalgitter** aus Schwarzfeldern.
    ///
    /// Die blinde Greedy-Suche scheiterte in 100 % der Versuche daran, alle zu
    /// langen Läufe im Schwarzfeldbudget aufzulösen — sie malte sich in eine
    /// Ecke und fand dann keinen Zug mehr, der nicht einen Lauf der Länge 2
    /// erzeugt hätte. Ein Gitter `c + k·r ≡ -o (mod p)` löst das strukturell:
    /// entlang jeder Zeile *und* jeder Spalte liegen die Schwarzfelder im Abstand
    /// `p`, alle inneren Läufe haben also Länge `p-1`.
    ///
    /// Der Versatz `o` wird nicht geraten. Unter 180°-Drehung geht die Bedingung
    /// in `c + k·r ≡ C-1 + k·(R-1) + o` über; das Muster ist genau dann
    /// selbstsymmetrisch, wenn `2o ≡ -(C-1 + k·(R-1)) (mod p)`. Für ungerades `p`
    /// ist 2 invertierbar, es gibt also **genau ein** passendes `o` — und damit
    /// ist die Symmetrieauflage erfüllt, ohne sie erzwingen zu müssen.
    private static func attemptOne(size: GridSize, ratio: ClosedRange<Double>,
                                   minWord: Int, maxWord: Int,
                                   crossRatio: ClosedRange<Double>,
                                   rng: inout SplitMix64) -> Result<GridTemplate, FailureReason> {
        // Innere Laufweite p-1 muss im erlaubten Wortlängenband liegen.
        var periods = stride(from: minWord + 1, through: maxWord + 1, by: 1)
            .filter { $0 % 2 == 1 }
        if periods.isEmpty { periods = [maxWord + 1] }
        rng.shuffle(&periods)
        var slopes = [1, 2, 3, size.cols - 1, size.cols - 2, size.cols - 3]
        rng.shuffle(&slopes)

        var lastFailure: FailureReason = .longRunsRemain
        for p in periods {
            for k in slopes {
                guard let inv2 = inverse(of: 2, mod: p) else { continue }
                let target = ((-(size.cols - 1 + k * (size.rows - 1))) % p + p * 4) % p
                let o = (target * inv2) % p

                var kinds = [CellKind](repeating: .letter, count: size.area)
                for r in 0 ..< size.rows {
                    for c in 0 ..< size.cols where ((c + k * r + o) % p + p * 4) % p == 0 {
                        kinds[size.index(Cell(r, c))] = .block
                    }
                }

                switch finish(size: size, kinds: kinds, ratio: ratio, minWord: minWord,
                              maxWord: maxWord, crossRatio: crossRatio, rng: &rng) {
                case .success(let t): return .success(t)
                case .failure(let f): lastFailure = f
                }
            }
        }
        return .failure(lastFailure)
    }

    /// Alle Kennzahlen eines Gitters in **einem** Durchgang.
    ///
    /// Vorher rief die Verstoßsumme vier Funktionen, die jede für sich alle Läufe
    /// neu aufzählten. Bei 1.200 Zügen je Versuch und 225 Zellen war das der
    /// Grund, dass für 15×15 nur zwei Templates in 100 Sekunden herauskamen.
    struct Metrics {
        var illegalRuns = 0
        var excessLength = 0
        var isolatedLetters = 0
        var blockRatio = 0.0
        var crossRatio = 0.0
        var connected = true
    }

    static func metrics(size: GridSize, kinds: [CellKind],
                        minWord: Int, maxWord: Int) -> Metrics {
        var m = Metrics()
        var coverCount = [Int](repeating: 0, count: size.area)
        for r in GridRuns.runs(size: size, kinds: kinds) {
            if r.length >= minWord {
                for c in r.cells { coverCount[size.index(c)] += 1 }
            }
            if r.length == 1 { continue }
            if r.length == 2 || r.length < minWord { m.illegalRuns += 1 }
            else if r.length > maxWord { m.excessLength += r.length - maxWord }
        }
        var letters = 0, crossed = 0, blocks = 0
        for i in 0 ..< size.area {
            switch kinds[i] {
            case .letter:
                letters += 1
                if coverCount[i] == 0 { m.isolatedLetters += 1 }
                if coverCount[i] >= 2 { crossed += 1 }
            default:
                blocks += 1
            }
        }
        m.blockRatio = Double(blocks) / Double(size.area)
        m.crossRatio = letters == 0 ? 0 : Double(crossed) / Double(letters)
        m.connected = GridRuns.lettersAreConnected(size: size, kinds: kinds)
        return m
    }

    /// Gewichtete Verstoßsumme. 0 heißt: alle Auflagen erfüllt.
    ///
    /// Alle Auflagen in **eine** Zahl zu gießen ist der Trick, der die Suche
    /// überhaupt zum Laufen bringt. Feste Reparaturregeln scheiterten daran,
    /// dass jeder Zug an einer Stelle woanders einen neuen Verstoß erzeugte;
    /// eine Bergsteigersuche auf dieser Summe darf solche Züge machen, solange
    /// die Summe nicht steigt.
    static func violationScore(size: GridSize, kinds: [CellKind], minWord: Int, maxWord: Int,
                               ratio: ClosedRange<Double>,
                               crossRatio: ClosedRange<Double>) -> Double {
        let m = metrics(size: size, kinds: kinds, minWord: minWord, maxWord: maxWord)
        var score = Double(m.illegalRuns) * 4 + Double(m.excessLength) * 3
            + Double(m.isolatedLetters) * 6
        if m.blockRatio < ratio.lowerBound { score += (ratio.lowerBound - m.blockRatio) * 60 }
        if m.blockRatio > ratio.upperBound { score += (m.blockRatio - ratio.upperBound) * 60 }
        if m.crossRatio > crossRatio.upperBound {
            score += (m.crossRatio - crossRatio.upperBound) * 30
        }
        if m.crossRatio < crossRatio.lowerBound {
            score += (crossRatio.lowerBound - m.crossRatio) * 60
        }
        if !m.connected { score += 25 }
        return score
    }

    /// Bergsteigersuche auf `violationScore`, Züge sind symmetrische Paare.
    ///
    /// Der Zug schaltet ein Paar um: sind beide Zellen weiß, werden sie schwarz,
    /// sonst weiß. Damit kann die Suche Schwarzfelder auch **zurücknehmen** — das
    /// war der fehlende Freiheitsgrad, an dem die festen Reparaturregeln hingen.
    private static func finish(size: GridSize, kinds initial: [CellKind],
                              ratio: ClosedRange<Double>, minWord: Int, maxWord: Int,
                              crossRatio: ClosedRange<Double>,
                              rng: inout SplitMix64) -> Result<GridTemplate, FailureReason> {
        var kinds = initial
        var score = violationScore(size: size, kinds: kinds, minWord: minWord, maxWord: maxWord,
                                   ratio: ratio, crossRatio: crossRatio)
        let pairs = symmetryPairs(size: size, rng: &rng)
        var stall = 0

        for _ in 0 ..< 1400 where score > 0 {
            let pair = pairs[rng.int(below: pairs.count)]
            var trial = kinds
            let makeBlack = pair.allSatisfy { trial[$0] == .letter }
            for i in pair { trial[i] = makeBlack ? .block : .letter }
            let newScore = violationScore(size: size, kinds: trial, minWord: minWord,
                                          maxWord: maxWord, ratio: ratio, crossRatio: crossRatio)
            if newScore <= score {
                if newScore == score { stall += 1 } else { stall = 0 }
                kinds = trial
                score = newScore
            } else {
                stall += 1
            }
            // Seitwärtszüge sind erlaubt, aber nicht endlos: bringt die Suche
            // 400 Züge nichts, ist dieses Startgitter eine Sackgasse.
            if stall > 350 { break }
        }

        let t = GridTemplate(size: size, kinds: kinds)
        let cr = currentCrossRatio(size: size, kinds: kinds, minWord: minWord)
        if !longRunCells(size: size, kinds: kinds, maxWord: maxWord).isEmpty {
            return .failure(.longRunsRemain)
        }
        if !runsAreLegal(size: size, kinds: kinds, minWord: minWord, maxWord: maxWord,
                         allowSingles: true) { return .failure(.illegalRun) }
        if hasIsolatedLetter(size: size, kinds: kinds, minWord: minWord) {
            return .failure(.isolatedLetter)
        }
        if t.blockRatio < ratio.lowerBound { return .failure(.blockRatioLow) }
        if t.blockRatio > ratio.upperBound { return .failure(.blockRatioHigh) }
        if cr > crossRatio.upperBound { return .failure(.crossRatioHigh) }
        if cr < crossRatio.lowerBound { return .failure(.crossRatioLow) }
        if !t.isRotationallySymmetric { return .failure(.notSymmetric) }
        if !GridRuns.lettersAreConnected(size: size, kinds: kinds) {
            return .failure(.disconnected)
        }
        return .success(t)
    }

    /// Multiplikatives Inverses modulo `m` per erweitertem euklidischem Algorithmus.
    static func inverse(of a: Int, mod m: Int) -> Int? {
        guard m > 1 else { return nil }
        var (t, newT) = (0, 1)
        var (r, newR) = (m, ((a % m) + m) % m)
        while newR != 0 {
            let q = r / newR
            (t, newT) = (newT, t - q * newT)
            (r, newR) = (newR, r - q * newR)
        }
        guard r == 1 else { return nil }
        return ((t % m) + m) % m
    }

    // MARK: - Prüfungen

    /// Jeder Lauf liegt in `[minWord, maxWord]` — oder hat Länge 1, wenn
    /// `allowSingles`. Länge 2 ist immer verboten: zwei nebeneinanderliegende
    /// Buchstaben müssen ein Wort bilden.
    static func runsAreLegal(size: GridSize, kinds: [CellKind], minWord: Int, maxWord: Int,
                             allowSingles: Bool) -> Bool {
        for r in GridRuns.runs(size: size, kinds: kinds) {
            if r.length == 1 { if allowSingles { continue } else { return false } }
            if r.length < minWord || r.length > maxWord { return false }
        }
        return true
    }

    /// Steht eine Buchstabenzelle in beiden Richtungen allein? Dann ist sie
    /// durch keine Frage bestimmt.
    static func hasIsolatedLetter(size: GridSize, kinds: [CellKind], minWord: Int) -> Bool {
        var covered = [Bool](repeating: false, count: size.area)
        for r in GridRuns.runs(size: size, kinds: kinds) where r.length >= minWord {
            for c in r.cells { covered[size.index(c)] = true }
        }
        for i in 0 ..< size.area where kinds[i] == .letter && !covered[i] { return true }
        return false
    }

    /// Anteil der Buchstabenzellen, die in **zwei** Wörtern liegen.
    static func currentCrossRatio(size: GridSize, kinds: [CellKind], minWord: Int) -> Double {
        var count = [Int](repeating: 0, count: size.area)
        for r in GridRuns.runs(size: size, kinds: kinds) where r.length >= minWord {
            for c in r.cells { count[size.index(c)] += 1 }
        }
        var letters = 0, crossed = 0
        for i in 0 ..< size.area where kinds[i] == .letter {
            letters += 1
            if count[i] >= 2 { crossed += 1 }
        }
        return letters == 0 ? 0 : Double(crossed) / Double(letters)
    }

    /// Zellindizes, die in einem zu langen Lauf liegen.
    static func longRunCells(size: GridSize, kinds: [CellKind], maxWord: Int) -> Set<Int> {
        var out = Set<Int>()
        for r in GridRuns.runs(size: size, kinds: kinds) where r.length > maxWord {
            for c in r.cells { out.insert(size.index(c)) }
        }
        return out
    }
}
