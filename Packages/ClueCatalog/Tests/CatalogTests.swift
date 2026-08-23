import Testing
import Foundation
import PuzzleKit
@testable import ClueCatalog

private var repoRoot: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
}

private func loadAbbreviations() throws -> AbbreviationTable {
    try AbbreviationTable.load(path: repoRoot.appendingPathComponent("Resources/abbreviations.json").path)
}

private func loadWidths() -> GlyphWidthTable {
    let p = repoRoot.appendingPathComponent("Resources/glyphwidths.json")
    guard let d = try? Data(contentsOf: p),
          let t = try? JSONDecoder().decode(GlyphWidthTable.self, from: d) else { return .bootstrap }
    return t
}

@Suite("Titel-Normalisierung")
struct TitleTests {
    @Test func acceptsSingleWordNouns() throws {
        for t in ["Kartoffel", "Brot", "Ahorn", "Löwe", "Straße"] {
            let r = TitleNormalizer.normalize(title: t)
            #expect(throws: Never.self) { try r.get() }
        }
        // ß wird zu SS und verlängert damit das Wort — genau wie im Gitter.
        let s = try TitleNormalizer.normalize(title: "Straße").get()
        #expect(s.surface == "STRASSE")
    }

    @Test func rejectsWhatCannotGoIntoAGrid() {
        let cases: [(String, Rejection)] = [
            ("Fußball-Weltmeisterschaft", .hasHyphen),
            ("Berliner Mauer", .multiWord),
            ("Merkur (Planet)", .hasParen),
            ("Boeing 747", .multiWord),
            ("Curaçao", .badCharacters),
            ("Öl", .tooShort),
            ("Donaudampfschifffahrtsgesellschaft", .tooLong),
        ]
        for (title, expected) in cases {
            switch TitleNormalizer.normalize(title: title) {
            case .success: Issue.record("\(title) hätte abgelehnt werden müssen")
            case .failure(let r): #expect(r == expected, Comment(rawValue: "\(title): \(r)"))
            }
        }
    }

    @Test func abbreviationDetection() {
        #expect(TitleNormalizer.looksLikeAbbreviation("NATO"))
        #expect(TitleNormalizer.looksLikeAbbreviation("USA"))
        #expect(!TitleNormalizer.looksLikeAbbreviation("Kartoffel"))
    }

    @Test func properNounHeuristicUsesTheDescriptionNotCapitalisation() {
        // Im Deutschen sind alle Substantive groß — die Beschreibung entscheidet.
        #expect(TitleNormalizer.looksLikeProperNoun(
            description: "deutscher Politiker", zipf: 5.0, hasEverydayCategory: false))
        #expect(TitleNormalizer.looksLikeProperNoun(
            description: "Gemeinde in Bayern", zipf: 5.0, hasEverydayCategory: false))
        #expect(!TitleNormalizer.looksLikeProperNoun(
            description: "Nahrungsmittel aus Mehl und Wasser", zipf: 5.0,
            hasEverydayCategory: true))
    }
}

@Suite("Kurzclues")
struct ShortClueTests {
    @Test func abbreviationsApplyLongestPatternFirst() throws {
        let t = try loadAbbreviations()
        // Ohne Längensortierung würde "italienische" von "italienisch"
        // zerschnitten und "ital.e" ergeben.
        #expect(t.apply("italienische Stadt") == "ital. Stadt")
        #expect(t.apply("Hauptstadt von Frankreich").hasPrefix("Hauptst."))
    }

    @Test func abbreviationsRespectWordBoundariesAndInflection() throws {
        let t = try loadAbbreviations()
        // Der Fehler aus dem ersten echten Katalog: „amerik.n".
        #expect(!t.apply("aus der amerikanischen Küche").contains("amerik.n"))
        #expect(t.apply("aus der amerikanischen Küche") == "aus der amerik. Küche")
        #expect(t.apply("italienischer Käse") == "ital. Käse")
        // Kein Treffer mitten in einem längeren Wort.
        #expect(t.apply("Deutschlandlied") == "Deutschlandlied")
    }

