import SwiftUI
import PuzzleKit

/// Das Gitter. Beide Varianten, eine Ansicht.
///
/// Der Unterschied zwischen klassisch und Schwedenrätsel steckt nicht in
/// Verzweigungen, sondern im `Puzzle`: eine Zelle ist `.block`, `.letter` oder
/// `.clue`, und ein Eintrag hat entweder eine Nummer oder einen Pfeil. Ob
/// Kurzfragen **in** den Zellen erscheinen, entscheidet `SurfaceCapabilities` —
/// auf dem Fernseher nicht.
public struct GridView: View {
    let session: PuzzleSession
    let capabilities: SurfaceCapabilities
    /// Welche Zelle den Fokus hat. Nur auf Flächen mit Fokus-Engine belegt: dort
    /// bewegt die Fernbedienung den Fokus, und der Cursor folgt ihm. Auf allen
    /// anderen Flächen setzt ein Tippen oder die Tastatur den Cursor, und dieser
    /// Zustand bleibt leer.
    @FocusState private var focusedCell: Cell?
    let onTap: (Cell) -> Void

    public init(session: PuzzleSession, capabilities: SurfaceCapabilities,
                onTap: @escaping (Cell) -> Void) {
        self.session = session
        self.capabilities = capabilities
        self.onTap = onTap
    }

    private var size: GridSize { session.puzzle.size }
    private var kinds: [CellKind] { session.puzzle.kinds }

    /// Fragezelle → die Kurzfragen, die dort stehen, samt Pfeil.
    private var cluesByCell: [Cell: [(arrow: ArrowKind, text: String)]] {
        var out: [Cell: [(ArrowKind, String)]] = [:]
        for e in session.puzzle.entries {
            guard let arrow = e.arrow, let owner = e.ownerCell else { continue }
            // Trennstellen hier, nicht im Zellen-View: `body` läuft bei jeder
            // Eingabe neu, die Trennung ist aber je Frage einmal nötig.
            let clue = Hyphenation.hyphenated(e.clueShortText ?? e.clueText)
            out[owner, default: []].append((arrow, clue))
        }
        return out.mapValues { $0.map { (arrow: $0.0, text: $0.1) } }
    }

