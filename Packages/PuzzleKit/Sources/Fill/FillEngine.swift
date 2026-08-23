public enum FillError: Error, CustomStringConvertible {
    case budgetExhausted(nodes: Int, filled: Int, total: Int)
    case deadSlot(slotID: Int)

    public var description: String {
        switch self {
        case .budgetExhausted(let n, let f, let t):
            "Füll-Budget erschöpft nach \(n) Knoten (\(f)/\(t) Slots belegt)"
        case .deadSlot(let id):
            "Slot \(id) hat keinen einzigen Kandidaten"
        }
    }
}

public struct FillOutcome: Sendable {
    /// Slot-ID → globaler Lexicon-Index.
    public let assignment: [Int]
    public let nodes: Int
}

/// Wie weit die Suche gekommen ist. Der Unterschied zwischen „harte Instanz"
/// (kommt bis 30 von 34 und scheitert am Rest) und „irgendwas ist kaputt"
/// (kommt nie über 3) ist an dieser Zahl ablesbar — und nur an ihr.
public struct FillTrace: Sendable {
    public var nodes = 0
    public var maxFilled = 0
    public var deadSlotHits = 0
    /// Wie oft ein Slot die Suche blockiert hat, nach Slot-ID.
    public var blockedBySlot: [Int: Int] = [:]
}

/// Die varianten-agnostische CSP-Engine.
///
/// Sie sieht ausschließlich Slots und deren Kreuzungen. Ob die Frage in einer
/// Liste steht oder in einer Nachbarzelle mit Pfeil, ist ihr unbekannt — genau
/// darin liegt der Varianten-Seam. Beide Varianten füllen mit demselben Code.
///
/// Heuristik: MRV (kleinste Kandidatenmenge zuerst), Forward-Checking über die
/// Kreuzungen, gewichtete Kandidatenreihenfolge nach Nähe zum Zipf-Zielband.
/// Alle Tiebreaks sind deterministisch.
public struct FillEngine {
    /// Untergrenze für das bevorzugte Häufigkeitsniveau der Kandidaten.
    /// Rund „noch gebräuchlich" auf der Zipf-Skala.
    public static let preferredZipfFloor = 3.6

    public let index: PatternIndex
    public let topology: Topology
    public let profile: DifficultyProfile
    /// Filter je Slot. Bei `arrow` hängt das Breitenbudget von der besitzenden
    /// Fragezelle ab — deshalb pro Slot und nicht global.
    public let slotFilters: [PatternIndex.WordFilter]
    public let branchLimit: Int
    /// Knotenbudget dieses Versuchs.
    public let nodeBudget: Int
    /// Nach so vielen Knoten wird der Fortschritt geprüft.
    public let progressProbeNodes: Int
    /// So viele Slots muss die Suche bis dahin mindestens einmal belegt haben.
    public let progressFloor: Int
    /// Wie viele Kandidaten je Knoten nach Least-Constraining-Value bewertet werden.
    ///
    /// Zusammen mit `branchLimit` entscheidet dieser Wert, **welchen Ausschnitt**
    /// eines Kandidatenpools die Suche überhaupt sieht. Bei classic/experte
    /// stehen Pools von 6.000 bis 11.500 Wörtern zur Verfügung — davon 80
    /// vorzusortieren und 18 zu bewerten ist ein sehr schmaler Blick.
    public let lcvWidth: Int

    private let crossings: [[(other: Int, mine: Int, theirs: Int)]]