    @Test func shortTextDropsDanglingFunctionWords() throws {
        let n = ClueNormalizer(abbreviations: try loadAbbreviations(), widths: loadWidths(),
                              singleBudget: 6_500)
        // „Feine Zucker- und" ist kein Clue, sondern ein Satzanfang.
        let s = try #require(n.shortText(from: "Bezeichnung für feine Zucker- und Backwaren"))
        #expect(!s.text.hasSuffix("und"))
        #expect(!s.text.hasSuffix("-"))
        #expect(s.width <= 6_500)
    }

    @Test func shortTextDropsDanglingAdjectiveAbbreviations() throws {
        let n = ClueNormalizer(abbreviations: try loadAbbreviations(), widths: loadWidths(),
                              singleBudget: 9_500)
        // „Eintopfgericht aus der amerik." ist unfertig — die Abkürzung eines
        // Adjektivs darf nicht am Ende stehen.
        let s = try #require(n.shortText(from: "Eintopfgericht aus der amerikanischen Küche"))
        #expect(!s.text.lowercased().hasSuffix("amerik."))
        #expect(!s.text.hasSuffix("der"))
    }

    @Test func shortTextCutsAtPhraseBoundaries() throws {
        let n = ClueNormalizer(abbreviations: try loadAbbreviations(), widths: loadWidths(),
                              singleBudget: 8_000)
        // Nicht „Pflanzenart aus der Gatt.", sondern der Schnitt vor „aus".
        let s = try #require(n.shortText(from: "Pflanzenart aus der Gattung Rubus"))
        #expect(s.text == "Pflanzenart")
        let t = try #require(n.shortText(from: "Eintopfgericht aus der amerikanischen Küche"))
        #expect(t.text == "Eintopfgericht")
    }

    @Test func shortTextFitsTheBudget() throws {
        let n = ClueNormalizer(abbreviations: try loadAbbreviations(), widths: loadWidths(),
                              singleBudget: 14_000)
        let long = "Nahrungsmittel, das aus Mehl, Wasser und weiteren Zutaten gebacken wird"
        let s = try #require(n.shortText(from: long))
        #expect(s.width <= 14_000)
        #expect(!s.text.contains(","))       // erste Klausel, Rest verworfen
        // Nicht abgekürzt, weil die Langform bereits ins Budget passt.
        #expect(s.text == "Nahrungsmittel")
    }

    @Test func widthIsMeasuredNotCounted() {
        // Der ganze Grund für die Glyph-Breitentabelle: gleiche Zeichenzahl,
        // sehr unterschiedliche Breite.
        let w = loadWidths()
        #expect(w.width(of: "MM") > w.width(of: "ill") * 2)
    }

    @Test func parentheticalsAreDropped() throws {
        let n = ClueNormalizer(abbreviations: try loadAbbreviations(), widths: loadWidths())
        let s = try #require(n.shortText(from: "Art der Gattung Nachtschatten (Solanum)"))
        #expect(!s.text.contains("("))
        #expect(!s.text.contains("Solanum"))
    }

    @Test func givesUpRatherThanProducingRubbish() throws {
        let n = ClueNormalizer(abbreviations: try loadAbbreviations(), widths: loadWidths(),
                              singleBudget: 900)   // absurd knapp
        // Lieber keine Kurzform als eine unbrauchbare: das Wort steht dann nur
        // für classic zur Verfügung.
        #expect(n.shortText(from: "Nahrungsmittel aus Mehl und Wasser") == nil)
    }

    @Test func stripsLeadingLemmaFromExtracts() {
        // Der Fehler, den der erste echte Lauf sichtbar gemacht hat: ohne diesen
        // Schritt scheitert jeder Artikel-Extrakt am Leak-Gatter.
        let a = ClueNormalizer.stripLeadingLemma(
            "Abdounodus ist eine ausgestorbene Gattung der Afrotheria.", title: "Abdounodus")
        #expect(a == "Ausgestorbene Gattung der Afrotheria.")
        let b = ClueNormalizer.stripLeadingLemma(
            "Der Ahorn ist eine Pflanzengattung in der Familie der Seifenbaumgewächse.",
            title: "Ahorn")
        #expect(b.hasPrefix("Pflanzengattung"))
        let c = ClueNormalizer.stripLeadingLemma("Hammer bezeichnet ein Werkzeug", title: "Hammer")
        #expect(c == "Werkzeug")
        // Nicht-Extrakte bleiben unangetastet, wenn kein Lemma am Anfang steht.
        let d = ClueNormalizer.stripLeadingLemma("Nahrungsmittel aus Mehl", title: "Brot")
        #expect(d == "Nahrungsmittel aus Mehl")
    }

