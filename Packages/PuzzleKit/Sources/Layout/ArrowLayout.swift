/// `arrow` — Schwedenrätsel: die Fragen stehen in Zellen **im** Gitter, Pfeile
/// zeigen, wo die Antwort beginnt und in welche Richtung sie läuft.
///
/// Anders als bei `classic` gibt es hier **keine kuratierten Templates**. Der
/// Grund ist die fehlende Symmetrieauflage: bei `classic` ist das Muster
/// sichtbar und wird beurteilt, deshalb zahlt sich Handarbeit aus. Bei `arrow`
/// fällt das Muster kaum auf — dafür gilt eine Belegungsauflage, und die ist ein
/// Zuordnungsproblem, das sich rechnen lässt.
///
/// Zwei Schritte:
///
/// 1. **Fragezellen platzieren** — dieselbe Bergsteigersuche auf einer
///    Verstoßsumme wie bei den `classic`-Templates. Auflagen: kein Lauf der
///    Länge 2, kein Lauf länger als `maxWord`, kein ungekreuzter Einzelbuchstabe
///    ohne Wort, Fragezellenanteil und Kreuzungsanteil im Zielband, und — neu —
///    jeder Lauf muss von mindestens einer Fragezelle aus **erreichbar** sein.
///
/// 2. **Slots zuweisen** — Backtracking mit MRV. Jeder Slot bekommt genau eine
///    besitzende Fragezelle, jede Fragezelle 1–2 Slots, Doppelpfeil- und
///    Knickpfeilquote unter der Stufenobergrenze.
///
/// Schritt 2 ist ein Exact-Cover-artiges Matching — und praktischerweise löst es
/// dieselbe Art Maschinerie, die auch die Wörter einsetzt. Zwei Probleme, ein
/// Verfahren.
public struct ArrowLayout: LayoutProvider {
    public let variant: PuzzleVariant = .arrow

    public init() {}

    /// Anteil Fragezellen, die leer bleiben dürfen. Kein hartes Verbot: eine
    /// einzelne leere Zelle ist im Druck üblich (dort steht oft ein Bild), viele
    /// sind ein Layoutfehler. Platzierung und Zuweisung müssen denselben Wert
    /// verwenden, sonst liefert die eine, was die andere ablehnt.
    static let emptyClueCellTolerance = 0.20

    /// Sicherheitsabstand zu den Bandgrenzen.
    ///
    /// Ohne ihn zielt die Bergsteigersuche genau auf die Grenze und landet durch
    /// Ganzzahl-Rundung knapp darüber: 29 von 99 Zellen sind 0,2929, aber 30 sind
    /// 0,303 gegen eine Obergrenze von 0,30. Die Restsumme wurde dann 0,2 und
    /// nie exakt 0 — die Platzierung galt als gescheitert, obwohl sie fertig war.
    /// Und der Validator hätte sie ohnehin abgelehnt.
    static let bandMargin = 0.008

    // MARK: - Erreichbarkeit

    /// Welche Fragezellen können diesen Lauf besitzen, und mit welchem Pfeil?
    ///
    /// Ein Lauf wird immer an seinem **Kopf** betreten. Für einen waagrechten
    /// Lauf mit Kopf `(r,c)` kommen in Frage:
    ///   `(r,c-1)` gerade nach rechts · `(r-1,c)` Knick abwärts-dann-rechts
    ///   `(r+1,c)` Knick aufwärts-dann-rechts
    /// Für einen senkrechten Lauf mit Kopf `(r,c)`:
    ///   `(r-1,c)` gerade abwärts · `(r,c-1)` Knick rechts-dann-abwärts
    ///   `(r,c+1)` Knick links-dann-abwärts
    static func possibleOwners(of slot: Slot, size: GridSize, kinds: [CellKind])
        -> [(cell: Cell, arrow: ArrowKind)]
    {
        let head = slot.start
        let candidates: [(Cell, ArrowKind)] = slot.direction == .across
            ? [(head.offset(0, -1), .right),
               (head.offset(-1, 0), .downThenRight),
               (head.offset(1, 0), .upThenRight)]
            : [(head.offset(-1, 0), .down),
               (head.offset(0, -1), .rightThenDown),
               (head.offset(0, 1), .leftThenDown)]
        return candidates
            .filter { size.contains($0.0) && kinds[size.index($0.0)] == .clue }
            .map { (cell: $0.0, arrow: $0.1) }
    }

