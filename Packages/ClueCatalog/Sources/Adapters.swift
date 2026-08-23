import Foundation
import PuzzleKit

/// Ein Rohdatensatz aus `scripts/harvest_wikipedia.py`.
public struct WikipediaRecord: Decodable, Sendable {
    public let title: String
    public let description: String?
    public let descriptionSource: String?
    public let pageviews60: Int
    public let topviewsMonthly: Int?
    public let categories: [String]
    public let pageid: Int?
    public let source: String

    public var rawEntry: RawEntry? {
        guard let d = description, !d.isEmpty else { return nil }
        let kind: SourceKind = descriptionSource == "extract" ? .wikipediaExtract : .wikidata
        return RawEntry(title: title,
                        descriptions: [RawDescription(text: d, source: kind)],
                        topics: categories,
                        pageviews60: pageviews60,
                        hasEverydayCategory: !categories.isEmpty,
                        sourceRef: "de.wikipedia:\(pageid.map(String.init) ?? title)")
    }
}

/// Ein Rohdatensatz aus `scripts/harvest_wiktionary.py`.
public struct WiktionaryRecord: Decodable, Sendable {
    public let lemma: String
    public let wordClasses: [String]
    public let senses: [String]
    public let topics: [String]
    public let source: String

    public var rawEntry: RawEntry? {
        guard !senses.isEmpty else { return nil }
        return RawEntry(title: lemma,
                        descriptions: senses.map { RawDescription(text: $0, source: .wiktionary) },
                        topics: topics,
                        wordClasses: wordClasses,
                        sourceRef: "de.wiktionary:\(lemma)")
    }
}

public enum RawSourceLoader {
    /// Liest JSON-Lines zeilenweise und überspringt kaputte Zeilen still —
    /// ein einzelner Parsefehler in 170.000 Zeilen darf keinen Lauf kosten.
    static func lines(at path: String) throws -> [Substring] {
        let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true)
    }

    public static func wikipedia(path: String) throws -> [RawEntry] {
        let dec = JSONDecoder()
        return try lines(at: path).compactMap {
            try? dec.decode(WikipediaRecord.self, from: Data($0.utf8))
        }.compactMap(\.rawEntry)
    }

    public static func wiktionary(path: String) throws -> [RawEntry] {
        let dec = JSONDecoder()
        return try lines(at: path).compactMap {
            try? dec.decode(WiktionaryRecord.self, from: Data($0.utf8))
        }.compactMap(\.rawEntry)
    }
}