    @Test func detectsLeakedAnswers() {
        #expect(ClueNormalizer.clueLeaksAnswer(clue: "Sorte von Brot", answerSurface: "BROT"))
        #expect(ClueNormalizer.clueLeaksAnswer(clue: "Brotsorte aus Roggen", answerSurface: "BROT"))
        #expect(ClueNormalizer.clueLeaksAnswer(clue: "Kartoffeln aus Bayern", answerSurface: "KARTOFFEL"))
        #expect(!ClueNormalizer.clueLeaksAnswer(clue: "Nahrungsmittel aus Mehl", answerSurface: "BROT"))
    }
}

@Suite("Häufigkeit und Tier")
struct FrequencyTests {
    @Test func zipfIsOnTheCanonicalScale() {
        // Referenz: Funktionswörter liegen bei ~7, sehr seltene Wörter bei ~1.
        let f = LeipzigFrequencies(counts: ["DIE": 534_906, "BROT": 1_400, "ZINNOBER": 6],
                                   totalTokens: 17_974_236, corpus: "test")
        let die = try! #require(f.zipf("DIE"))
        let brot = try! #require(f.zipf("BROT"))
        let selten = try! #require(f.zipf("ZINNOBER"))
        #expect(die > 7.0)
        #expect(brot > 4.5 && brot < 5.5)
        #expect(selten < 3.0)
        #expect(f.zipf("GIBTESNICHT") == nil)
    }

    @Test func pageviewFallbackStaysBelowTheEasyBand() {
        // Der Fallback darf nie in das Band der Stufe „Leicht" (>= 4.5) reichen:
        // ohne Korpusbeleg wissen wir nicht, ob das Wort gängig ist.
        for views in [0, 100, 10_000, 5_000_000] {
            let z = Frequency.zipfFromPageviews(views, hasEverydayCategory: true)
            #expect(z <= 4.6)
        }
    }

    @Test func tierThresholdsMatchTheRealDistribution() {
        // An der Leipzig-Verteilung kalibriert. Mit den ursprünglich geschätzten
        // Schwellen lagen 96 % aller Clues in Tier 4 und 5.
        #expect(Frequency.tier(zipf: 5.0, flags: [], aggressivelyShortened: false) == 1)
        #expect(Frequency.tier(zipf: 4.2, flags: [], aggressivelyShortened: false) == 2)
        #expect(Frequency.tier(zipf: 3.5, flags: [], aggressivelyShortened: false) == 3)
        #expect(Frequency.tier(zipf: 2.8, flags: [], aggressivelyShortened: false) == 4)
        #expect(Frequency.tier(zipf: 1.5, flags: [], aggressivelyShortened: false) == 5)
    }

    @Test func tierGetsHarderForProperNounsAndAbbreviations() {
        let plain = Frequency.tier(zipf: 4.2, flags: [], aggressivelyShortened: false)
        let proper = Frequency.tier(zipf: 4.2, flags: [.properNoun], aggressivelyShortened: false)
        let abbr = Frequency.tier(zipf: 4.2, flags: [.abbreviation], aggressivelyShortened: false)
        #expect(proper > plain)
        #expect(abbr > plain)
        // Nie über 5 hinaus.
        #expect(Frequency.tier(zipf: 1.0, flags: [.properNoun, .abbreviation],
                               aggressivelyShortened: true) == 5)
    }
}

@Suite("Assembler")
struct AssemblerTests {
    private func wiki(_ title: String, _ desc: String?, views: Int = 6000,
                      cats: [String] = ["Lebensmittel"]) -> RawEntry? {
        let json = """
        {"title":"\(title)","description":\(desc.map { "\"\($0)\"" } ?? "null"),
         "descriptionSource":"central","pageviews60":\(views),"topviewsMonthly":null,
         "categories":\(cats.map { "\"\($0)\"" }),"pageid":1,"source":"de.wikipedia"}
        """
        return try! JSONDecoder().decode(WikipediaRecord.self, from: Data(json.utf8)).rawEntry
    }

