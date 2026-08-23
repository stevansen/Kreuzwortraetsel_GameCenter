public enum PuzzleLayout: Codable, Sendable, Hashable {
    /// `true` = Schwarzfeld, nach Zellindex.
    case classic(blocks: [Bool])
    case arrow(clueCells: [ClueCellPlan])
}

/// Ein gefülltes Wort samt gewählter Frage — self-contained, damit UI und
/// CLI-Vorschau ohne Katalogzugriff arbeiten können.
public struct Entry: Codable, Sendable, Hashable {
    public let slot: Slot
    public let answerID: Int32
    public let answer: String
    public let clueID: Int32
    public let clueText: String
    /// Nur bei `arrow` gesetzt (und dort verpflichtend).
    public let clueShortText: String?
    /// Nur bei `classic`: die Nummer im Gitter.
    public let number: Int?
    /// Nur bei `arrow`: Pfeilart und besitzende Fragezelle.
    public let arrow: ArrowKind?
    public let ownerCell: Cell?

    public init(slot: Slot, answerID: Int32, answer: String, clueID: Int32, clueText: String,
                clueShortText: String?, number: Int?, arrow: ArrowKind?, ownerCell: Cell?) {
        self.slot = slot
        self.answerID = answerID
        self.answer = answer
        self.clueID = clueID
        self.clueText = clueText
        self.clueShortText = clueShortText
        self.number = number
        self.arrow = arrow
        self.ownerCell = ownerCell
    }
}

public struct Puzzle: Codable, Sendable, Hashable {
    /// Stabile ID aus `(seed, variant, difficulty, generatorVersion, catalogVersion)`.
    /// Bewusst **nicht** aus dem Gitterinhalt — sie muss vor der Generierung berechenbar sein.
    public let id: String
    public let seed: UInt64
    public let variant: PuzzleVariant
    public let difficulty: Difficulty
    public let generatorVersion: Int
    public let catalogVersion: Int
    public let size: GridSize
    public let layout: PuzzleLayout
    public let entries: [Entry]
    public let solutionHash: String

    public init(seed: UInt64, variant: PuzzleVariant, difficulty: Difficulty,
                generatorVersion: Int, catalogVersion: Int,
                size: GridSize, layout: PuzzleLayout, entries: [Entry]) {
        self.seed = seed
        self.variant = variant
        self.difficulty = difficulty
        self.generatorVersion = generatorVersion
        self.catalogVersion = catalogVersion
        self.size = size
        self.layout = layout
        self.entries = entries.sorted { $0.slot.id < $1.slot.id }
        self.id = Puzzle.makeID(seed: seed, variant: variant, difficulty: difficulty,
                                generatorVersion: generatorVersion, catalogVersion: catalogVersion)
        self.solutionHash = Puzzle.makeSolutionHash(size: size, entries: self.entries)
    }

    public static func makeID(seed: UInt64, variant: PuzzleVariant, difficulty: Difficulty,
                              generatorVersion: Int, catalogVersion: Int) -> String {
        let s = "pz1|\(seed)|\(variant.rawValue)|\(difficulty.rawValue)|\(generatorVersion)|\(catalogVersion)"
        return String(SHA256.hex(s).prefix(24))
    }

    static func makeSolutionHash(size: GridSize, entries: [Entry]) -> String {
        var parts: [String] = ["sol1|\(size.rows)x\(size.cols)"]
        for e in entries {
            parts.append("\(e.slot.id):\(e.slot.start.row),\(e.slot.start.col),\(e.slot.direction.rawValue):\(e.answer)")
        }
        return String(SHA256.hex(parts.joined(separator: "|")).prefix(32))
    }

    /// Lösungsbuchstaben nach Zellindex; `nil` für Nicht-Buchstabenzellen.
    public func solutionLetters() -> [Letter?] {
        var out = [Letter?](repeating: nil, count: size.area)
        for e in entries {
            guard let letters = Alphabet.normalize(e.answer) else { continue }
            for (i, c) in e.slot.cells.enumerated() where i < letters.count {
                out[size.index(c)] = letters[i]
            }
        }
        return out
    }

    public var kinds: [CellKind] {
        var out = [CellKind](repeating: .letter, count: size.area)
        switch layout {
        case .classic(let blocks):
            for i in 0 ..< min(blocks.count, out.count) where blocks[i] { out[i] = .block }
        case .arrow(let clueCells):
            for p in clueCells { out[size.index(p.cell)] = .clue }
        }
        return out
    }

    public var letterCellCount: Int { kinds.count { $0 == .letter } }

    /// Tagesrätsel-Seed: serverlos, weltweit gleich.
    public static func dailySeed(isoDate: String, variant: PuzzleVariant, difficulty: Difficulty) -> UInt64 {
        SHA256.seed("daily|\(isoDate)|\(variant.rawValue)|\(difficulty.rawValue)")
    }
}
