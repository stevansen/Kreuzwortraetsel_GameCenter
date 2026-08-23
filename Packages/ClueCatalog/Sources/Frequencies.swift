import Foundation
import PuzzleKit

/// Worthäufigkeiten aus der Leipzig Corpora Collection (CC BY 4.0).
///
/// Ersetzt den Aufrufzahlen-Proxy: Artikelaufrufe messen Popularität, nicht
/// Wortgebrauch. „Brot" wird seltener angeklickt als eine aktuelle Berühmtheit,
/// ist aber das viel häufigere Wort — und nur Häufigkeit gehört in die
/// Schwierigkeitsberechnung.
public struct LeipzigFrequencies: Sendable {
    public let totalTokens: Int
    public let corpus: String
    /// Normalisierte Oberfläche → Vorkommen im Korpus.
    private let counts: [String: Int]

    public init(counts: [String: Int], totalTokens: Int, corpus: String) {
        self.counts = counts
        self.totalTokens = totalTokens
        self.corpus = corpus
    }

    public static func load(tsv: String, meta: String) throws -> LeipzigFrequencies {
        struct Meta: Decodable { let corpus: String; let totalTokens: Int }
        let m = try JSONDecoder().decode(Meta.self, from: Data(contentsOf: URL(fileURLWithPath: meta)))
        let text = try String(contentsOf: URL(fileURLWithPath: tsv), encoding: .utf8)
        var counts: [String: Int] = [:]
        counts.reserveCapacity(400_000)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, let n = Int(parts[1]) else { continue }
            counts[String(parts[0])] = n
        }
        return LeipzigFrequencies(counts: counts, totalTokens: m.totalTokens, corpus: m.corpus)
    }

    public var formCount: Int { counts.count }

    /// Kanonische Zipf-Skala: `log10(Vorkommen pro Million) + 3`.
    /// Funktionswörter landen bei ~7, sehr seltene Wörter bei ~1.
    public func zipf(_ surface: String) -> Double? {
        guard let c = counts[surface], c > 0, totalTokens > 0 else { return nil }
        return log10(Double(c) / Double(totalTokens) * 1e6) + 3.0
    }
}

public enum Frequency {
    /// Fallback für Einträge ohne Korpusbeleg (nur Wikipedia-Herkunft).
    /// Bleibt bewusst konservativ unter dem Band der Stufe „Leicht".
    public static func zipfFromPageviews(_ pageviews60: Int, hasEverydayCategory: Bool) -> Double {
        let perDay = Double(max(pageviews60, 0)) / 60.0
        var z = log10(perDay + 1.0) + 2.4
        if hasEverydayCategory { z += 0.3 }
        return min(max(z, 1.0), 4.6)
    }

    /// Clue-Härte auf der **echten** Zipf-Skala.
    ///
    /// Die Schwellen sind an der Leipzig-Verteilung kalibriert: von 382.884
    /// gitterfähigen Formen haben nur ~700 zipf >= 5. Mit den ursprünglich
    /// geschätzten Schwellen (1 ab 5,5) wäre Tier 1 praktisch leer geblieben —
    /// im ersten Lauf lagen 96 % aller Clues in Tier 4 und 5.
    public static func tier(zipf: Double, flags: AnswerFlags,
                           aggressivelyShortened: Bool) -> Int {
        var t: Int
        switch zipf {
        case 4.6...: t = 1
        case 4.0 ..< 4.6: t = 2
        case 3.3 ..< 4.0: t = 3
        case 2.6 ..< 3.3: t = 4
        default: t = 5
        }
        if flags.contains(.properNoun) { t += 1 }
        if flags.contains(.abbreviation) { t += 1 }
        if aggressivelyShortened { t += 1 }
        return min(max(t, 1), 5)
    }
}