    public init(index: PatternIndex, topology: Topology, profile: DifficultyProfile,
                slotFilters: [PatternIndex.WordFilter], branchLimit: Int = 80,
                lcvWidth: Int = 18, nodeBudget: Int? = nil,
                useProgressProbe: Bool = true) {
        self.index = index
        self.topology = topology
        self.profile = profile
        self.slotFilters = slotFilters
        self.branchLimit = branchLimit
        self.lcvWidth = lcvWidth
        self.nodeBudget = nodeBudget ?? profile.nodeBudget
        // **Wo die Zeit tatsächlich hingeht.** Gemessen an classic/schwer: acht
        // Versuche, der erfolgreiche brauchte 1.184 Knoten — und der Lauf dauerte
        // 26 Sekunden, weil die sieben gescheiterten jeder das volle Budget von
        // 600.000 Knoten verbrannten. Über 95 % der Zeit floss in Layouts, die
        // nie eine Chance hatten; kein Tuning der Innenschleife hätte das geändert.
        //
        // Die Abbruchbedingung ist bewusst **Fortschritt**, nicht Budget. Ein
        // gestaffeltes Budget je Versuch war der erste Anlauf und ein Rückschritt:
        // Versuch und Layout sind gekoppelt, ein kleines Budget bestraft also
        // nicht das hoffnungslose Layout, sondern das früh gezogene. Drei von acht
        // Kombinationen scheiterten damit ganz. Hier wird stattdessen gefragt: hat
        // die Suche nach einer Sondierungsphase überhaupt einen nennenswerten Teil
        // des Gitters belegt? Ein Layout, das nach 30.000 Knoten nie über 45 % kam,
        // kommt auch nach 600.000 nicht.
        // Der Boden lag zuerst bei 45 %. Nach der Fragen-Schärfung (26 % weniger
        // Kurzfragen) brauchte die Suche für denselben Anteil mehr Knoten, und die
        // Sonde tötete Versuche, die durchgekommen wären — arrow/mittel starb so
        // nach 900 Knoten je Versuch. 30 % ist gemessen, nicht geschätzt.
        self.progressProbeNodes = min(max(nodeBudget ?? profile.nodeBudget, 1) / 20, 30_000)
        self.progressFloor = useProgressProbe
            ? max(1, Int(Double(topology.slots.count) * 0.30))
            : 0
        //
        // **Der letzte Versuch läuft ohne Sonde.** Die Sonde ist eine Wette:
        // sie spart Zeit an hoffnungslosen Layouts und verliert gelegentlich ein
        // lösbares. Bei classic/experte, Seed 2, starben alle zehn Versuche an
        // der Sonde (30.328 Knoten von 2.500.000) — die Wette ging zehnmal
        // hintereinander verloren. Ein Versuch ohne Abbruch kostet im Regelfall
        // nichts, weil er nur erreicht wird, wenn alles andere gescheitert ist.
        //
        // Ein zusätzlicher Stillstandsdetektor („seit N Knoten kein neuer
        // Bestwert") war der zweite Anlauf und ein Rückschritt: beim Füllen der
        // letzten Slots gibt es lange Plateaus ohne neuen Bestwert, und genau die
        // wurden abgewürgt. classic/experte und arrow/leicht scheiterten damit
        // ganz, für 6 Sekunden Gewinn bei classic/schwer. Verworfen.
        self.crossings = topology.crossings()
    }

    // MARK: - Zustand

    private struct State {
        var cellLetters: [Letter?]
        /// Slot-ID → lokaler Index innerhalb seiner Länge, `-1` = frei.
        var assigned: [Int]
        /// Länge → Bitset der schon verbrauchten Antworten.
        var used: [Int: Bitset]
        var filled = 0
        var properNouns = 0
        var nodes = 0
        var maxFilled = 0
        var blocked: [Int: Int] = [:]
    }

    /// Letzter Suchverlauf — nur für Diagnose, nicht Teil des Ergebnisses.
    public final class TraceBox: @unchecked Sendable {
        public var trace = FillTrace()
        public init() {}
    }

    public func fill(rng: inout SplitMix64, trace: TraceBox? = nil) throws -> FillOutcome {
        let slots = topology.slots
        var masks: [Bitset] = []
        masks.reserveCapacity(slots.count)
        for (i, s) in slots.enumerated() {
            masks.append(index.mask(length: s.length, filter: slotFilters[i]))
        }

        var used: [Int: Bitset] = [:]
        for s in slots where used[s.length] == nil {
            used[s.length] = Bitset(bitCount: index.lengths[s.length]?.count ?? 0)
        }
        var state = State(cellLetters: [Letter?](repeating: nil, count: topology.size.area),
                          assigned: [Int](repeating: -1, count: slots.count),
                          used: used)

        // Ein Slot ohne jeden Kandidaten ist ein Katalogproblem, kein
        // Suchproblem — sofort und mit klarer Meldung abbrechen.
        for (i, m) in masks.enumerated() where m.isEmpty {
            throw FillError.deadSlot(slotID: slots[i].id)
        }

        let maxProperNouns = Int(Double(slots.count) * profile.maxProperNounRatio)
        var rngCopy = rng
        let ok = solve(&state, masks: masks, maxProperNouns: maxProperNouns, rng: &rngCopy)
        rng = rngCopy
        if let trace {
            trace.trace.nodes = state.nodes
            trace.trace.maxFilled = state.maxFilled
            trace.trace.blockedBySlot = state.blocked
        }
        guard ok else {
            throw FillError.budgetExhausted(nodes: state.nodes, filled: state.filled,
                                            total: slots.count)
        }
        return FillOutcome(assignment: state.assigned.enumerated().map { i, local in
            index.lengths[slots[i].length]!.gids[local]
        }, nodes: state.nodes)
    }