    // MARK: - Topologie

    /// Zählt, welche Stufe wie oft scheitert — für die Diagnose.
    public struct StageCounts: Sendable {
        public var placementFailed = 0
        public var noSlots = 0
        public var assignmentFailed = 0
        public var success = 0
    }

    public func stageCounts(size: GridSize, profile: DifficultyProfile,
                            rng: inout SplitMix64, attempts: Int = 24) -> StageCounts {
        var c = StageCounts()
        for attempt in 0 ..< attempts {
            var local = SplitMix64(seed: SplitMix64.derive(rng.next(), UInt64(attempt)))
            let (kinds, _) = placeClueCellsBestEffort(size: size, profile: profile, rng: &local)
            let slots = makeSlots(size: size, kinds: kinds, profile: profile)
            if slots.isEmpty { c.noSlots += 1; continue }
            guard let plans = assignOwners(size: size, kinds: kinds, slots: slots,
                                           profile: profile, rng: &local) else {
                c.assignmentFailed += 1; continue
            }
            let topo = Topology(size: size, kinds: kinds, slots: slots, cluePlans: plans)
            if validate(topology: topo, profile: profile).contains(where: \.isError) {
                c.placementFailed += 1
            } else {
                c.success += 1
            }
        }
        return c
    }

    /// Die Verstoßsumme ist eine **Suchheuristik**, kein Abnahmekriterium.
    ///
    /// Vorher musste die Platzierung exakt 0 erreichen, sonst wurde sie
    /// verworfen — und weil die Summe Stilposten wie die Knickpfeilquote und
    /// Sicherheitsabstände zu den Bändern mitzählt, blieb sie oft bei 0,3 oder 5
    /// stehen, obwohl das Gitter vollkommen brauchbar war. Entscheiden darf der
    /// Validator: er kennt den Unterschied zwischen Fehler und Warnung.
    public func makeTopology(size: GridSize, profile: DifficultyProfile,
                             rng: inout SplitMix64) throws -> Topology {
        var best: (topology: Topology, issues: Int)?
        for attempt in 0 ..< 60 {
            var local = SplitMix64(seed: SplitMix64.derive(rng.next(), UInt64(attempt)))
            let (kinds, _) = placeClueCellsBestEffort(size: size, profile: profile, rng: &local)
            let slots = makeSlots(size: size, kinds: kinds, profile: profile)
            guard !slots.isEmpty else { continue }
            guard let plans = assignOwners(size: size, kinds: kinds, slots: slots,
                                           profile: profile, rng: &local)
            else { continue }
            let topology = Topology(size: size, kinds: kinds, slots: slots, cluePlans: plans)
            let errors = validate(topology: topology, profile: profile).count(where: \.isError)
            if errors == 0 { return topology }
            if best == nil || errors < best!.issues { best = (topology, errors) }
        }
        // Nichts Fehlerfreies gefunden: mit dem besten Versuch scheitern, damit
        // der Generator die Meldung sieht statt nur „Budget erschöpft".
        if let best {
            let issues = validate(topology: best.topology, profile: profile).filter(\.isError)
            throw LayoutError.exhausted("Arrow-Layout \(size.label): "
                + issues.prefix(3).map(\.code).joined(separator: ", "))
        }
        throw LayoutError.exhausted("Arrow-Zuweisung für \(size.label)")
    }

    static func makeSlots(size: GridSize, kinds: [CellKind], profile: DifficultyProfile) -> [Slot] {
        GridRuns.runs(size: size, kinds: kinds)
            .filter { $0.length >= profile.wordLength.lowerBound }
            .enumerated()
            .map { Slot(id: $0.offset, start: $0.element.start,
                        direction: $0.element.direction, length: $0.element.length) }
    }

    func makeSlots(size: GridSize, kinds: [CellKind], profile: DifficultyProfile) -> [Slot] {
        Self.makeSlots(size: size, kinds: kinds, profile: profile)
    }