    private func wikt(_ lemma: String, _ senses: [String],
                      classes: [String] = ["noun"]) -> RawEntry? {
        RawEntry(title: lemma,
                 descriptions: senses.map { RawDescription(text: $0, source: .wiktionary) },
                 topics: [], wordClasses: classes, sourceRef: "de.wiktionary:\(lemma)")
    }

    private func assembler(freq: LeipzigFrequencies? = nil) throws -> CatalogAssembler {
        CatalogAssembler(normalizer: ClueNormalizer(abbreviations: try loadAbbreviations(),
                                                    widths: loadWidths(), singleBudget: 14_000),
                         frequencies: freq, doubleBudget: 7_500)
    }

    @Test func endToEndOnSyntheticRecords() throws {
        let entries = [
            wiki("Brot", "Nahrungsmittel, das aus Mehl und Wasser gebacken wird"),
            wiki("Kartoffel", "Art der Gattung Nachtschatten (Solanum)"),
            wiki("Berliner Mauer", "Grenzanlage"),
            wiki("Ahorn", nil),
            wiki("Hammer", "händisch angetriebenes Werkzeug", cats: ["Werkzeug"]),
        ].compactMap { $0 }
        let (answers, clues, report) = try assembler().assemble(entries)
        #expect(answers.map(\.surface) == ["BROT", "HAMMER", "KARTOFFEL"])
        #expect(report.rejections[.multiWord] == 1)
        #expect(clues["BROT"]?.first?.shortText != nil)
        for a in answers { #expect(!(clues[a.surface] ?? []).isEmpty) }
    }

    @Test func mergesSourcesForTheSameAnswer() throws {
        // Wiktionary und Wikipedia beschreiben dasselbe Wort: beide Clues
        // behalten, Wiktionary zuerst (bessere Definitionen).
        let entries = [
            wiki("Hammer", "händisch angetriebenes Werkzeug", cats: ["Werkzeug"]),
            wikt("Hammer", ["Werkzeug bestehend aus Kopf und Stiel",
                            "große Maschine zur Umformung von Metall"]),
        ].compactMap { $0 }
        let (answers, clues, report) = try assembler().assemble(entries)
        #expect(answers.count == 1)
        #expect(clues["HAMMER"]?.count == 3)
        #expect(report.mergedAcrossSources == 1)
        #expect(report.bySource["wiktionary"] == 2)
        #expect(report.bySource["wikidata"] == 1)
    }

    @Test func wordClassBeatsTheProperNounHeuristic() throws {
        // „Baum" hat auch einen Nachnamen-Abschnitt; ist die Gattungswortart
        // dabei, ist es kein Eigenname.
        let both = try #require(wikt("Baum", ["aus Stamm und Krone bestehende Gehölzpflanze"],
                                     classes: ["noun", "propernoun"]))
        let onlyProper = try #require(wikt("Zwickau", ["Stadt in Sachsen"],
                                           classes: ["propernoun"]))
        let (answers, _, _) = try assembler().assemble([both, onlyProper])
        let baum = try #require(answers.first { $0.surface == "BAUM" })
        let zwickau = try #require(answers.first { $0.surface == "ZWICKAU" })
        #expect(!baum.flags.contains(.properNoun))
        #expect(zwickau.flags.contains(.properNoun))
    }

    @Test func corpusFrequencyBeatsPageviewFallback() throws {
        let freq = LeipzigFrequencies(counts: ["BROT": 3_000], totalTokens: 1_000_000,
                                      corpus: "test")
        let entries = [wiki("Brot", "Nahrungsmittel aus Mehl"),
                       wiki("Yakitori", "Japanisches Gericht", views: 30)].compactMap { $0 }
        let (answers, _, report) = try assembler(freq: freq).assemble(entries)
        #expect(report.zipfFromCorpus == 1)
        #expect(report.zipfFromPageviews == 1)
        let brot = try #require(answers.first { $0.surface == "BROT" })
        // 3000 / 1e6 * 1e6 = 3000 pro Million -> zipf = log10(3000) + 3 ≈ 6.48
        #expect(brot.zipf > 6.0 && brot.zipf < 7.0)
        let yakitori = try #require(answers.first { $0.surface == "YAKITORI" })
        // Fallback bleibt bewusst unter dem Band der Stufe „Leicht".
        #expect(yakitori.zipf < 4.6)
    }

    @Test func ambiguityGateDropsCluesSharedByThreeAnswersOfEqualLength() throws {
        let entries = [
            wiki("Amsel", "Wirbeltier mit Federn und Schnabel"),
            wiki("Möwen", "Wirbeltier mit Federn und Schnabel"),
            wiki("Adler", "Wirbeltier mit Federn und Schnabel"),
            wiki("Brot", "Nahrungsmittel aus Mehl"),
        ].compactMap { $0 }
        let (answers, clues, report) = try assembler().assemble(entries)
        #expect(report.ambiguousDropped >= 3)
        #expect(!answers.map(\.surface).contains("AMSEL"))
        #expect(answers.map(\.surface).contains("BROT"))
        #expect(clues["AMSEL"] == nil)
    }

    @Test func assemblyIsOrderIndependent() throws {
        let entries = [
            wiki("Brot", "Nahrungsmittel aus Mehl"),
            wikt("Hammer", ["Werkzeug zum Schlagen"]),
            wiki("Kartoffel", "Art der Gattung Nachtschatten"),
        ].compactMap { $0 }
        let a = try assembler().assemble(entries)
        let b = try assembler().assemble(entries.reversed())
        #expect(a.answers.map(\.surface) == b.answers.map(\.surface))
        #expect(a.answers.map(\.zipf) == b.answers.map(\.zipf))
        #expect(a.clues["HAMMER"]?.map(\.text) == b.clues["HAMMER"]?.map(\.text))
    }
}

