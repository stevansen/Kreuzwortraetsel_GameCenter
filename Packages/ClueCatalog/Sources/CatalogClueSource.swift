import Foundation
import PuzzleKit

/// `ClueSource` über den SQLite-Katalog.
///
/// Lädt die Fragen einer Antwort einmal und hält sie im Cache: ein Rätsel fragt
/// pro Antwort genau einmal, aber ein Batch-Lauf über tausende Seeds fragt
/// dieselben Antworten sehr oft.
public final class CatalogClueSource: ClueSource, @unchecked Sendable {
    private let reader: CatalogReader
    private let lock = NSLock()
    private var cache: [Int32: [CatalogClue]] = [:]
    /// Anteil, den ein einzelner Fragetyp im Rätsel höchstens einnehmen darf.
    public let maxKindShare: Double
    private let widths: GlyphWidthTable?

    public init(reader: CatalogReader, maxKindShare: Double = 0.30,
                widths: GlyphWidthTable? = nil) {
        self.reader = reader
        self.maxKindShare = maxKindShare
        self.widths = widths
    }

    /// Breite des **längsten Einzelworts** einer Kurzfrage.
    ///
    /// Das gespeicherte `shortWidth` ist die Gesamtbreite. Die Fragezelle bricht
    /// den Text aber auf zwei bis drei kurze Zeilen, und ein einzelnes langes
    /// Wort passt in keine davon — im Rendering standen dann „Bevollmächtigt er"
    /// und „Kollektive Arbeitsniederl egung", mitten im Wort umbrochen. Deutsche
    /// Komposita machen das zur Regel, nicht zum Randfall.
    ///
    /// Bewusst als **Vorliebe** bei der Auswahl, nicht als Gatter im Katalog:
    /// ein Gatter würde den Kandidatenpool verkleinern, von dem das Füllen
    /// abhängt. Passt keine Frage, wird die beste verfügbare genommen — ein
    /// unschön umbrochener Text ist besser als kein Rätsel.
    private func longestWordWidth(_ text: String) -> Int {
        guard let widths else { return 0 }
        return text.split(separator: " ").map { widths.width(of: String($0)) }.max() ?? 0
    }

    private func clues(for answerID: Int32) -> [CatalogClue] {
        lock.lock(); defer { lock.unlock() }
        if let c = cache[answerID] { return c }
        let c = (try? reader.clues(answerID: answerID)) ?? []
        cache[answerID] = c
        return c
    }

    public func clue(answerID: Int32, tiers: ClosedRange<Int>, maxShortWidth: Int?,
                     usedTexts: Set<String>, usedKinds: [Int: Int], slotCount: Int,
                     rng: inout SplitMix64) -> ClueChoice? {
        // Deterministisch: `clues(answerID:)` liefert ORDER BY tier, id.
        var eligible = clues(for: answerID).filter { c in
            guard tiers.contains(c.tier) else { return false }
            guard !usedTexts.contains(c.text) else { return false }
            if let budget = maxShortWidth {
                guard let w = c.shortWidth, w <= budget, let s = c.shortText,
                      !usedTexts.contains(s) else { return false }
            }
            return true
        }
        guard !eligible.isEmpty else { return nil }

        // Typ-Mix: ein Fragetyp, der sein Kontingent ausgeschöpft hat, wird
        // zurückgestellt — aber nicht ausgeschlossen, sonst scheitern Rätsel an
        // einer Kosmetikregel.
        let cap = max(1, Int(Double(slotCount) * maxKindShare))
        let preferred = eligible.filter { (usedKinds[$0.kind.rawValue] ?? 0) < cap }
        if !preferred.isEmpty { eligible = preferred }

        // Fragen bevorzugen, deren längstes Wort in eine Zeile der Zelle passt.
        // Als Zeilenbreite wird ein Drittel des Zellbudgets angesetzt: die Zelle
        // trägt etwa drei Zeilen.
        if let budget = maxShortWidth, widths != nil {
            let lineWidth = budget / 3
            let fitting = eligible.filter {
                guard let short = $0.shortText else { return false }
                return longestWordWidth(short) <= lineWidth
            }
            if !fitting.isEmpty { eligible = fitting }
        }

        let pick = eligible[rng.int(below: eligible.count)]
        return ClueChoice(id: pick.id, text: pick.text, shortText: pick.shortText,
                          shortWidth: pick.shortWidth, kind: pick.kind.rawValue,
                          tier: pick.tier)
    }
}