    // MARK: - Schritt 1: Fragezellen

    /// Verstoßsumme wie bei der Templatesuche, plus zwei arrow-spezifische Posten:
    /// ein Lauf ohne möglichen Besitzer und eine Fragezelle, von der aus kein
    /// Lauf erreichbar ist.
    /// Aufschlüsselung derselben Summe — für die Diagnose, wenn eine Platzierung
    /// nicht auf 0 kommt.
    public static func violationBreakdown(size: GridSize, kinds: [CellKind],
                                         profile: DifficultyProfile) -> [(String, Double)] {
        var out: [(String, Double)] = []
        let minWord = profile.wordLength.lowerBound
        let maxWord = profile.wordLength.upperBound
        var runsTwo = 0.0, runsLong = 0.0
        for r in GridRuns.runs(size: size, kinds: kinds) {
            if r.length == 1 { continue }
            if r.length == 2 || r.length < minWord { runsTwo += 5 }
            else if r.length > maxWord { runsLong += 3 * Double(r.length - maxWord) }
        }
        out.append(("Läufe der Länge 2", runsTwo))
        out.append(("zu lange Läufe", runsLong))
        out.append(("isolierte Buchstaben",
                    TemplateSearch.hasIsolatedLetter(size: size, kinds: kinds,
                                                     minWord: minWord) ? 8 : 0))
        let slots = makeSlots(size: size, kinds: kinds, profile: profile)
        let bentBudget = Int(Double(max(slots.count, 1)) * profile.maxBentArrowRatio)
        var noOwner = 0.0
        var needBent = 0
        var soleOwnerLoad = [Int](repeating: 0, count: size.area)
        var ownable = [Bool](repeating: false, count: size.area)
        for s in slots {
            let owners = possibleOwners(of: s, size: size, kinds: kinds)
            if owners.isEmpty { noOwner += 6 }
            else if !owners.contains(where: { !$0.arrow.isBent }) { needBent += 1 }
            if owners.count == 1 { soleOwnerLoad[size.index(owners[0].cell)] += 1 }
            for o in owners { ownable[size.index(o.cell)] = true }
        }
        out.append(("Slots ohne Besitzer", noOwner))
        out.append(("nur per Knickpfeil erreichbar (\(needBent), Budget \(bentBudget))",
                    needBent > bentBudget ? Double(needBent - bentBudget) * 6 : 0))
        var overloaded = 0.0
        for load in soleOwnerLoad where load > 2 { overloaded += Double(load - 2) * 5 }
        out.append(("Zellen mit >2 Pflichtslots", overloaded))
        var clueCells = 0, unusable = 0
        for i in 0 ..< size.area where kinds[i] == .clue {
            clueCells += 1
            if !ownable[i] { unusable += 1 }
        }
        let tolerance = Int(Double(clueCells) * Self.emptyClueCellTolerance)
        out.append(("unbrauchbare Fragezellen (\(unusable), toleriert \(tolerance))",
                    unusable > tolerance ? Double(unusable - tolerance) * 4 : 0))
        out.append(("Kapazität < Slots",
                    slots.count > clueCells * 2 ? Double(slots.count - clueCells * 2) * 4 : 0))
        let dead = Double(clueCells) / Double(size.area)
        let deadLow = profile.deadCellRatio.lowerBound + bandMargin
        let deadHigh = profile.deadCellRatio.upperBound - bandMargin
        out.append(("Fragezellenanteil (\(fmt(dead, 3)))",
                    dead < deadLow ? (deadLow - dead) * 60
                        : (dead > deadHigh ? (dead - deadHigh) * 60 : 0)))
        let cr = TemplateSearch.currentCrossRatio(size: size, kinds: kinds, minWord: minWord)
        let crLow = profile.crossRatio.lowerBound + bandMargin
        let crHigh = profile.crossRatio.upperBound - bandMargin
        out.append(("Kreuzungsanteil (\(fmt(cr, 3)))",
                    cr > crHigh ? (cr - crHigh) * 30 : (cr < crLow ? (crLow - cr) * 60 : 0)))
        out.append(("unzusammenhängend",
                    GridRuns.lettersAreConnected(size: size, kinds: kinds) ? 0 : 25))
        out.append(("Slots", Double(slots.count)))
        return out
    }

