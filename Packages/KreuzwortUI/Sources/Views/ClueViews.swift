import SwiftUI
import PuzzleKit

/// Die aktive Frage, groß am Rand.
///
/// **Verpflichtend, nicht optional.** Sie ist gleichzeitig die Lösung für drei
/// Probleme: kleine Displays, Dynamic Type (der Zellentext skaliert nicht mit,
/// sonst zerreißt das Gitter) und Flächen, die überhaupt keine Fragen in Zellen
/// darstellen. Sie zeigt immer die **Langform** — die Kurzform ist fürs Auge in
/// einer engen Zelle gedacht, nicht als eigentliche Frage.
public struct ClueBarView: View {
    let session: PuzzleSession
    let onPrevious: () -> Void
    let onNext: () -> Void

    public init(session: PuzzleSession, onPrevious: @escaping () -> Void,
                onNext: @escaping () -> Void) {
        self.session = session
        self.onPrevious = onPrevious
        self.onNext = onNext
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button(action: onPrevious) { Image(systemName: "chevron.left") }
                .accessibilityLabel(Loc.string("clue.previous"))
            VStack(alignment: .leading, spacing: 2) {
                if let entry = session.activeEntry {
                    Text(heading(for: entry))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.clueText)
                        .font(.headline)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    // Der Füllstand des aktiven Wortes. Beim Tippen ist das
                    // die Auskunft, die man tatsächlich braucht: wo stehe ich,
                    // wie viele Lücken bleiben.
                    Text(session.pattern(of: entry))
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(Loc.string(
                            "cluelist.progress", entry.slot.length,
                            session.filledCount(of: entry)))
                } else {
                    Text(loc: "clue.none").font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onNext) { Image(systemName: "chevron.right") }
                .accessibilityLabel(Loc.string("clue.next"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
    }

    private func heading(for entry: Entry) -> String {
        var parts: [String] = []
        if let n = entry.number {
            parts.append("\(n) \(entry.slot.direction.displayName)")
        } else if let a = entry.arrow {
            parts.append("\(a.glyph) \(a.runDirection.displayName)")
        }
        parts.append(Loc.string("clue.letters", entry.slot.length))
        return parts.joined(separator: " · ")
    }
}

/// Der Füllstand eines Wortes: gesetzte Buchstaben, Lücken als „_“.
///
/// **Warum das sichtbar sein muss.** Welche Frage man als nächste angeht,
/// entscheidet sich an den Kreuzern — ein Wort mit drei gesetzten Buchstaben
/// ist oft lösbar, ein leeres selten. Die Fragenliste zeigte bisher nur ein
/// Häkchen für fertige Wörter; der ganze Zwischenzustand, also gerade die
/// Auskunft, nach der man auswählt, fehlte. Die Länge stand nur an der
/// aktiven Frage, nicht an den anderen.
extension PuzzleSession {
    func letters(of entry: Entry) -> [Letter?] {
        entry.slot.cells.map { progress.letter(at: puzzle.size.index($0)) }
    }

    /// „K _ E _ _ _“ — fürs Auge, mit schmalen Leerzeichen getrennt, damit die
    /// Lücken zählbar bleiben.
    func pattern(of entry: Entry) -> String {
        letters(of: entry)
            .map { $0.map { String(Alphabet.character($0)) } ?? "_" }
            .joined(separator: "\u{2009}")
    }

    func filledCount(of entry: Entry) -> Int {
        letters(of: entry).count { $0 != nil }
    }
}

/// Alle Fragen als Liste — der Inhalt, ohne Scroll-Hülle.
///
/// **Warum getrennt.** Weder `List` noch `ScrollView` noch `LazyVStack` rendern
/// in `ImageRenderer`: die erste zeigt SwiftUIs Platzhalter, die anderen bleiben
/// leer, weil sie einen echten View-Host bzw. ein Sichtfenster brauchen. Damit
/// wäre die Fragenliste nicht snapshot-testbar — und sie ist bei Schwedenrätseln
/// der primäre VoiceOver-Pfad, also gerade die Ansicht, die man geprüft haben
/// will. Der Inhalt steht deshalb für sich und wird von `ClueListView` nur noch
/// scrollbar gemacht.
public struct ClueListContent: View {
    let session: PuzzleSession
    let onSelect: (Int) -> Void

    public init(session: PuzzleSession, onSelect: @escaping (Int) -> Void) {
        self.session = session
        self.onSelect = onSelect
    }

    private var grouped: [(title: String, entries: [Entry])] {
        let entries = session.navigation.orderedSlots.compactMap(session.navigation.entry)
        // Klassisch nach Richtung gruppieren, Schwedenrätsel als eine Liste:
        // dort gibt es keine Nummerierung, an der man sich orientieren könnte.
        guard entries.contains(where: { $0.number != nil }) else {
            return [(Loc.string("cluelist.all"), entries)]
        }
        return [(Loc.string("cluelist.across"), entries.filter { $0.slot.direction == .across }),
                (Loc.string("cluelist.down"), entries.filter { $0.slot.direction == .down })]
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(grouped, id: \.title) { group in
                Text(group.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                ForEach(group.entries, id: \.slot.id) { entry in
                    row(entry)
                    Divider().padding(.leading, 46)
                }
            }
        }
    }

    private func row(_ entry: Entry) -> some View {
        let isActive = session.activeEntry?.slot.id == entry.slot.id
        let fertig = isComplete(entry)
        let gesetzt = session.filledCount(of: entry)
        return Button { onSelect(entry.slot.id) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker(for: entry))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 26, alignment: .trailing)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.clueText)
                        .font(.callout)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    // Länge und Füllstand in einer Zeile. Monospaced, damit die
                    // Lücken untereinander stehen und zählbar bleiben.
                    Text("\(entry.slot.length)\u{2009}·\u{2009}"
                         + session.pattern(of: entry))
                        .font(.caption.monospaced())
                        .foregroundStyle(fertig ? AnyShapeStyle(.secondary)
                                                : AnyShapeStyle(.primary.opacity(0.75)))
                }
                Spacer(minLength: 4)
                if fertig {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isActive ? Color.accentColor.opacity(0.14) : .clear)
        }
        .buttonStyle(.plain)
        // **Das Muster ist fürs Auge, nicht fürs Ohr.** „K Leerzeichen
        // Unterstrich" vorgelesen hilft niemandem; die Zahl schon.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.clueText + ", "
            + (fertig ? Loc.string("cluelist.complete")
                      : Loc.string("cluelist.progress", entry.slot.length, gesetzt)))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private func marker(for entry: Entry) -> String {
        if let n = entry.number { return "\(n)" }
        if let a = entry.arrow { return a.glyph }
        return "—"
    }

    private func isComplete(_ entry: Entry) -> Bool {
        entry.slot.cells.allSatisfy {
            session.progress.letter(at: session.puzzle.size.index($0)) != nil
        }
    }
}

