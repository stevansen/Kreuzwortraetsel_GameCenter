import Foundation
import PuzzleKit

/// Woher eine Beschreibung stammt — bestimmt Lizenz, Fragetyp, Vorrang und ob
/// das Lemma am Satzanfang abgeschnitten werden muss.
public enum SourceKind: String, Sendable, CaseIterable {
    /// Wiktionary-Bedeutungen: die saubersten Definitionen, deshalb Vorrang.
    case wiktionary
    /// Wikidata-Kurzbeschreibungen: knapp, CC0, gute Zweitquelle.
    case wikidata
    /// Erster Satz eines Wikipedia-Artikels: nur als Lückenfüller.
    case wikipediaExtract

    public var license: String {
        switch self {
        case .wiktionary: "CC BY-SA 4.0 (Deutsches Wiktionary)"
        case .wikidata: "CC0 (Wikidata)"
        case .wikipediaExtract: "CC BY-SA 4.0 (Wikipedia Artikeltext)"
        }
    }

    public var clueKind: ClueKind {
        switch self {
        case .wiktionary, .wikidata: .definition
        case .wikipediaExtract: .trivia
        }
    }

    /// Deutsche Artikeltexte beginnen mit dem Stichwort — das muss weg, sonst
    /// scheitert jede Zeile am Leak-Gatter.
    public var stripsLemma: Bool { self == .wikipediaExtract }

    /// Kleiner ist besser. Entscheidet, welcher Clue im Rätsel bevorzugt wird.
    public var priority: Int {
        switch self {
        case .wiktionary: 0
        case .wikidata: 1
        case .wikipediaExtract: 2
        }
    }
}

public struct RawDescription: Sendable {
    public let text: String
    public let source: SourceKind
    public init(text: String, source: SourceKind) {
        self.text = text
        self.source = source
    }
}

/// Das gemeinsame Zwischenformat aller Quellen.
///
/// Wikipedia, Wiktionary und Leipzig liefern sehr verschiedene Daten; alles
/// danach — Normalisierung, QA, Ambiguitätsgatter, Scoring, Report — läuft
/// einmal und quellenagnostisch. Neue Quellen brauchen nur einen Adapter, der
/// `RawEntry` liefert.
public struct RawEntry: Sendable {
    public let title: String
    public let descriptions: [RawDescription]
    public let topics: [String]
    /// Wiktionary-Wortarten (`noun`, `propernoun`, `abbreviation`, …).
    public let wordClasses: [String]
    /// Nur Wikipedia — Fallback, wenn das Wort im Korpus nicht belegt ist.
    public let pageviews60: Int?
    public let hasEverydayCategory: Bool
    public let sourceRef: String

    public init(title: String, descriptions: [RawDescription], topics: [String],
                wordClasses: [String] = [], pageviews60: Int? = nil,
                hasEverydayCategory: Bool = false, sourceRef: String) {
        self.title = title
        self.descriptions = descriptions
        self.topics = topics
        self.wordClasses = wordClasses
        self.pageviews60 = pageviews60
        self.hasEverydayCategory = hasEverydayCategory
        self.sourceRef = sourceRef
    }
}
