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
    public let index: PatternIndex
    public let topology: Topology
    public let profile: DifficultyProfile
    /// Filter je Slot. Bei `arrow` hängt das Breitenbudget von der besitzenden
    /// Fragezelle ab — deshalb pro Slot und nicht global.
    public let slotFilters: [PatternIndex.WordFilter]
    public let branchLimit: Int

    private let crossings: [[(other: Int, mine: Int, theirs: Int)]]

    public init(index: PatternIndex, topology: Topology, profile: DifficultyProfile,
                slotFilters: [PatternIndex.WordFilter], branchLimit: Int = 80) {
        self.index = index
        self.topology = topology
        self.profile = profile
        self.slotFilters = slotFilters
        self.branchLimit = branchLimit
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
    }

    public func fill(rng: inout SplitMix64) throws -> FillOutcome {
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
    private func order(_ cands: Bitset, length: Int, salt: UInt64) -> [Int] {
        guard let idx = index.lengths[length] else { return [] }
        var keyed: [(UInt64, Int)] = []
        keyed.reserveCapacity(min(cands.count, 4096))
        let target = profile.minZipf + 0.8
        cands.forEachSetBit { local in
            let d = abs(idx.zipf[local] - target)
            let bucket: UInt64 = d < 0.5 ? 0 : (d < 1.5 ? 1 : 2)
            let key = (bucket << 60) | (SplitMix64.mix(salt, UInt64(local)) >> 4)
            keyed.append((key, local))
        }
        keyed.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        return keyed.prefix(branchLimit).map(\.1)
    }

    private func solve(_ state: inout State, masks: [Bitset], maxProperNouns: Int,
                       rng: inout SplitMix64) -> Bool {
        if state.filled == topology.slots.count { return true }
        if state.nodes > profile.nodeBudget { return false }

        guard let pick = pickSlot(state, masks, maxProperNouns: maxProperNouns) else { return false }
        if pick.candidates.isEmpty { return false }

        let slot = topology.slots[pick.slot]
        let idx = index.lengths[slot.length]!
        let salt = rng.next()

        for local in order(pick.candidates, length: slot.length, salt: salt) {
            state.nodes += 1
            if state.nodes > profile.nodeBudget { return false }

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