    /// Diagnose: initiale Kandidatenzahl je Slot, ohne Suche.
    ///
    /// Wenn eine Generierung scheitert, ist die erste Frage immer, ob es an der
    /// Suche oder am Vokabular liegt. Diese Zahlen beantworten sie.
    public func diagnose() -> [(slot: Slot, candidates: Int, crossings: Int)] {
        topology.slots.enumerated().map { i, s in
            (slot: s,
             candidates: index.mask(length: s.length, filter: slotFilters[i]).count,
             crossings: crossings[i].count)
        }
    }

    // MARK: - Suche

    private func candidates(_ slotIndex: Int, _ state: State, _ masks: [Bitset],
                            maxProperNouns: Int) -> Bitset {
        let slot = topology.slots[slotIndex]
        var b = masks[slotIndex]
        for i in 0 ..< slot.length {
            let cell = slot.cell(at: i)
            if let l = state.cellLetters[topology.size.index(cell)] {
                b.formIntersection(index.lengths[slot.length]!.bitset(pos: i, letter: l))
            }
        }
        if let u = state.used[slot.length] { b.subtract(u) }
        if state.properNouns >= maxProperNouns {
            b.subtract(index.properNounMask(length: slot.length))
        }
        return b
    }

    /// MRV mit deterministischen Tiebreaks: kleinste Kandidatenmenge, dann
    /// meiste Kreuzungen, dann kleinster Slot-Index. Der letzte Tiebreak ist
    /// nicht Kosmetik — ohne ihn hinge das Ergebnis von der Aufzählungsreihenfolge ab.
    private func pickSlot(_ state: State, _ masks: [Bitset], maxProperNouns: Int)
        -> (slot: Int, candidates: Bitset)?
    {
        var best: (slot: Int, count: Int, crossings: Int, cands: Bitset)?
        for i in topology.slots.indices where state.assigned[i] < 0 {
            let c = candidates(i, state, masks, maxProperNouns: maxProperNouns)
            let n = c.count
            if n == 0 { return (i, c) }   // sofort scheitern lassen
            let x = crossings[i].count
            if let b = best {
                if n < b.count || (n == b.count && x > b.crossings) {
                    best = (i, n, x, c)
                }
            } else {
                best = (i, n, x, c)
            }
        }
        guard let b = best else { return nil }
        return (b.slot, b.cands)
    }

    /// Kandidatenreihenfolge: erst Nähe zum Zipf-Zielband (drei Körbe), dann ein
    /// seedbarer Streuschlüssel. Bewusst ohne `pow`/`log` — `PuzzleKit` soll ohne
    /// Foundation bauen, und Ganzzahlarithmetik ist hier auch reproduzierbarer.
    ///
    /// Das Ziel liegt **nicht** direkt über `minZipf`, sondern hat einen Boden bei
    /// `preferredZipfFloor`. Sonst bevorzugt eine schwere Stufe ausgerechnet den
    /// seltensten Teil ihres Bandes — bei classic/experte (minZipf 2,0) waren das
    /// rund 30.000 Wörter aus dem langen Wiktionary-Schwanz. Die verzahnen
    /// schlecht: ungewöhnliche Buchstabenmuster, wenige passende Kreuzungen. Eine
    /// schwere Stufe soll seltene Wörter *zulassen*, nicht aus ihnen *bestehen*.
    private func order(_ cands: Bitset, length: Int, salt: UInt64) -> [Int] {
        guard let idx = index.lengths[length] else { return [] }
        var keyed: [(UInt64, Int)] = []
        keyed.reserveCapacity(min(cands.count, 4096))
        let target = max(profile.minZipf + 0.8, Self.preferredZipfFloor)
        cands.forEachSetBit { local in
            let d = abs(idx.zipf[local] - target)
            let bucket: UInt64 = d < 0.5 ? 0 : (d < 1.5 ? 1 : 2)
            let key = (bucket << 60) | (SplitMix64.mix(salt, UInt64(local)) >> 4)
            keyed.append((key, local))
        }
        keyed.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        return keyed.prefix(branchLimit).map(\.1)
    }