    /// Beste Platzierung samt Restverstößen — auch wenn sie nicht 0 erreicht.
    public func bestEffortPlacement(size: GridSize, profile: DifficultyProfile,
                                    rng: inout SplitMix64) -> (kinds: [CellKind], score: Double) {
        var bestKinds = [CellKind](repeating: .letter, count: size.area)
        var bestScore = Double.infinity
        for attempt in 0 ..< 12 {
            var local = SplitMix64(seed: SplitMix64.derive(rng.next(), UInt64(attempt)))
            let (k, s) = placeClueCellsBestEffort(size: size, profile: profile, rng: &local)
            if s < bestScore { bestScore = s; bestKinds = k }
            if bestScore == 0 { break }
        }
        return (bestKinds, bestScore)
    }

    static func violationScore(size: GridSize, kinds: [CellKind],
                               profile: DifficultyProfile) -> Double {
        var score = 0.0
        let minWord = profile.wordLength.lowerBound
        let maxWord = profile.wordLength.upperBound

        for r in GridRuns.runs(size: size, kinds: kinds) {
            if r.length == 1 { continue }
            if r.length == 2 { score += 5 }
            else if r.length < minWord { score += 5 }
            else if r.length > maxWord { score += 3 * Double(r.length - maxWord) }
        }
        if TemplateSearch.hasIsolatedLetter(size: size, kinds: kinds, minWord: minWord) {
            score += 8
        }

        let slots = makeSlots(size: size, kinds: kinds, profile: profile)
        var ownable = [Bool](repeating: false, count: size.area)
        // Bei einer Knickpfeilquote von 0 darf **kein** waagrechter Lauf am
        // linken Rand beginnen und kein senkrechter oben — es gibt dort keine
        // Zelle, aus der ein gerader Pfeil zeigen könnte. Genau deshalb sind in
        // gedruckten Schwedenrätseln die obere Zeile und die linke Spalte
        // überwiegend Fragezellen. Die Platzierung muss das wissen, sonst
        // scheitert erst die Zuweisung daran.
        let bentBudget = Int(Double(max(slots.count, 1)) * profile.maxBentArrowRatio)
        var needBent = 0
        var soleOwnerLoad = [Int](repeating: 0, count: size.area)
        for s in slots {
            let owners = possibleOwners(of: s, size: size, kinds: kinds)
            if owners.isEmpty { score += 6 }
            else if !owners.contains(where: { !$0.arrow.isBent }) { needBent += 1 }
            // Ein Slot mit genau einem möglichen Besitzer belegt dessen Kapazität
            // zwingend. Drei solche Slots auf derselben Zelle sind unlösbar.
            if owners.count == 1 { soleOwnerLoad[size.index(owners[0].cell)] += 1 }
            for o in owners { ownable[size.index(o.cell)] = true }
        }
        // Die Knickpfeilquote ist eine **globale** Obergrenze. Wenn mehr Slots
        // ausschließlich per Knickpfeil erreichbar sind, als die Quote zulässt,
        // ist die Zuweisung unlösbar — vorher fiel das erst dort auf, und die
        // Platzierung lieferte fröhlich Verstoßsumme 0.
        if needBent > bentBudget { score += Double(needBent - bentBudget) * 6 }
        for load in soleOwnerLoad where load > 2 { score += Double(load - 2) * 5 }
        // Kapazität: jede Fragezelle trägt höchstens zwei Slots.
        //
        // Unbrauchbare Fragezellen werden erst oberhalb der Toleranz bestraft,
        // die auch die Zuweisung anlegt. Vorher war die Platzierung strenger als
        // ihr eigener Abnehmer und blieb an einer einzigen Zelle hängen.
        var clueCells = 0, unusable = 0
        for i in 0 ..< size.area where kinds[i] == .clue {
            clueCells += 1
            if !ownable[i] { unusable += 1 }
        }
        let emptyTolerance = Int(Double(clueCells) * Self.emptyClueCellTolerance)
        if unusable > emptyTolerance { score += Double(unusable - emptyTolerance) * 4 }
        if slots.count > clueCells * 2 { score += Double(slots.count - clueCells * 2) * 4 }

        let dead = Double(clueCells) / Double(size.area)
        let deadLow = profile.deadCellRatio.lowerBound + Self.bandMargin
        let deadHigh = profile.deadCellRatio.upperBound - Self.bandMargin
        if dead < deadLow { score += (deadLow - dead) * 60 }
        if dead > deadHigh { score += (dead - deadHigh) * 60 }

        let cr = TemplateSearch.currentCrossRatio(size: size, kinds: kinds, minWord: minWord)
        let crLow = profile.crossRatio.lowerBound + Self.bandMargin
        let crHigh = profile.crossRatio.upperBound - Self.bandMargin
        if cr > crHigh { score += (cr - crHigh) * 30 }
        if cr < crLow { score += (crLow - cr) * 60 }

        if !GridRuns.lettersAreConnected(size: size, kinds: kinds) { score += 25 }
        // OFFEN: Der Slot-Graph-Zusammenhang wird hier **nicht** bewertet, nur im
        // Validator. Ihn in die Summe zu nehmen kostet je Bewertung eine
        // Topology-Konstruktion und trieb die Platzierung von Sekunden auf
        // Minuten, ohne die Stufe „Leicht" zu lösen. Der richtige Weg ist eine
        // inkrementelle Zusammenhangsprüfung auf den Läufen — siehe README,
        // Abschnitt „Bekannte Lücken".
        return score
    }

