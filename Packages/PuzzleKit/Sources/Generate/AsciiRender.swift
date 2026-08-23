/// ASCII-Darstellung eines Rätsels — für die CLI.
///
/// Bis die Arrow-Ansicht in der App steht (M6), ist das die einzige Möglichkeit,
/// ein Schwedenrätsel-Layout zu beurteilen. Deshalb gehört sie in den Kern und
/// nicht in ein Skript.
public enum AsciiRender {
    public static func grid(_ puzzle: Puzzle, showSolution: Bool = true) -> String {
        let kinds = puzzle.kinds
        let solution = puzzle.solutionLetters()
        var arrowAt: [Int: [ArrowKind]] = [:]
        for e in puzzle.entries {
            if let a = e.arrow, let owner = e.ownerCell {
                arrowAt[puzzle.size.index(owner), default: []].append(a)
            }
        }
        var numberAt: [Int: Int] = [:]
        for e in puzzle.entries where e.number != nil {
            let i = puzzle.size.index(e.slot.start)
            numberAt[i] = min(numberAt[i] ?? .max, e.number!)
        }

        var lines: [String] = []
        for r in 0 ..< puzzle.size.rows {
            var row = ""
            for c in 0 ..< puzzle.size.cols {
                let i = puzzle.size.index(Cell(r, c))
                switch kinds[i] {
                case .block:
                    row += "██"
                case .clue:
                    let glyphs = (arrowAt[i] ?? []).map(\.glyph).joined()
                    row += glyphs.isEmpty ? "??" : (glyphs.count == 1 ? "\(glyphs) " : glyphs)
                case .letter:
                    if showSolution, let l = solution[i] {
                        row += "\(Alphabet.character(l)) "
                    } else if let n = numberAt[i] {
                        row += n < 10 ? "\(n) " : "\(n)"
                    } else {
                        row += ". "
                    }
                }
            }
            lines.append(row)
        }
        return lines.joined(separator: "\n")
    }

    public static func clueList(_ puzzle: Puzzle, limit: Int = 200) -> String {
        var out: [String] = []
        for e in puzzle.entries.prefix(limit) {
            let head: String
            if let n = e.number {
                head = "\(n) \(e.slot.direction == .across ? "waagr." : "senkr.")"
            } else if let a = e.arrow, let owner = e.ownerCell {
                head = "(\(owner.row),\(owner.col)) \(a.glyph)"
            } else {
                head = "#\(e.slot.id)"
            }
            let short = e.clueShortText.map { " [kurz: \($0)]" } ?? ""
            out.append("  \(head)  \(e.answer) (\(e.slot.length)) — \(e.clueText)\(short)")
        }
        return out.joined(separator: "\n")
    }

    public static func summary(_ puzzle: Puzzle) -> String {
        let shortCount = puzzle.entries.count { $0.clueShortText != nil }
        return """
        \(puzzle.variant.label) · \(puzzle.difficulty.label) · \(puzzle.size.label)
        Seed \(puzzle.seed) · ID \(puzzle.id) · genVer \(puzzle.generatorVersion) \
        · katVer \(puzzle.catalogVersion)
        \(puzzle.entries.count) Wörter · \(puzzle.letterCellCount) Buchstabenzellen \
        · \(shortCount) mit Kurzfrage
        Lösungs-Hash \(puzzle.solutionHash)
        """
    }
}
