public struct ValidationIssue: Sendable, CustomStringConvertible, Hashable {
    public enum Severity: String, Sendable { case error, warning }
    public let severity: Severity
    public let code: String
    public let detail: String

    public init(_ severity: Severity = .error, _ code: String, _ detail: String) {
        self.severity = severity
        self.code = code
        self.detail = detail
    }

    public var description: String { "[\(severity.rawValue)] \(code): \(detail)" }
    public var isError: Bool { severity == .error }
}

public enum LayoutError: Error, CustomStringConvertible {
    case noTemplate(GridSize)
    case exhausted(String)

    public var description: String {
        switch self {
        case .noTemplate(let s): "kein gültiges Template für \(s.label)"
        case .exhausted(let why): "Layout-Budget erschöpft: \(why)"
        }
    }
}

/// **Der Varianten-Seam.**
///
/// Ein `LayoutProvider` beantwortet genau eine Frage: wie wird aus einer
/// Gittergröße eine Menge von Slots mit Kreuzungen? Alles danach — Füllen,
/// Clue-Auswahl, Scoring, Fortschritt, Sync, Leaderboards — ist geteilter Code
/// und kennt die Variante nicht.
///
/// Wenn außerhalb von `Layout/` ein `if variant == .arrow` auftaucht, sitzt der
/// Seam an der falschen Stelle. `SeamTests` prüft das per Quellcode-Scan.
public protocol LayoutProvider: Sendable {
    var variant: PuzzleVariant { get }

    func makeTopology(size: GridSize, profile: DifficultyProfile,
                      rng: inout SplitMix64) throws -> Topology

    /// Geometrieregeln der Variante.
    func validate(topology: Topology, profile: DifficultyProfile) -> [ValidationIssue]

    /// Regeln, die erst am gefüllten Rätsel prüfbar sind (z. B. Breitenbudget).
    func validate(puzzle: Puzzle, profile: DifficultyProfile,
                  widths: GlyphWidthTable) -> [ValidationIssue]
}

public extension LayoutProvider {
    /// Regeln, die für **beide** Varianten gelten.
    func validateShared(topology: Topology, profile: DifficultyProfile) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let runs = GridRuns.runs(size: topology.size, kinds: topology.kinds)

        for r in runs where r.length == 2 {
            issues.append(.init(.error, "run-length-2",
                "Lauf der Länge 2 bei \(r.start) \(r.direction.debugLabel) — zwei benachbarte Buchstaben müssen ein Wort bilden"))
        }
        for r in runs where r.length > profile.wordLength.upperBound {
            issues.append(.init(.error, "run-too-long",
                "Lauf der Länge \(r.length) bei \(r.start) \(r.direction.debugLabel) überschreitet \(profile.wordLength.upperBound)"))
        }
        for i in 0 ..< topology.size.area where topology.kinds[i] == .letter {
            if topology.slotsByCell[i].isEmpty {
                issues.append(.init(.error, "uncovered-letter-cell",
                    "Buchstabenzelle \(topology.size.cell(i)) liegt in keinem Slot"))
            }
        }
        for s in topology.slots where s.length < profile.wordLength.lowerBound {
            issues.append(.init(.error, "slot-too-short",
                "Slot \(s.id) hat Länge \(s.length) < \(profile.wordLength.lowerBound)"))
        }
        if topology.crossRatio < profile.crossRatio.lowerBound - 1e-9 {
            issues.append(.init(.error, "cross-ratio",
                "Kreuzungsanteil \(fmt(topology.crossRatio)) < "
                    + "\(fmt(profile.crossRatio.lowerBound))"))
        }
        if !GridRuns.slotGraphIsConnected(topology: topology) {
            issues.append(.init(.error, "slot-graph-disconnected",
                "Der Slot-Graph zerfällt in mehrere Inseln"))
        }
        let dead = Double(topology.size.area - topology.letterCellCount) / Double(topology.size.area)
        if !profile.deadCellRatio.contains(dead) {
            issues.append(.init(.error, "dead-cell-ratio",
                "Anteil belegter Zellen \(fmt(dead)) außerhalb "
                    + "\(fmt(profile.deadCellRatio.lowerBound, 2))…\(fmt(profile.deadCellRatio.upperBound, 2))"))
        }
        return issues
    }
}