    func placeClueCells(size: GridSize, profile: DifficultyProfile,
                        rng: inout SplitMix64) -> [CellKind]? {
        let (kinds, score) = placeClueCellsBestEffort(size: size, profile: profile, rng: &rng)
        return score < 1e-9 ? kinds : nil
    }

    func placeClueCellsBestEffort(size: GridSize, profile: DifficultyProfile,
                                  rng: inout SplitMix64) -> ([CellKind], Double) {
        // Startbelegung: ein Diagonalgitter wie bei `classic`, nur ohne
        // Symmetrieauflage — also freier in der Wahl von Periode und Steigung.
        let maxWord = profile.wordLength.upperBound
        let minWord = profile.wordLength.lowerBound
        var periods = Array(stride(from: minWord + 1, through: maxWord + 1, by: 1))
        rng.shuffle(&periods)
        var slopes = [1, 2, 3, size.cols - 1, size.cols - 2]
        rng.shuffle(&slopes)

        let p = periods.first ?? (maxWord + 1)
        let k = slopes.first ?? 1
        let o = rng.int(below: p)
        var kinds = [CellKind](repeating: .letter, count: size.area)
        for r in 0 ..< size.rows {
            for c in 0 ..< size.cols where ((c + k * r + o) % p + p * 4) % p == 0 {
                kinds[size.index(Cell(r, c))] = .clue
            }
        }

        var score = Self.violationScore(size: size, kinds: kinds, profile: profile)
        var stall = 0
        for _ in 0 ..< 4000 where score > 0 {
            let i = rng.int(below: size.area)
            var trial = kinds
            trial[i] = trial[i] == .clue ? .letter : .clue
            let newScore = Self.violationScore(size: size, kinds: trial, profile: profile)
            if newScore <= score {
                stall = newScore == score ? stall + 1 : 0
                kinds = trial
                score = newScore
            } else {
                stall += 1
            }
            if stall > 900 { break }
        }
        return (kinds, score)
    }

    // MARK: - Schritt 2: Zuweisung