@Suite("Katalog schreiben und lesen")
struct RoundTripTests {
    @Test func writeThenLoadLexicon() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kreuzwort-test-\(ProcessInfo.processInfo.processIdentifier).sqlite")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let answers = [
            CatalogAnswer(surface: "BROT", zipf: 5.2, flags: [], topics: ["Lebensmittel"],
                          sourceRef: "test:1"),
            CatalogAnswer(surface: "HAMMER", zipf: 4.4, flags: [], topics: ["Werkzeug"],
                          sourceRef: "test:2"),
            // Ohne Clue: darf im Lexicon nicht auftauchen.
            CatalogAnswer(surface: "OHNECLUE", zipf: 5.0, flags: [], topics: [],
                          sourceRef: "test:3"),
        ]
        let clues: [String: [CatalogClue]] = [
            "BROT": [CatalogClue(text: "Nahrungsmittel aus Mehl", shortText: "Nahrungsmittel",
                                 shortWidth: 8_000, kind: .definition, tier: 2, locale: "de",
                                 license: "CC0 (Wikidata)", sourceRef: "test:1")],
            "HAMMER": [CatalogClue(text: "Werkzeug zum Schlagen", shortText: nil, shortWidth: nil,
                                   kind: .definition, tier: 3, locale: "de",
                                   license: "CC0 (Wikidata)", sourceRef: "test:2")],
        ]

        let w = try CatalogWriter(path: tmp.path, fresh: true)
        let counts = try w.write(answers: answers, cluesByAnswer: clues)
        try w.setMeta(["catalogVersion": "1", "locale": "de"])
        #expect(counts.answers == 3)
        #expect(counts.clues == 2)

        let r = try CatalogReader(path: tmp.path)
        #expect(r.catalogVersion == 1)
        let lex = try r.loadLexicon()
        #expect(lex.count == 2, Comment(rawValue: "Antworten ohne Clue müssen wegfallen"))
        let surfaces = lex.entries.map(\.surface).sorted()
        #expect(surfaces == ["BROT", "HAMMER"])

        let brot = try #require(lex.entries.first { $0.surface == "BROT" })
        #expect(brot.hasClueByTier[1])                       // Tier 2 → Index 1
        #expect(brot.minShortWidthByTier[1] == 8_000)
        let hammer = try #require(lex.entries.first { $0.surface == "HAMMER" })
        #expect(hammer.minShortWidthByTier[2] == Int32.max)   // kein Kurzclue
    }

    @Test func lexiconSortIsStable() throws {
        let e1 = LexEntry(answerID: 5, letters: Alphabet.normalize("HAUS")!, zipf: 4,
                          flags: [], minShortWidthByTier: [Int32](repeating: .max, count: 5),
                          hasClueByTier: [true, false, false, false, false])
        let e2 = LexEntry(answerID: 1, letters: Alphabet.normalize("BAUM")!, zipf: 4,
                          flags: [], minShortWidthByTier: [Int32](repeating: .max, count: 5),
                          hasClueByTier: [true, false, false, false, false])
        let a = Lexicon(entries: [e1, e2], catalogVersion: 1)
        let b = Lexicon(entries: [e2, e1], catalogVersion: 1)
        #expect(a.entries.map(\.surface) == b.entries.map(\.surface))
        #expect(a.entries.first?.surface == "BAUM")
    }
}

