import Testing
@testable import PuzzleKit

/// Die Geometrie-Suite für das Schwedenrätsel. Bis die App-Ansicht steht (M6)
/// sind diese Tests plus die ASCII-Vorschau die einzige Möglichkeit, ein
/// Arrow-Layout zu beurteilen.
@Suite("ArrowLayout")
struct ArrowLayoutTests {
    /// Stufen, für die das Arrow-Layout heute verlässlich eine gültige Topologie
    /// liefert. „Leicht" fehlt: dort zerfällt der Slot-Graph regelmäßig, weil die
    /// Platzierung ihn nicht bewertet (siehe Kommentar in `violationScore`).
    /// Bewusst als Lücke geführt statt als grüner Test auf halber Strecke.
    static let workingDifficulties: [Difficulty] = [.mittel, .schwer, .experte]

    private func topology(_ difficulty: Difficulty, seed: UInt64)
        throws -> (Topology, DifficultyProfile) {
        let profile = DifficultyProfile.profile(.arrow, difficulty)
        let layout = ArrowLayout()
        var rng = SplitMix64(seed: seed)
        let size = profile.sizes[0]
        return (try layout.makeTopology(size: size, profile: profile, rng: &rng), profile)
    }

    @Test func arrowGeometryIsConsistent() throws {
        // Pfeilsemantik: Startversatz und Laufrichtung müssen zusammenpassen,
        // und Knickpfeile müssen sich von geraden unterscheiden.
        for kind in ArrowKind.allCases {
            let off = kind.startOffset
            #expect(abs(off.dr) + abs(off.dc) == 1, "Start liegt nicht benachbart")
            let straight = (off == (0, 1) && kind.runDirection == .across)
                || (off == (1, 0) && kind.runDirection == .down)
            #expect(kind.isBent != straight)
        }
        #expect(ArrowKind.kind(startOffset: (0, 1), run: .across) == .right)
        #expect(ArrowKind.kind(startOffset: (1, 0), run: .across) == .downThenRight)
    }

    @Test func possibleOwnersFollowTheHeadRule() {
        // Ein Lauf wird immer am Kopf betreten: für einen waagrechten Lauf
        // kommen links, oben und unten in Frage — nie rechts.
        let size = GridSize(rows: 5, cols: 5)
        var kinds = [CellKind](repeating: .letter, count: size.area)
        for c in [Cell(1, 0), Cell(0, 1), Cell(2, 1)] { kinds[size.index(c)] = .clue }
        let slot = Slot(id: 0, start: Cell(1, 1), direction: .across, length: 4)
        let owners = ArrowLayout.possibleOwners(of: slot, size: size, kinds: kinds)
        let pairs = Set(owners.map { "\($0.cell.row),\($0.cell.col):\($0.arrow.rawValue)" })
        #expect(pairs.contains("1,0:right"))
        #expect(pairs.contains("0,1:downThenRight"))
        #expect(pairs.contains("2,1:upThenRight"))
        #expect(owners.count == 3)
    }