    /// Backtracking mit MRV: der Slot mit den wenigsten möglichen Besitzern
    /// zuerst. Tiebreak über die Slot-ID, damit das Ergebnis deterministisch ist.
    func assignOwners(size: GridSize, kinds: [CellKind], slots: [Slot],
                      profile: DifficultyProfile, rng: inout SplitMix64) -> [ClueCellPlan]? {
        let owners: [[(cell: Cell, arrow: ArrowKind)]] = slots.map {
            Self.possibleOwners(of: $0, size: size, kinds: kinds)
        }
        if owners.contains(where: \.isEmpty) { return nil }

        let clueIndices = (0 ..< size.area).filter { kinds[$0] == .clue }
        var indexOfClue = [Int: Int](minimumCapacity: clueIndices.count)
        for (n, i) in clueIndices.enumerated() { indexOfClue[i] = n }

        var load = [Int](repeating: 0, count: clueIndices.count)
        var assignment = [Int?](repeating: nil, count: slots.count)   // Slot -> Fragezellen-Index
        var arrows = [ArrowKind?](repeating: nil, count: slots.count)
        var bentCount = 0
        var doubleCount = 0

        // Die Quoten sind ein **Stilziel**, keine Korrektheitsauflage.
        //
        // Korrekt ist ein Layout, wenn jeder Slot genau einen Besitzer hat, alle
        // Pfeile geometrisch stimmen und kein Lauf die Länge 2 hat. Ob 8 % oder
        // 14 % der Pfeile Knicke sind, ändert nichts an der Lösbarkeit — es
        // ändert, wie schwer sich das Rätsel anfühlt. Deshalb wird zuerst mit den
        // Zielquoten gerechnet und nur bei Fehlschlag gelockert; der Validator
        // meldet die Überschreitung dann als Warnung, nicht als Fehler.
        let strictBent = Int(Double(slots.count) * profile.maxBentArrowRatio)
        let strictDouble = max(1, Int(Double(clueIndices.count) * profile.maxDoubleArrowRatio))
        var maxBent = strictBent
        var maxDouble = strictDouble
        let salt = rng.next()

        func solve(_ placed: Int) -> Bool {
            if placed == slots.count { return true }
            // MRV: wenigste noch mögliche Besitzer.
            var best = -1
            var bestOptions: [(cell: Cell, arrow: ArrowKind)] = []
            var bestCount = Int.max
            for (i, o) in owners.enumerated() where assignment[i] == nil {
                let viable = o.filter { cand in
                    guard let n = indexOfClue[size.index(cand.cell)] else { return false }
                    if load[n] >= 2 { return false }
                    if load[n] == 1, doubleCount >= maxDouble { return false }
                    if cand.arrow.isBent, bentCount >= maxBent { return false }
                    return true
                }
                if viable.count < bestCount {
                    bestCount = viable.count; best = i; bestOptions = viable
                    if bestCount == 0 { break }
                }
            }
            guard best >= 0 else { return false }
            if bestOptions.isEmpty { return false }

            // Reihenfolge: noch unbenutzte Fragezellen zuerst (jede leere Zelle
            // ist im Druck ein Loch), dann gerade Pfeile (lesbarer), dann
            // deterministisch streuen.
            let ordered = bestOptions.sorted {
                let la = indexOfClue[size.index($0.cell)].map { load[$0] } ?? 0
                let lb = indexOfClue[size.index($1.cell)].map { load[$0] } ?? 0
                if la != lb { return la < lb }
                if $0.arrow.isBent != $1.arrow.isBent { return !$0.arrow.isBent }
                let a = SplitMix64.mix(salt, UInt64(size.index($0.cell)))
                let b = SplitMix64.mix(salt, UInt64(size.index($1.cell)))
                return a < b
            }
            for cand in ordered {
                guard let n = indexOfClue[size.index(cand.cell)] else { continue }
                let wasDouble = load[n] == 1
                assignment[best] = n
                arrows[best] = cand.arrow
                load[n] += 1
                if wasDouble { doubleCount += 1 }
                if cand.arrow.isBent { bentCount += 1 }

                if solve(placed + 1) { return true }

                if cand.arrow.isBent { bentCount -= 1 }
                if wasDouble { doubleCount -= 1 }
                load[n] -= 1
                arrows[best] = nil
                assignment[best] = nil
            }
            return false
        }

        var solved = solve(0)
        if !solved {
            // Erste Lockerung: Quoten verdoppeln.
            maxBent = max(strictBent * 2, 2)
            maxDouble = min(clueIndices.count, strictDouble * 2)
            load = [Int](repeating: 0, count: clueIndices.count)
            assignment = [Int?](repeating: nil, count: slots.count)
            arrows = [ArrowKind?](repeating: nil, count: slots.count)
            bentCount = 0; doubleCount = 0
            solved = solve(0)
        }
        if !solved {
            // Zweite Lockerung: Quoten ganz aufheben. Ein stilistisch weniger
            // schönes Rätsel ist besser als keins.
            maxBent = slots.count
            maxDouble = clueIndices.count
            load = [Int](repeating: 0, count: clueIndices.count)
            assignment = [Int?](repeating: nil, count: slots.count)
            arrows = [ArrowKind?](repeating: nil, count: slots.count)
            bentCount = 0; doubleCount = 0
            solved = solve(0)
        }
        guard solved else { return nil }

        // Leere Fragezellen umverteilen: eine Zelle ohne Frage ist im gedruckten
        // Rätsel ein Loch. Wo möglich, wird ein Slot von einer doppelt belegten
        // Zelle abgegeben.
        var hosted: [Int: [HostedSlot]] = [:]
        for (slotIndex, n) in assignment.enumerated() {
            guard let n, let arrow = arrows[slotIndex] else { return nil }
            hosted[clueIndices[n], default: []].append(
                HostedSlot(slotID: slots[slotIndex].id, arrow: arrow))
        }
        let plans = clueIndices.compactMap { i -> ClueCellPlan? in
            guard let h = hosted[i], !h.isEmpty else { return nil }
            return ClueCellPlan(cell: size.cell(i), hosted: h)
        }
        // Anteil leerer Fragezellen begrenzen — aber mit dem **strukturellen
        // Minimum** als Sockel: gibt es mehr Fragezellen als Slots, müssen
        // zwangsläufig Zellen leer bleiben. Ohne diesen Sockel war die Auflage
        // unerfüllbar (28 Zellen, 26 Slots, Toleranz 3 → immer abgelehnt), und
        // die Zuweisung schlug fehl, obwohl das Layout in Ordnung war.
        let empty = clueIndices.count - plans.count
        let forced = max(0, clueIndices.count - slots.count)
        let allowed = forced + Int((Double(clueIndices.count) * Self.emptyClueCellTolerance).rounded())
        if empty > allowed { return nil }
        return plans.sorted { $0.cell < $1.cell }
    }

