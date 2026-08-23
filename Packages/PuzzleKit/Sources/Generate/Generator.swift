public enum GeneratorError: Error, CustomStringConvertible {
    case allAttemptsFailed(variant: PuzzleVariant, difficulty: Difficulty,
                           attempts: Int, lastReason: String)
    case noClue(answer: String, tiers: ClosedRange<Int>, budget: Int?)
    case invalid([ValidationIssue])

    public var description: String {
        switch self {
        case .allAttemptsFailed(let v, let d, let n, let why):
            "\(v.rawValue)/\(d.rawValue): \(n) Versuche gescheitert, letzter Grund: \(why)"
        case .noClue(let a, let t, let b):
            "keine Frage für \(a) in Tier \(t.lowerBound)–\(t.upperBound)"
                + (b.map { ", Breitenbudget \($0)" } ?? "")
        case .invalid(let issues):
            "Rätsel ungültig:\n" + issues.map(\.description).joined(separator: "\n")
        }
    }
}

/// Erzeugt aus `(seed, variant, difficulty)` ein vollständiges Rätsel.
///
/// Bit-identisch auf jeder Plattform und in der CLI — das ist die Eigenschaft,
/// auf der alles andere ruht: Tagesrätsel ohne Server, Spielstand-Sync über
/// 20 Bytes, Rätsel per Link teilen.
public struct Generator: Sendable {
    public let layout: any LayoutProvider
    public let index: PatternIndex
    public let clues: any ClueSource
    public let widths: GlyphWidthTable
    public let generatorVersion: Int
    /// Wie viele Kandidaten die Füll-Engine je Suchknoten probiert.
    ///
    /// Ein niedriger Wert macht die Suche **unvollständig**: hat ein Slot 900
    /// Kandidaten und werden nur 80 probiert, kann ein lösbarer Teilbaum
    /// übersehen werden — und über Dutzende Slots hinweg summiert sich das zu
    /// einem Fehlschlag auf einer erfüllbaren Instanz.
    public let branchLimit: Int

    public let lcvWidth: Int

    public init(layout: any LayoutProvider, index: PatternIndex, clues: any ClueSource,
                widths: GlyphWidthTable, generatorVersion: Int = 1,
                branchLimit: Int = 80, lcvWidth: Int = 18) {
        self.layout = layout
        self.index = index
        self.clues = clues
        self.widths = widths
        self.generatorVersion = generatorVersion
        self.branchLimit = branchLimit
        self.lcvWidth = lcvWidth
    }

    public struct Report: Sendable {
        public var attempts = 0
        public var nodes = 0
        public var failures: [String] = []
        /// Bester Suchfortschritt über alle Versuche: `maxFilled` von `slots`.
        public var bestProgress = 0
        public var slotCount = 0
        /// Slots, an denen die Suche am häufigsten hängen blieb.
        public var worstSlots: [(slotID: Int, length: Int, hits: Int)] = []
    }

    public func generate(seed: UInt64, difficulty: Difficulty)
        throws -> (puzzle: Puzzle, report: Report)
    {
        let profile = DifficultyProfile.profile(layout.variant, difficulty)
        var report = Report()
        var lastReason = "unbekannt"

        for attempt in 0 ..< profile.maxAttempts {
            report.attempts += 1
            // Abgeleiteter Seed pro Versuch: derselbe Ausgangs-Seed führt immer
            // zur selben Versuchsfolge.
            var rng = SplitMix64(seed: SplitMix64.derive(seed, UInt64(attempt)))
            let size = profile.sizes[rng.int(below: profile.sizes.count)]

            do {
                let topology = try layout.makeTopology(size: size, profile: profile, rng: &rng)
                let topoIssues = layout.validate(topology: topology, profile: profile)
                    .filter(\.isError)
                if !topoIssues.isEmpty {
                    lastReason = "Topologie: " + topoIssues[0].code
                    report.failures.append(lastReason)
                    continue
                }

                let filters = slotFilters(topology: topology, profile: profile)
                let engine = FillEngine(index: index, topology: topology, profile: profile,
                                        slotFilters: filters, branchLimit: branchLimit,
                                        lcvWidth: lcvWidth)
                let box = FillEngine.TraceBox()
                report.slotCount = topology.slots.count
                defer {
                    if box.trace.maxFilled > report.bestProgress {
                        report.bestProgress = box.trace.maxFilled
                        report.worstSlots = box.trace.blockedBySlot
                            .sorted { $0.value > $1.value }.prefix(4).map { pair in
                                let slot = topology.slots.first(where: { $0.id == pair.key })
                                return (slotID: pair.key, length: slot?.length ?? 0,
                                        hits: pair.value)
                            }
                    }
                }
                let outcome = try engine.fill(rng: &rng, trace: box)
                report.nodes += outcome.nodes

                let puzzle = try assemble(seed: seed, difficulty: difficulty, profile: profile,
                                          topology: topology, outcome: outcome, rng: &rng)
                let issues = layout.validate(puzzle: puzzle, profile: profile, widths: widths)
                    .filter(\.isError)
                guard issues.isEmpty else { throw GeneratorError.invalid(issues) }
                return (puzzle, report)
            } catch let e {
                lastReason = "\(e)"
                report.failures.append(lastReason)
                continue
            }
        }
        throw GeneratorError.allAttemptsFailed(variant: layout.variant, difficulty: difficulty,
                                               attempts: report.attempts, lastReason: lastReason)
    }