    @Test func generatesValidTopologyForEveryDifficulty() throws {
        for difficulty in Self.workingDifficulties {
            let (topo, profile) = try topology(difficulty, seed: 20_260_823)
            let issues = ArrowLayout().validate(topology: topo, profile: profile)
                .filter(\.isError)
            #expect(issues.isEmpty, Comment(rawValue:
                "\(difficulty.rawValue):\n" + issues.map(\.description).joined(separator: "\n")))
            #expect(!topo.slots.isEmpty)
            #expect(!topo.cluePlans.isEmpty)
        }
    }

    @Test func everySlotHasExactlyOneOwnerAndEveryClueCellIsUsed() throws {
        let (topo, _) = try topology(.mittel, seed: 42)
        var ownerCount = [Int: Int]()
        for plan in topo.cluePlans {
            #expect((1 ... 2).contains(plan.hosted.count),
                    Comment(rawValue: "Fragezelle \(plan.cell) trägt \(plan.hosted.count)"))
            for h in plan.hosted { ownerCount[h.slotID, default: 0] += 1 }
        }
        for s in topo.slots {
            #expect(ownerCount[s.id] == 1,
                    Comment(rawValue: "Slot \(s.id) hat \(ownerCount[s.id] ?? 0) Besitzer"))
        }
    }

    @Test func noRunOfLengthTwoAndEveryLetterCovered() throws {
        for difficulty in Self.workingDifficulties {
            let (topo, profile) = try topology(difficulty, seed: 7)
            for r in GridRuns.runs(size: topo.size, kinds: topo.kinds) {
                #expect(r.length != 2, Comment(rawValue:
                    "\(difficulty.rawValue): Lauf der Länge 2 bei \(r.start) — zwei "
                        + "benachbarte Buchstaben müssen ein Wort bilden"))
                #expect(r.length <= profile.wordLength.upperBound || r.length == 1)
            }
            for i in 0 ..< topo.size.area where topo.kinds[i] == .letter {
                #expect(!topo.slotsByCell[i].isEmpty, Comment(rawValue:
                    "\(difficulty.rawValue): Zelle \(topo.size.cell(i)) in keinem Slot"))
            }
        }
    }

    @Test func slotGraphIsConnected() throws {
        // Zerfällt der Slot-Graph, zerfällt das Rätsel in unabhängige Inseln.
        for difficulty in Self.workingDifficulties {
            let (topo, _) = try topology(difficulty, seed: 99)
            #expect(GridRuns.slotGraphIsConnected(topology: topo),
                    Comment(rawValue: "\(difficulty.rawValue): Slot-Graph zerfällt"))
        }
    }

    @Test func quotasForBentAndDoubleArrowsHold() throws {
        for difficulty in Self.workingDifficulties {
            let (topo, profile) = try topology(difficulty, seed: 4711)
            let bent = topo.cluePlans.flatMap(\.hosted).count { $0.arrow.isBent }
            let doubles = topo.cluePlans.count { $0.hosted.count == 2 }
            let bentRatio = Double(bent) / Double(max(topo.slots.count, 1))
            let doubleRatio = Double(doubles) / Double(max(topo.cluePlans.count, 1))
            // Quoten sind Stilziele: die Zuweisung lockert sie, wenn sie streng
            // nicht lösbar sind. Zugesagt ist höchstens die doppelte Zielquote.
            #expect(bentRatio <= profile.maxBentArrowRatio * 2 + 0.05, Comment(rawValue:
                "\(difficulty.rawValue): Knickpfeilanteil \(fmt(bentRatio)) "
                    + "gegen Ziel \(fmt(profile.maxBentArrowRatio))"))
            #expect(doubleRatio <= profile.maxDoubleArrowRatio * 2 + 0.05, Comment(rawValue:
                "\(difficulty.rawValue): Doppelpfeilanteil \(fmt(doubleRatio))"))

        }
    }

    @Test func arrowLeichtIsAKnownGap() throws {
        // Dokumentiert die offene Stelle, statt sie zu verschweigen: schlägt der
        // Aufruf eines Tages nicht mehr fehl, meldet swift-testing das und die
        // Stufe kann in `workingDifficulties` wandern.
        withKnownIssue("Slot-Graph zerfällt bei arrow/leicht — siehe README") {
            let profile = DifficultyProfile.profile(.arrow, .leicht)
            var rng = SplitMix64(seed: 1)
            let topo = try ArrowLayout().makeTopology(size: profile.sizes[0],
                                                      profile: profile, rng: &rng)
            let issues = ArrowLayout().validate(topology: topo, profile: profile)
                .filter(\.isError)
            #expect(issues.isEmpty)
        }
    }

    @Test func sameSeedSameTopology() throws {
        let profile = DifficultyProfile.profile(.arrow, .mittel)
        let layout = ArrowLayout()
        var a = SplitMix64(seed: 555)
        var b = SplitMix64(seed: 555)
        let x = try layout.makeTopology(size: profile.sizes[0], profile: profile, rng: &a)
        let y = try layout.makeTopology(size: profile.sizes[0], profile: profile, rng: &b)
        #expect(x.kinds == y.kinds)
        #expect(x.slots == y.slots)
        #expect(x.cluePlans == y.cluePlans)
    }
}