    public var body: some View {
        let clues = cluesByCell
        let activeCells = Set(session.activeCells)
        GeometryReader { geo in
            let side = cellSide(in: geo.size)
            VStack(spacing: 1) {
                ForEach(0 ..< size.rows, id: \.self) { row in
                    HStack(spacing: 1) {
                        ForEach(0 ..< size.cols, id: \.self) { col in
                            cell(at: Cell(row, col), side: side,
                                 clues: clues, activeCells: activeCells)
                        }
                    }
                }
            }
            .frame(width: Double(size.cols) * (side + 1),
                   height: Double(size.rows) * (side + 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Fokus bewegt den Cursor. Auf dem Fernseher ist das der ganze
        // Navigationsweg: die Fernbedienung kennt nur Richtungen und
        // „Auswählen", und die Fokus-Engine des Systems findet die Nachbarzelle
        // besser als jede eigene Rechnung. Auf Flächen ohne Fokus-Engine bleibt
        // `focusedCell` leer und dieser Zweig läuft nie.
        .onChange(of: focusedCell) { _, new in
            if let new { onTap(new) }
        }
        // Umgekehrt: springt der Cursor anders (Wortwechsel, Hinweis), zieht
        // der Fokus nach. Sonst zeigt der Fernseher den Fokus an einer Stelle
        // und den Cursor an einer anderen.
        .onChange(of: session.caret.cell) { _, new in
            guard capabilities.hasFocusEngine, focusedCell != new else { return }
            focusedCell = new
        }
    }

    /// Kantenlänge einer Zelle.
    ///
    /// `minimumCellSide` ist ein **Wunsch**, keine harte Untergrenze. Als
    /// Untergrenze behandelt lief das Gitter über: 13 Zeilen × 48 pt Wunschmaß
    /// für die Fernsehfläche sind mehr als die verfügbare Höhe, und die
    /// Clue-Leiste lag anschließend über dem Gitter.
    ///
    /// Die Auflösung hängt davon ab, ob die Fläche schieben und zoomen kann: wo
    /// ja, wird das Wunschmaß gehalten und der Rest ist erreichbar; wo nein
    /// (Fernseher, Mac-Fenster), wird eingepasst — ein zu kleines Gitter ist
    /// besser als ein überlappendes.
    private func cellSide(in available: CGSize) -> Double {
        let fitted = min(available.width / Double(size.cols),
                         available.height / Double(size.rows))
        guard fitted < capabilities.minimumCellSide else { return fitted }
        return capabilities.supportsZoomPan ? capabilities.minimumCellSide : fitted
    }

    @ViewBuilder
    private func cell(at cell: Cell, side: Double,
                      clues: [Cell: [(arrow: ArrowKind, text: String)]],
                      activeCells: Set<Cell>) -> some View {
        let index = size.index(cell)
        switch kinds[index] {
        case .block:
            Rectangle().fill(.primary.opacity(0.85))
                .frame(width: side, height: side)
                .accessibilityHidden(true)

        case .clue:
            ClueCellView(entries: clues[cell] ?? [], side: side,
                         showsText: capabilities.rendersInCellClues)
                .frame(width: side, height: side)
                .contentShape(Rectangle())

        case .letter:
            LetterCellView(state: session.progress.cells[index],
                           number: number(at: cell),
                           isCaret: session.caret.cell == cell,
                           isActiveWord: activeCells.contains(cell),
                           isFlagged: session.flaggedCells.contains(index),
                           side: side)
                .frame(width: side, height: side)
                .contentShape(Rectangle())
                .onTapGesture { onTap(cell) }
                .focusable(capabilities.hasFocusEngine)
                .focused($focusedCell, equals: cell)
                .accessibilityLabel(accessibilityLabel(for: cell))
                .accessibilityAddTraits(session.caret.cell == cell ? [.isSelected] : [])
        }
    }

    /// Nummer, falls hier ein klassisches Wort beginnt.
    private func number(at cell: Cell) -> Int? {
        session.puzzle.entries
            .filter { $0.slot.start == cell }
            .compactMap(\.number)
            .min()
    }

    /// VoiceOver liest die **Langform** der Frage, nie die Kurzform: die ist
    /// fürs Auge in einer engen Zelle gedacht, nicht fürs Ohr.
    private func accessibilityLabel(for cell: Cell) -> String {
        let index = size.index(cell)
        let letter = session.progress.cells[index].letter
        var parts = [Loc.string("grid.cell.position", cell.row + 1, cell.col + 1)]
        parts.append(letter.map { String(Alphabet.character($0)) }
            ?? Loc.string("grid.cell.empty"))
        if let entry = session.navigation.slot(at: cell, direction: session.caret.direction)
            .flatMap(session.navigation.entry) {
            parts.append(Loc.string("grid.cell.partOf", entry.clueText,
                                    entry.slot.direction.displayName, entry.slot.length))
        }
        if session.flaggedCells.contains(index) {
            parts.append(Loc.string("grid.cell.flagged"))
        }
        return parts.joined(separator: ", ")
    }
}

struct LetterCellView: View {
    let state: CellState
    let number: Int?
    let isCaret: Bool
    let isActiveWord: Bool
    let isFlagged: Bool
    let side: Double

    var body: some View {
        ZStack {
            Rectangle().fill(background)
            if let number {
                Text("\(number)")
                    .font(.system(size: max(7, side * 0.24), weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .topLeading)
                    .padding(1)
            }
            if let letter = state.letter {
                Text(String(Alphabet.character(letter)))
                    .font(.system(size: side * 0.56,
                                  weight: state.pencil ? .light : .semibold,
                                  design: .rounded))
                    .foregroundStyle(state.pencil ? AnyShapeStyle(.secondary)
                                                  : AnyShapeStyle(.primary))
            }
            // **Nie nur Farbe.** Ein Fehler wird zusätzlich als Form markiert,
            // damit er auch bei Farbfehlsichtigkeit erkennbar bleibt.
            if isFlagged {
                Path { p in
                    p.move(to: CGPoint(x: side * 0.68, y: side * 0.06))
                    p.addLine(to: CGPoint(x: side * 0.94, y: side * 0.06))
                    p.addLine(to: CGPoint(x: side * 0.94, y: side * 0.32))
                    p.closeSubpath()
                }
                .fill(.red)
            }
            if isCaret {
                Rectangle().strokeBorder(.tint, lineWidth: max(2, side * 0.07))
            }
        }
    }

    private var background: some ShapeStyle {
        if isFlagged { return AnyShapeStyle(.red.opacity(0.18)) }
        if isCaret { return AnyShapeStyle(.tint.opacity(0.22)) }
        if isActiveWord { return AnyShapeStyle(.tint.opacity(0.10)) }
        return AnyShapeStyle(.background.secondary)
    }
}

/// Eine Fragezelle des Schwedenrätsels: ein oder zwei Kurzfragen mit Pfeil.
struct ClueCellView: View {
    let entries: [(arrow: ArrowKind, text: String)]
    let side: Double
    /// Auf dem Fernseher steht hier nur der Pfeil — der Text ist auf drei Metern
    /// unlesbar und wandert in Clue-Leiste und Clue-Liste.
    let showsText: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(.primary.opacity(0.10))
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 1) {
                        if showsText {
                            Text(entry.text)
                                .font(.system(size: fontSize))
                                // 0,5 machte den Breiten-Etat aus dem Katalog
                                // wirkungslos: SwiftUI zwang jede Frage in die
                                // Zelle, indem es sie auf die halbe Größe
                                // schrumpfte. Im gerenderten Schwedenrätsel
                                // standen dadurch Fragen wie „Abk. für
                                // Bundesautobahntankstelle" in einer Schrift, die
                                // niemand liest, und brachen mitten im Wort.
                                // 0,8 begrenzt das; was dann nicht passt, wird
                                // sichtbar gekürzt statt unlesbar verkleinert.
                                //
                                // Die Ursache liegt tiefer: der Etat im Katalog
                                // und die tatsächliche Zeilenbreite dieser Zelle
                                // sind nicht miteinander verbunden. Solange das
                                // so ist, ist dies eine Grenze, keine Lösung.
                                .minimumScaleFactor(0.8)
                                .lineLimit(entries.count > 1 ? 2 : 3)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Spacer(minLength: 0)
                        }
                        Text(entry.arrow.glyph)
                            .font(.system(size: max(8, side * 0.26)))
                            .foregroundStyle(.tint)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entries.isEmpty ? Loc.string("grid.clueCell.empty")
            : entries.map { Loc.string("grid.clueCell.clue", $0.text, $0.arrow.rawValue) }
                .joined(separator: "; "))
    }

    private var fontSize: Double {
        // Zwei Fragen teilen sich die Zelle, also kleinere Schrift.
        max(5, side * (entries.count > 1 ? 0.14 : 0.17))
    }
}