    /// Filter je Slot. Bei `arrow` bestimmt die besitzende Fragezelle das
    /// Breitenbudget: eine Zelle mit zwei Fragen hat pro Frage nur die halbe
    /// Breite. Das ist ein **Füll-Constraint**, kein Nachfilter — sonst füllt man
    /// erfolgreich und stellt am Ende fest, dass es für ein Wort nur eine
    /// 60-Zeichen-Umschreibung gibt.
    public func slotFilters(topology: Topology, profile: DifficultyProfile)
        -> [PatternIndex.WordFilter]
    {
        var budgetBySlot: [Int: Int] = [:]
        for plan in topology.cluePlans {
            let budget = plan.hosted.count >= 2 ? profile.doubleClueBudget : profile.singleClueBudget
            for h in plan.hosted { budgetBySlot[h.slotID] = budget }
        }
        return topology.slots.map { slot in
            PatternIndex.WordFilter(minZipf: profile.minZipf, tiers: profile.clueTiers,
                                    maxShortWidth: budgetBySlot[slot.id])
        }
    }

    private func assemble(seed: UInt64, difficulty: Difficulty, profile: DifficultyProfile,
                          topology: Topology, outcome: FillOutcome,
                          rng: inout SplitMix64) throws -> Puzzle {
        let numbers = topology.cluePlans.isEmpty ? Numbering.numbers(topology: topology) : [:]
        var arrowBySlot: [Int: (ArrowKind, Cell)] = [:]
        for plan in topology.cluePlans {
            for h in plan.hosted { arrowBySlot[h.slotID] = (h.arrow, plan.cell) }
        }
        var budgetBySlot: [Int: Int] = [:]
        for plan in topology.cluePlans {
            let budget = plan.hosted.count >= 2 ? profile.doubleClueBudget : profile.singleClueBudget
            for h in plan.hosted { budgetBySlot[h.slotID] = budget }
        }

        var usedTexts = Set<String>()
        var usedKinds: [Int: Int] = [:]
        var entries: [Entry] = []

        for (i, slot) in topology.slots.enumerated() {
            let gid = outcome.assignment[i]
            let entry = index.lexicon.entries[gid]
            let budget = budgetBySlot[slot.id]
            guard let choice = clues.clue(answerID: entry.answerID, tiers: profile.clueTiers,
                                          maxShortWidth: budget, usedTexts: usedTexts,
                                          usedKinds: usedKinds, slotCount: topology.slots.count,
                                          rng: &rng)
            else {
                throw GeneratorError.noClue(answer: entry.surface, tiers: profile.clueTiers,
                                            budget: budget)
            }
            usedTexts.insert(choice.text)
            if let s = choice.shortText { usedTexts.insert(s) }
            usedKinds[choice.kind, default: 0] += 1

            let arrow = arrowBySlot[slot.id]
            entries.append(Entry(slot: slot, answerID: entry.answerID, answer: entry.surface,
                                 clueID: choice.id, clueText: choice.text,
                                 clueShortText: choice.shortText, number: numbers[slot.id],
                                 arrow: arrow?.0, ownerCell: arrow?.1))
        }

        let layoutValue: PuzzleLayout = topology.cluePlans.isEmpty
            ? .classic(blocks: topology.kinds.map { $0 == .block })
            : .arrow(clueCells: topology.cluePlans.sorted { $0.cell < $1.cell })

        return Puzzle(seed: seed, variant: layout.variant, difficulty: difficulty,
                      generatorVersion: generatorVersion,
                      catalogVersion: index.lexicon.catalogVersion,
                      size: topology.size, layout: layoutValue, entries: entries)
    }
}