    // MARK: - Validierung

    public func validate(topology: Topology, profile: DifficultyProfile) -> [ValidationIssue] {
        var issues = validateShared(topology: topology, profile: profile)
        let size = topology.size

        var hostedBySlot: [Int: (Cell, ArrowKind)] = [:]
        for plan in topology.cluePlans {
            if plan.hosted.isEmpty {
                // Kann nicht auftreten: leere Zellen werden gar nicht als Plan
                // geführt. Bleibt als Netz, falls jemand Pläne selbst baut.
                issues.append(.init(.error, "empty-clue-cell",
                    "Fragezelle \(plan.cell) trägt keine Frage"))
            }
            if plan.hosted.count > 2 {
                issues.append(.init(.error, "overloaded-clue-cell",
                    "Fragezelle \(plan.cell) trägt \(plan.hosted.count) Fragen (max. 2)"))
            }
            for h in plan.hosted {
                if hostedBySlot[h.slotID] != nil {
                    issues.append(.init(.error, "slot-owned-twice",
                        "Slot \(h.slotID) hat mehr als einen Besitzer"))
                }
                hostedBySlot[h.slotID] = (plan.cell, h.arrow)
            }
        }
        for s in topology.slots where hostedBySlot[s.id] == nil {
            issues.append(.init(.error, "slot-without-owner",
                "Slot \(s.id) bei \(s.start) hat keine Fragezelle"))
        }

        // Pfeilgeometrie: Ziel im Gitter, Ziel ist Buchstabenzelle, Slot beginnt dort.
        for s in topology.slots {
            guard let (owner, arrow) = hostedBySlot[s.id] else { continue }
            let off = arrow.startOffset
            let start = owner.offset(off.dr, off.dc)
            if !size.contains(start) {
                issues.append(.init(.error, "arrow-target-outside",
                    "Pfeil \(arrow.rawValue) aus \(owner) zeigt aus dem Gitter"))
                continue
            }
            if topology.kinds[size.index(start)] != .letter {
                issues.append(.init(.error, "arrow-target-not-letter",
                    "Pfeil \(arrow.rawValue) aus \(owner) zeigt auf keine Buchstabenzelle"))
            }
            if start != s.start {
                issues.append(.init(.error, "arrow-start-mismatch",
                    "Pfeil \(arrow.rawValue) aus \(owner) beginnt nicht am Slotkopf \(s.start)"))
            }
            if arrow.runDirection != s.direction {
                issues.append(.init(.error, "arrow-direction-mismatch",
                    "Pfeil \(arrow.rawValue) läuft nicht \(s.direction.debugLabel)"))
            }
        }

        let bent = topology.cluePlans.flatMap(\.hosted).count { $0.arrow.isBent }
        let doubles = topology.cluePlans.count { $0.hosted.count == 2 }
        if !topology.slots.isEmpty {
            let bentRatio = Double(bent) / Double(topology.slots.count)
            if bentRatio > profile.maxBentArrowRatio + 1e-9 {
                let severity: ValidationIssue.Severity =
                    bentRatio <= profile.maxBentArrowRatio * 2 + 0.05 ? .warning : .error
                issues.append(.init(severity, "bent-arrow-ratio",
                    "Knickpfeilanteil \(fmt(bentRatio)) über Zielquote "
                        + "\(fmt(profile.maxBentArrowRatio))"))
            }
        }
        if !topology.cluePlans.isEmpty {
            let doubleRatio = Double(doubles) / Double(topology.cluePlans.count)
            if doubleRatio > profile.maxDoubleArrowRatio + 1e-9 {
                let severity: ValidationIssue.Severity =
                    doubleRatio <= profile.maxDoubleArrowRatio * 2 + 0.05 ? .warning : .error
                issues.append(.init(severity, "double-arrow-ratio",
                    "Doppelpfeilanteil \(fmt(doubleRatio)) über Zielquote "
                        + "\(fmt(profile.maxDoubleArrowRatio))"))
            }
        }
        if topology.kinds.contains(.block) {
            issues.append(.init(.error, "unexpected-block", "arrow kennt keine Schwarzfelder"))
        }
        return issues
    }

