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

    public init(reader: CatalogReader, maxKindShare: Double = 0.30) {
        self.reader = reader
        self.maxKindShare = maxKindShare
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

        let pick = eligible[rng.int(below: eligible.count)]
        return ClueChoice(id: pick.id, text: pick.text, shortText: pick.shortText,
                          shortWidth: pick.shortWidth, kind: pick.kind.rawValue,
                          tier: pick.tier)
    }
}