@Suite("Fragen-Trennschärfe")
struct ClueSharpnessTests {
    static func hasNoun(_ t: String) -> Bool {
        t.split(separator: " ").dropFirst().contains { $0.first?.isUppercase == true }
    }

    private func normalizer(_ budget: Int = 9_500) throws -> ClueNormalizer {
        ClueNormalizer(abbreviations: try loadAbbreviations(), widths: loadWidths(),
                       singleBudget: budget)
    }

    @Test func shortTextRejectsNounlessPhrases() throws {
        let n = try normalizer()
        // Stand so im gerenderten Rätsel: ERDE — „Belebter und dritter".
        // Eine mehrwortige Wortgruppe ohne Substantiv ist keine Frage.
        // Die Wortgruppe „Belebter und dritter" darf nicht stehenbleiben.
        // Ein einzelnes Fragment ist zugelassen (siehe Normalize.swift).
        let s = n.shortText(
            from: "Belebter und dritter, von der Sonne aus gezählter Planet in unserem Sonnensystem")
        if let s, s.text.contains(" ") { #expect(Self.hasNoun(s.text)) }
        #expect(s?.text != "Belebter und dritter")
    }

    @Test func shortTextKeepsSingleWordAdjectives() throws {
        let n = try normalizer()
        // Die Substantiv-Regel darf einwortige Fragen nicht mitreißen:
        // „Echt" ist eine gute Frage zu WAHR.
        let s = try #require(n.shortText(from: "Echt"))
        #expect(s.text == "Echt")
    }

    @Test func longTextTrimsDanglingClause() throws {
        let n = try normalizer()
        // Stand so im gerenderten Rätsel: DOMAIN — „Ein Namensbereich, der
        // dazu dient". Ein angefangener Nebensatz ist keine Frage.
        let t = try n.longText(
            from: "Ein Namensbereich, der dazu dient, Rechner im Internet zu gruppieren"
        ).get()
        #expect(!t.hasSuffix("dient"))
        #expect(!t.hasSuffix("der"))
        #expect(!t.hasSuffix(","))
        #expect(t.hasPrefix("Ein Namensbereich"))
    }

    @Test func longTextStripsContextPrefix() throws {
        let n = try normalizer()
        // Stand so im gerenderten Rätsel: ASYL — „Rechtssprache; kein Plural:
        // Schutz". Die Einordnung vor dem Doppelpunkt ist Metainformation.
        let t = try n.longText(
            from: "Rechtssprache; kein Plural: Schutz vor politischer Verfolgung").get()
        #expect(t == "Schutz vor politischer Verfolgung")
    }

    @Test func shortTextDropsTrailingPrepositions() throws {
        // Budget wie bei einer Einzelzelle im Schwedenrätsel — bei 9.500
        // kürzt die Leiter bis auf ein Wort und die Präposition entfällt
        // ohnehin.
        let n = try normalizer(16_000)
        // Stand so im gerenderten Rätsel: TAL — „Tiefergelegenes Gelände
        // zwischen". Eine Präposition am Ende lässt die Frage offen.
        let s = try #require(n.shortText(
            from: "Tiefergelegenes Gelände zwischen Erhebungen, Geländeeinschnitt"))
        #expect(!s.text.hasSuffix("zwischen"))
        #expect(s.text == "Tiefergelegenes Gelände")
    }

    @Test func longTextKeepsRealColons() throws {
        let n = try normalizer()
        // Ein Doppelpunkt spät im Text ist Teil der Definition, kein Präfix.
        let source = "Gerät zur Messung des Luftdrucks: es zeigt Wetteränderungen an"
        let t = try n.longText(from: source).get()
        #expect(t.hasPrefix("Gerät zur Messung"))
    }
}
