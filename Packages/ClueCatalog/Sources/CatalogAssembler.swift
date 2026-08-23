import Foundation
import PuzzleKit

public struct ImportReport: Sendable {
    public var read = 0
    public var accepted = 0
    public var rejections: [Rejection: Int] = [:]
    public var mergedAcrossSources = 0
    public var ambiguousDropped = 0
    public var withShortText = 0
    public var byLength: [Int: Int] = [:]
    public var byTier: [Int: Int] = [:]
    public var byLicense: [String: Int] = [:]
    public var bySource: [String: Int] = [:]
    public var properNouns = 0
    public var zipfFromCorpus = 0
    public var zipfFromPageviews = 0
    public var shortInSingleBudget: [Int: Int] = [:]
    public var shortInDoubleBudget: [Int: Int] = [:]
    /// Kurzformen, die an einem der geschärften Gatter gescheitert sind.
    public var shortDroppedAmbiguous = 0
    public var shortDroppedGeneric = 0
    public var shortDroppedWordClass = 0

    mutating func reject(_ r: Rejection) { rejections[r, default: 0] += 1 }
}

/// Stufe 2–6 der Katalogpipeline, quellenagnostisch: normalisieren, Clues bauen,
/// QA, Häufigkeit, Tier, Ambiguitätsgatter, Report.
///
/// Deterministisch und ohne Netz — deshalb sitzt das Ernten in getrennten
/// Skripten. Diese Stufe ist reproduzierbar und getestet, jene nicht.
public struct CatalogAssembler: Sendable {
    public let normalizer: ClueNormalizer
    public let frequencies: LeipzigFrequencies?
    public let doubleBudget: Int

    public init(normalizer: ClueNormalizer, frequencies: LeipzigFrequencies?,
                doubleBudget: Int = 7_500) {
        self.normalizer = normalizer
        self.frequencies = frequencies
        self.doubleBudget = doubleBudget
    }

