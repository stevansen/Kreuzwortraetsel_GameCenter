/// `classic`: kuratierte, 180°-symmetrische, voll verzahnte Schwarzfeldmuster.
///
/// Warum Templates und nicht prozedural: die Symmetrieauflage ist genau der
/// Grund, aus dem sich Handarbeit hier auszahlt — das Muster ist sichtbar und
/// wird beurteilt. Die Templates werden einmal per `puzzlegen templates`
/// gesucht, validiert und eingecheckt.
public struct ClassicLayout: LayoutProvider {
    public let variant: PuzzleVariant = .classic
    public let templates: [GridTemplate]

    public init(templates: [GridTemplate]) { self.templates = templates }

    public func makeTopology(size: GridSize, profile: DifficultyProfile,
                             rng: inout SplitMix64) throws -> Topology {
        let usable = templates
            .filter { $0.size == size && profile.deadCellRatio.contains($0.blockRatio) }
            .sorted { $0.rows.joined() < $1.rows.joined() }   // stabile Reihenfolge
        guard !usable.isEmpty else { throw LayoutError.noTemplate(size) }
        let pick = usable[rng.int(below: usable.count)]
        return Self.topology(size: size, kinds: pick.kinds, profile: profile)
    }

    static func topology(size: GridSize, kinds: [CellKind], profile: DifficultyProfile) -> Topology {
        // Slots sind die Läufe ab Mindestlänge. Läufe der Länge 1 sind
        // ungekreuzte Einzelbuchstaben und damit kein eigenes Wort; Läufe der
        // Länge 2 sind Templatefehler und werden vom Validator gemeldet, nicht
        // hier stillschweigend verschluckt.
        let runs = GridRuns.runs(size: size, kinds: kinds)
            .filter { $0.length >= profile.wordLength.lowerBound }
        let slots = runs.enumerated().map { i, r in
            Slot(id: i, start: r.start, direction: r.direction, length: r.length)
        }
        return Topology(size: size, kinds: kinds, slots: slots, cluePlans: [])
    }

    public func validate(topology: Topology, profile: DifficultyProfile) -> [ValidationIssue] {
        var issues = validateShared(topology: topology, profile: profile)
        let template = GridTemplate(size: topology.size, kinds: topology.kinds)
        if !template.isRotationallySymmetric {
            issues.append(.init(.error, "not-symmetric", "Muster ist nicht 180°-rotationssymmetrisch"))
        }
        if !GridRuns.lettersAreConnected(size: topology.size, kinds: topology.kinds) {
            issues.append(.init(.error, "letters-disconnected", "Weiße Zellen sind nicht zusammenhängend"))
        }
        // Volle Verzahnung wird **nicht** verlangt (siehe DifficultyProfile):
        // der Kreuzungsanteil wird in validateShared gegen minCrossRatio geprüft.
        if !topology.cluePlans.isEmpty {
            issues.append(.init(.error, "unexpected-clue-cells", "classic darf keine Fragezellen haben"))
        }
        return issues
    }

    public func validate(puzzle: Puzzle, profile: DifficultyProfile,
                         widths: GlyphWidthTable) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        for e in puzzle.entries {
            if e.number == nil {
                issues.append(.init(.error, "missing-number", "Slot \(e.slot.id) ohne Nummer"))
            }
            if e.clueText.isEmpty {
                issues.append(.init(.error, "empty-clue", "Slot \(e.slot.id) ohne Fragetext"))
            }
        }
        return issues
    }
}