    public func validate(puzzle: Puzzle, profile: DifficultyProfile,
                         widths: GlyphWidthTable) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        guard case .arrow(let clueCells) = puzzle.layout else {
            return [.init(.error, "wrong-layout", "arrow-Rätsel ohne arrow-Layout")]
        }
        var countByCell: [Cell: Int] = [:]
        for plan in clueCells { countByCell[plan.cell] = plan.hosted.count }

        var seenTexts = Set<String>()
        for e in puzzle.entries {
            guard let short = e.clueShortText else {
                issues.append(.init(.error, "missing-short-clue",
                    "\(e.answer) hat keine Kurzfrage — im Schwedenrätsel verpflichtend"))
                continue
            }
            // **Das Breitenbudget ist ein Füll-Constraint, hier nur die
            // Nachprüfung.** Eine Zelle mit zwei Fragen hat pro Frage die halbe
            // Breite; wer erst füllt und dann filtert, stellt am Ende fest, dass
            // es für ein Wort nur eine 60-Zeichen-Umschreibung gibt.
            let hosts = e.ownerCell.flatMap { countByCell[$0] } ?? 1
            let budget = hosts >= 2 ? profile.doubleClueBudget : profile.singleClueBudget
            let w = widths.width(of: short)
            if w > budget {
                issues.append(.init(.error, "short-clue-too-wide",
                    "\u{201E}\(short)\u{201C} braucht \(w), Budget \(budget) (\(hosts) Fragen in der Zelle)"))
            }
            if !seenTexts.insert(short).inserted {
                issues.append(.init(.error, "duplicate-short-clue",
                    "Kurzfrage \u{201E}\(short)\u{201C} kommt zweimal vor"))
            }
            if e.arrow == nil || e.ownerCell == nil {
                issues.append(.init(.error, "missing-arrow", "\(e.answer) ohne Pfeil"))
            }
            if e.number != nil {
                issues.append(.init(.error, "unexpected-number",
                    "arrow-Rätsel haben keine Nummerierung"))
            }
        }
        return issues
    }
}