    public func assemble(_ entries: [RawEntry])
        -> (answers: [CatalogAnswer], clues: [String: [CatalogClue]], report: ImportReport)
    {
        var report = ImportReport()
        var answers: [String: CatalogAnswer] = [:]
        var clues: [String: [CatalogClue]] = [:]
        var seenTexts: [String: Set<String>] = [:]

        // Stabile Reihenfolge über alle Quellen: derselbe Eingabesatz muss
        // denselben Katalog ergeben, unabhängig von der Dateireihenfolge.
        for entry in entries.sorted(by: { $0.title == $1.title
            ? $0.sourceRef < $1.sourceRef : $0.title < $1.title })
        {
            report.read += 1
            guard !entry.descriptions.isEmpty else { report.reject(.noDescription); continue }

            let surface: String
            switch TitleNormalizer.normalize(title: entry.title) {
            case .success(let v): surface = v.surface
            case .failure(let r): report.reject(r); continue
            }
            let length = Alphabet.normalize(surface)?.count ?? surface.count

            // --- Flags ---
            var flags: AnswerFlags = []
            if TitleNormalizer.looksLikeAbbreviation(entry.title)
                || entry.wordClasses.contains("abbreviation") {
                flags.insert(.abbreviation)
            }
            let wiktionarySaysProper = entry.wordClasses.contains("propernoun")
                && !entry.wordClasses.contains("noun")
            // Wortart schlägt Heuristik: Wiktionary weiß es, Beschreibungsmarker raten.
            if wiktionarySaysProper { flags.insert(.properNoun) }

            // --- Häufigkeit ---
            let zipf: Double
            if let z = frequencies?.zipf(surface) {
                zipf = z
                report.zipfFromCorpus += 1
            } else {
                zipf = Frequency.zipfFromPageviews(entry.pageviews60 ?? 0,
                                                   hasEverydayCategory: entry.hasEverydayCategory)
                report.zipfFromPageviews += 1
            }

            if !wiktionarySaysProper, entry.wordClasses.isEmpty,
               TitleNormalizer.looksLikeProperNoun(description: entry.descriptions.first?.text,
                                                   zipf: zipf,
                                                   hasEverydayCategory: entry.hasEverydayCategory) {
                flags.insert(.properNoun)
            }

            // --- Clues ---
            var produced = 0
            for desc in entry.descriptions.sorted(by: { $0.source.priority < $1.source.priority }) {
                let base = desc.source.stripsLemma
                    ? ClueNormalizer.stripLeadingLemma(desc.text, title: entry.title)
                    : desc.text
                let long: String
                switch normalizer.longText(from: base) {
                case .success(let v): long = v
                case .failure(let r): report.reject(r); continue
                }
                if ClueNormalizer.clueLeaksAnswer(clue: long, answerSurface: surface) {
                    report.reject(.answerAppearsInClue); continue
                }
                // Dieselbe Frage nicht zweimal für dieselbe Antwort — verschiedene
                // Quellen formulieren oft identisch.
                if seenTexts[surface]?.contains(long.lowercased()) == true { continue }
                seenTexts[surface, default: []].insert(long.lowercased())

                let short = normalizer.shortText(from: long).flatMap {
                    ClueNormalizer.clueLeaksAnswer(clue: $0.text, answerSurface: surface)
                        ? nil : $0
                }
                let tier = Frequency.tier(zipf: zipf, flags: flags,
                                          aggressivelyShortened: short?.aggressive ?? false)
                clues[surface, default: []].append(CatalogClue(
                    text: long, shortText: short?.text, shortWidth: short?.width,
                    kind: desc.source.clueKind, tier: tier, locale: "de",
                    license: desc.source.license, sourceRef: entry.sourceRef))
                report.bySource[desc.source.rawValue, default: 0] += 1
                produced += 1
            }
            guard produced > 0 else { continue }

            // Wortart: Substantiv gewinnt, wenn mehrere angegeben sind — ein
            // Lemma mit Substantiv- *und* Nachnamen-Abschnitt ist als Gattungswort
            // brauchbarer.
            let wordClass = entry.wordClasses.contains("noun") ? "noun"
                : (entry.wordClasses.sorted().first ?? "")

            if let existing = answers[surface] {
                report.mergedAcrossSources += 1
                answers[surface] = CatalogAnswer(
                    surface: surface, zipf: max(existing.zipf, zipf),
                    flags: existing.flags.union(flags),
                    topics: Array(Set(existing.topics).union(entry.topics)).sorted(),
                    wordClass: existing.wordClass.isEmpty ? wordClass : existing.wordClass,
                    sourceRef: existing.sourceRef)
            } else {
                answers[surface] = CatalogAnswer(surface: surface, zipf: zipf, flags: flags,
                                                 topics: entry.topics.sorted(),
                                                 wordClass: wordClass,
                                                 sourceRef: entry.sourceRef)
            }
            _ = length
        }

        applyAmbiguityGate(&clues, answers: answers, report: &report)

        let finalAnswers = answers.values
            .filter { !(clues[$0.surface] ?? []).isEmpty }
            .sorted { $0.surface < $1.surface }
        let keep = Set(finalAnswers.map(\.surface))
        clues = clues.filter { keep.contains($0.key) }

        for a in finalAnswers {
            report.accepted += 1
            report.byLength[a.length, default: 0] += 1
            if a.flags.contains(.properNoun) { report.properNouns += 1 }
            for c in clues[a.surface] ?? [] {
                report.byTier[c.tier, default: 0] += 1
                report.byLicense[c.license, default: 0] += 1
                if let w = c.shortWidth {
                    report.withShortText += 1
                    if w <= normalizer.singleBudget { report.shortInSingleBudget[a.length, default: 0] += 1 }
                    if w <= doubleBudget { report.shortInDoubleBudget[a.length, default: 0] += 1 }
                }
            }
        }
        return (finalAnswers, clues, report)
    }