/// Die scrollbare Fragenliste für die App.
public struct ClueListView: View {
    let session: PuzzleSession
    let onSelect: (Int) -> Void

    public init(session: PuzzleSession, onSelect: @escaping (Int) -> Void) {
        self.session = session
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView { ClueListContent(session: session, onSelect: onSelect) }
    }
}

/// Der Abschlussbildschirm mit der Punkte-Herleitung Zeile für Zeile.
///
/// Die Aufschlüsselung ist kein Schmuck: eine Punktzahl ohne Begründung fühlt
/// sich willkürlich an, und die Formel hat sechs Faktoren.
public struct CompletionView: View {
    let session: PuzzleSession
    let onNext: () -> Void

    public init(session: PuzzleSession, onNext: @escaping () -> Void) {
        self.session = session
        self.onNext = onNext
    }

    public var body: some View {
        VStack(spacing: 18) {
            Text(loc: "completion.title").font(.largeTitle.bold())
            Text("\(session.puzzle.variant.displayName) · "
                + "\(session.puzzle.difficulty.displayName) · \(session.puzzle.size.label)")
                .font(.subheadline).foregroundStyle(.secondary)

            if let breakdown = session.breakdown {
                VStack(spacing: 6) {
                    ForEach(Array(breakdown.lines.enumerated()), id: \.offset) { _, line in
                        HStack {
                            Text(line.kind.displayName)
                            Spacer(minLength: 20)
                            Text(line.value).monospacedDigit()
                        }
                        .font(line.kind.isTotal ? .headline : .callout)
                        .foregroundStyle(line.kind.isTotal
                            ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    }
                }
                .padding(14)
                .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: 340)
            }

            Text(durationText).font(.callout).foregroundStyle(.secondary)
            Button(action: onNext) { Text(loc: "completion.next") }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    private var durationText: String {
        let total = Int(session.elapsedSeconds.rounded())
        return Loc.string("completion.duration", total / 60, total % 60)
    }
}