    /// Bewertet Kandidaten danach, wie viel Spielraum sie den Kreuzungen lassen.
    ///
    /// Maximiert das **Minimum** der verbleibenden Kandidatenzahlen — ein Zug,
    /// der irgendeinem Nachbarn nur noch zwei Wörter lässt, ist gefährlicher als
    /// einer, der allen dreißig lässt. Nur die vordersten `lcvWidth` Kandidaten
    /// werden bewertet; alles zu bewerten kostet mehr, als es einbringt.
    private func rankByLeastConstraining(_ pool: [Int], slot: Slot, slotIndex: Int,
                                        state: State, masks: [Bitset], maxProperNouns: Int,
                                        idx: PatternIndex.LengthIndex) -> [Int] {
        let crossingsHere = crossings[slotIndex].filter { state.assigned[$0.other] < 0 }
        guard !crossingsHere.isEmpty, pool.count > 1 else { return pool }
        let width = min(pool.count, lcvWidth)

        var scored: [(score: Int, total: Int, local: Int)] = []
        scored.reserveCapacity(width)
        var probe = state
        for local in pool.prefix(width) {
            let letters = idx.letters[local]
            var written: [Int] = []
            for i in 0 ..< slot.length {
                let ci = topology.size.index(slot.cell(at: i))
                if probe.cellLetters[ci] == nil {
                    probe.cellLetters[ci] = letters[i]
                    written.append(ci)
                }
            }
            var minRemaining = Int.max
            var total = 0
            for cross in crossingsHere {
                let n = candidates(cross.other, probe, masks, maxProperNouns: maxProperNouns).count
                minRemaining = min(minRemaining, n)
                total += n
                if minRemaining == 0 { break }
            }
            for ci in written { probe.cellLetters[ci] = nil }
            if minRemaining > 0 { scored.append((minRemaining, total, local)) }
        }
        guard !scored.isEmpty else { return Array(pool.dropFirst(width)) }
        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.total != $1.total { return $0.total > $1.total }
            return $0.local < $1.local
        }
        // Bewertete zuerst, danach der unbewertete Rest als Rückfallebene.
        return scored.map(\.local) + pool.dropFirst(width)
    }

    private func solve(_ state: inout State, masks: [Bitset], maxProperNouns: Int,
                       rng: inout SplitMix64) -> Bool {
        if state.filled == topology.slots.count { return true }
        if state.nodes > nodeBudget { return false }
        // Sondierung: kein nennenswerter Fortschritt -> Layout aufgeben.
        if progressFloor > 0, state.nodes >= progressProbeNodes,
           state.maxFilled < progressFloor { return false }

        guard let pick = pickSlot(state, masks, maxProperNouns: maxProperNouns) else { return false }
        if pick.candidates.isEmpty {
            state.blocked[topology.slots[pick.slot].id, default: 0] += 1
            return false
        }

        let slot = topology.slots[pick.slot]
        let idx = index.lengths[slot.length]!
        let salt = rng.next()

        // **Least-Constraining-Value.** Vorher wurden die Kandidaten praktisch
        // zufällig durchprobiert (Zipf-Korb plus Streuschlüssel) — die Suche kam
        // damit auf etwa 60 % der Slots und blieb stehen. Jetzt wird unter den
        // aussichtsreichsten Kandidaten der gewählt, der den kreuzenden Slots am
        // meisten Kandidaten übrig lässt. Das ist die Standardheuristik für
        // Kreuzwortfüller und der Unterschied zwischen „kommt weit" und „fertig".
        let raw = order(pick.candidates, length: slot.length, salt: salt)
        let ranked = rankByLeastConstraining(raw, slot: slot, slotIndex: pick.slot,
                                             state: state, masks: masks,
                                             maxProperNouns: maxProperNouns, idx: idx)
        for local in ranked {
            state.nodes += 1
            if state.nodes > nodeBudget { return false }

            // Setzen
            var written: [Int] = []
            let letters = idx.letters[local]
            for i in 0 ..< slot.length {
                let ci = topology.size.index(slot.cell(at: i))
                if state.cellLetters[ci] == nil {
                    state.cellLetters[ci] = letters[i]
                    written.append(ci)
                }
            }
            state.assigned[pick.slot] = local
            state.used[slot.length]!.set(local)
            state.filled += 1
            if state.filled > state.maxFilled { state.maxFilled = state.filled }
            let isProper = idx.flags[local].contains(.properNoun)
            if isProper { state.properNouns += 1 }

            // Forward-Check: jedes gekreuzte, noch freie Slot muss einen
            // Kandidaten behalten. Billig, und spart ganze Teilbäume.
            var viable = true
            for cross in crossings[pick.slot] where state.assigned[cross.other] < 0 {
                if candidates(cross.other, state, masks, maxProperNouns: maxProperNouns).isEmpty {
                    viable = false; break
                }
            }
            if viable, solve(&state, masks: masks, maxProperNouns: maxProperNouns, rng: &rng) {
                return true
            }

            // Zurücknehmen
            if isProper { state.properNouns -= 1 }
            state.filled -= 1
            state.used[slot.length]!.clear(local)
            state.assigned[pick.slot] = -1
            for ci in written { state.cellLetters[ci] = nil }
        }
        return false
    }
}