    /// Ein Clue, der auf drei oder mehr Antworten **gleicher Länge** passt, ist
    /// keine Frage, sondern ein Ratespiel. Läuft auf Lang- und Kurzform getrennt,
    /// weil Kürzen Mehrdeutigkeit erzeugt — genau der Fehler, der Schwedenrätsel
    /// unspielbar macht.
    /// Wie oft eine Kurzform katalogweit vorkommen darf, bevor sie als
    /// **generisch** gilt.
    ///
    /// „Wasser" als Frage zu EIS ist formal eindeutig — kein anderer
    /// Dreibuchstaber hat genau diese Kurzform — und als Frage trotzdem schwach.
    /// Das Merkmal ist nicht die Kollision bei gleicher Länge, sondern dass der
    /// Text überhaupt für viele Antworten passt. Deshalb wird über **alle**
    /// Längen gezählt.
    static let genericShortClueLimit = 4

    /// Wortarten, bei denen eine Substantiv-Kurzfrage grammatisch nicht passt.
    ///
    /// Im Deutschen ist ein einzelnes großgeschriebenes Wort ein Substantiv —
    /// das ist hier ein verlässliches Merkmal, kein Ratespiel. „Aufmerksamkeit"
    /// als Frage zu AUFFÄLLIG paart ein Substantiv mit einem Adjektiv.
    static let nonNounClasses: Set<String> = ["adjective", "verb", "adverb"]

    private static func looksLikeSingleNoun(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard words.count == 1, let first = words[0].first else { return false }
        return first.isUppercase
    }

    private func applyAmbiguityGate(_ clues: inout [String: [CatalogClue]],
                                    answers: [String: CatalogAnswer],
                                    report: inout ImportReport) {
        func length(_ surface: String) -> Int {
            Alphabet.normalize(surface)?.count ?? surface.count
        }
        var longIndex: [String: Set<String>] = [:]
        var shortIndex: [String: Set<String>] = [:]
        /// Ohne Längenschlüssel: zählt, für wie viele Antworten eine Kurzform
        /// überhaupt taugt.
        var shortGlobal: [String: Set<String>] = [:]

        for (surface, cs) in clues {
            let len = length(surface)
            for c in cs {
                longIndex["\(len)|\(c.text.lowercased())", default: []].insert(surface)
                if let s = c.shortText {
                    let key = s.lowercased()
                    shortIndex["\(len)|\(key)", default: []].insert(surface)
                    shortGlobal[key, default: []].insert(surface)
                }
            }
        }

        for (surface, cs) in clues {
            let len = length(surface)
            let wordClass = answers[surface]?.wordClass ?? ""
            var kept: [CatalogClue] = []
            for var c in cs {
                // Langform: unverändert bei drei Kollisionen gleicher Länge.
                if (longIndex["\(len)|\(c.text.lowercased())"]?.count ?? 0) >= 3 {
                    report.ambiguousDropped += 1
                    continue
                }

                if let short = c.shortText {
                    let key = short.lowercased()
                    var drop = false

                    // Kurzformen strenger: **zwei** reichen. Eine Kurzfrage, die
                    // auf zwei Antworten gleicher Länge passt, ist im Gitter
                    // nicht mehr entscheidbar — bei der Langform bleibt wenigstens
                    // der Rest des Satzes zur Unterscheidung.
                    if (shortIndex["\(len)|\(key)"]?.count ?? 0) >= 2 {
                        report.shortDroppedAmbiguous += 1
                        drop = true
                    } else if (shortGlobal[key]?.count ?? 0) >= Self.genericShortClueLimit {
                        report.shortDroppedGeneric += 1
                        drop = true
                    } else if Self.nonNounClasses.contains(wordClass),
                              Self.looksLikeSingleNoun(short) {
                        report.shortDroppedWordClass += 1
                        drop = true
                    }

                    if drop {
                        // Nur die Kurzform fällt weg — die Langform bleibt
                        // brauchbar, das Wort steht dann für `classic` zur Verfügung.
                        c.shortText = nil
                        c.shortWidth = nil
                        report.ambiguousDropped += 1
                    }
                }
                kept.append(c)
            }
            clues[surface] = kept
        }
    }
}
