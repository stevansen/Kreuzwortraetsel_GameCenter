import Foundation
import PuzzleKit
import ClueCatalog

// catalogbuild — Rohdaten aus drei Quellen → catalog.sqlite.
//
// Stufe 1 (Ernten) sitzt in scripts/harvest_*.py: Netzzugriffe und Dumps sind
// nicht reproduzierbar. Alles ab hier ist deterministisch und getestet.
//
//   Wiktionary  Definitionen (die besten Fragen)          CC BY-SA 4.0
//   Wikipedia   Kurzbeschreibungen, Eigennamen, Spezialwortschatz  CC0 / CC BY-SA
//   Leipzig     Worthäufigkeit (die echte Zipf-Skala)      CC BY 4.0

struct Args {
    var flags: [String: String] = [:]
    var positional: [String] = []
    init(_ argv: [String]) {
        var i = 0
        while i < argv.count {
            let a = argv[i]
            if a.hasPrefix("--") {
                let k = String(a.dropFirst(2))
                if i + 1 < argv.count, !argv[i + 1].hasPrefix("--") { flags[k] = argv[i + 1]; i += 2 }
                else { flags[k] = "1"; i += 1 }
            } else { positional.append(a); i += 1 }
        }
    }
    func str(_ k: String, _ d: String) -> String { flags[k] ?? d }
    func has(_ k: String) -> Bool { flags[k] != nil }
}

func die(_ m: String) -> Never {
    FileHandle.standardError.write(Data(("fehler: " + m + "\n").utf8))
    exit(1)
}

func loadWidths(_ path: String) -> GlyphWidthTable {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let t = try? JSONDecoder().decode(GlyphWidthTable.self, from: d)
    else {
        print("warnung: \(path) nicht lesbar — Bootstrap-Breitentabelle wird verwendet")
        return .bootstrap
    }
    return t
}

func bar(_ n: Int, max m: Int, width: Int = 26) -> String {
    guard m > 0, n > 0 else { return "" }
    return String(repeating: "█", count: max(1, Int(Double(n) / Double(m) * Double(width))))
}

func pad(_ s: String, _ n: Int) -> String {
    s.count >= n ? s : s + String(repeating: " ", count: n - s.count)
}

// MARK: - build

func cmdBuild(_ a: Args) {
    let output = a.str("out", "Resources/catalog.sqlite")
    let widths = loadWidths(a.str("widths", "Resources/glyphwidths.json"))
    let abbr: AbbreviationTable
    do { abbr = try AbbreviationTable.load(path: a.str("abbreviations", "Resources/abbreviations.json")) }
    catch { die("Abkürzungstabelle: \(error)") }

    // Budgets aus dem Profil, nicht aus der Kommandozeile: Balancing gehört an
    // eine Stelle, und die heißt DifficultyProfile.
    let arrow = DifficultyProfile.profile(.arrow, .mittel)

    // --- Häufigkeiten ---
    var frequencies: LeipzigFrequencies?
    let freqTSV = a.str("leipzig", "raw/leipzig/de-frequencies.tsv")
    let freqMeta = a.str("leipzig-meta", "raw/leipzig/leipzig-meta.json")
    if FileManager.default.fileExists(atPath: freqTSV) {
        do {
            let f = try LeipzigFrequencies.load(tsv: freqTSV, meta: freqMeta)
            frequencies = f
            print("Leipzig: \(f.formCount) Formen, \(f.totalTokens) Tokens (\(f.corpus))")
        } catch { print("warnung: Leipzig nicht lesbar (\(error)) — Fallback auf Aufrufzahlen") }
    } else {
        print("warnung: \(freqTSV) fehlt — Häufigkeit fällt auf Aufrufzahlen zurück")
    }

    // --- Quellen ---
    var entries: [RawEntry] = []
    let wiktPath = a.str("wiktionary", "raw/wiktionary/de-entries.jsonl")
    if FileManager.default.fileExists(atPath: wiktPath) {
        do {
            let e = try RawSourceLoader.wiktionary(path: wiktPath)
            print("Wiktionary: \(e.count) Einträge")
            entries += e
        } catch { die("Wiktionary lesen: \(error)") }
    }
    for key in ["wikipedia", "wikipedia-extra"] {
        guard let path = a.flags[key] ?? (key == "wikipedia"
            ? "raw/wikipedia/de-candidates.jsonl" : nil) else { continue }
        guard FileManager.default.fileExists(atPath: path) else {
            if a.flags[key] != nil { print("warnung: \(path) fehlt") }
            continue
        }
        do {
            let e = try RawSourceLoader.wikipedia(path: path)
            print("Wikipedia (\(path)): \(e.count) Einträge")
            entries += e
        } catch { die("Wikipedia lesen: \(error)") }
    }
    guard !entries.isEmpty else { die("keine Quelle gefunden — zuerst scripts/harvest_*.py laufen lassen") }

    // --- Zusammensetzen ---
    let normalizer = ClueNormalizer(abbreviations: abbr, widths: widths,
                                    maxLongLength: 90, singleBudget: arrow.singleClueBudget)
    let assembler = CatalogAssembler(normalizer: normalizer, frequencies: frequencies,
                                     doubleBudget: arrow.doubleClueBudget)
    print("\nassembliere \(entries.count) Rohdatensätze …")
    let (answers, clues, report) = assembler.assemble(entries)

    do {
        let w = try CatalogWriter(path: output, fresh: true)
        let counts = try w.write(answers: answers, cluesByAnswer: clues)
        try w.setMeta([
            "catalogVersion": String(CatalogSchema.version),
            "locale": "de",
            "abbreviationsVersion": String(abbr.version),
            "widthTableFont": widths.fontName,
            "singleClueBudget": String(arrow.singleClueBudget),
            "doubleClueBudget": String(arrow.doubleClueBudget),
            "frequencyCorpus": frequencies?.corpus ?? "none",
        ])
        try w.analyze()
        print("geschrieben: \(counts.answers) Antworten, \(counts.clues) Clues, "
            + "\(counts.topics) Themenzuordnungen → \(output)")
    } catch { die("schreiben: \(error)") }

    writeAttribution(report: report, output: output, corpus: frequencies?.corpus)
    printReport(report, singleBudget: arrow.singleClueBudget, doubleBudget: arrow.doubleClueBudget)
}

func writeAttribution(report: ImportReport, output: String, corpus: String?) {
    var md = """
    # Attribution

    Der Fragenkatalog wird von `catalogbuild` erzeugt. Diese Datei ist generiert —
    nicht von Hand pflegen.

    ## Quellen

    - **Deutsches Wiktionary** — CC BY-SA 4.0. <https://de.wiktionary.org/>
      Definitionen aus dem Block `{{Bedeutungen}}` des deutschen Abschnitts.
    - **Wikidata-Kurzbeschreibungen** — CC0 1.0. <https://www.wikidata.org/>
    - **Wikipedia-Artikeltexte** — CC BY-SA 4.0. <https://de.wikipedia.org/>
      Nur als Lückenfüller, erster Satz, Lemma entfernt.
    - **Leipzig Corpora Collection** — CC BY 4.0. <https://wortschatz.uni-leipzig.de/>
      Worthäufigkeiten\(corpus.map { " (Korpus `\($0)`)" } ?? "").
      Goldhahn, Eckart, Quasthoff: *Building Large Monolingual Dictionaries at the
      Leipzig Corpora Collection*, LREC 2012.

    Die Herkunft steht pro Clue in `clues.source_ref` und `clues.license`.

    ## Clues nach Lizenz


    """
    for (license, n) in report.byLicense.sorted(by: { $0.value > $1.value }) {
        md += "- \(license): \(n)\n"
    }
    md += """

    ## Weiterverwendung

    CC-BY-SA-Clues verlangen Namensnennung und Share-Alike. Wenn das für die
    Auslieferung ein Problem ist, lässt sich der Katalog auf
    `license LIKE 'CC0%'` einschränken; die Abdeckung sinkt dann deutlich, weil
    die Wiktionary-Definitionen — die besten Fragen — CC BY-SA sind.

    """
    let dir = (output as NSString).deletingLastPathComponent
    let path = (dir.isEmpty ? "." : dir) + "/ATTRIBUTION.md"
    try? md.write(toFile: path, atomically: true, encoding: .utf8)
    print("Attribution → \(path)")
}

func printReport(_ r: ImportReport, singleBudget: Int, doubleBudget: Int) {
    let acceptRate = Double(r.accepted) / Double(max(r.read, 1))
    print("\n== Abdeckungsreport ==")
    print("gelesen \(r.read) · akzeptiert \(r.accepted) (\(pct(acceptRate)))"
        + " · quellenübergreifend zusammengeführt \(r.mergedAcrossSources)")
    print("Eigennamen \(r.properNouns) (\(pct(Double(r.properNouns) / Double(max(r.accepted, 1)))))"
        + " · Clues mit Kurzform \(r.withShortText)"
        + " · mehrdeutig verworfen \(r.ambiguousDropped)")
    print("Häufigkeit: \(r.zipfFromCorpus) aus Korpus, \(r.zipfFromPageviews) aus Aufrufzahlen")
    print("Verworfene Kurzformen: \(r.shortDroppedAmbiguous) mehrdeutig (gleiche Länge), "
        + "\(r.shortDroppedGeneric) generisch (katalogweit), "
        + "\(r.shortDroppedWordClass) Wortart passt nicht")

    print("\nClues nach Quelle:")
    for (s, n) in r.bySource.sorted(by: { $0.value > $1.value }) { print("  \(pad(s, 18)) \(n)") }

    print("\nAblehnungsgründe:")
    let maxRej = r.rejections.values.max() ?? 1
    for (reason, n) in r.rejections.sorted(by: { $0.value > $1.value }) {
        print("  \(pad(reason.rawValue, 22)) \(pad(String(n), 8)) \(bar(n, max: maxRej))")
    }

    print("\nAntworten pro Länge (Ziel: >= 800 je Länge 3–15):")
    let maxLen = r.byLength.values.max() ?? 1
    var lengthGaps: [Int] = []
    for len in 3 ... 15 {
        let n = r.byLength[len] ?? 0
        if n < 800 { lengthGaps.append(len) }
        let s1 = r.shortInSingleBudget[len] ?? 0
        let s2 = r.shortInDoubleBudget[len] ?? 0
        let flag = n >= 800 ? "✓" : (n >= 300 ? "·" : "✗")
        print("  \(pad(String(len), 3)) \(pad(String(n), 7))\(flag)  "
            + "kurz: \(pad(String(s1), 7))doppel: \(pad(String(s2), 7))"
            + bar(n, max: maxLen, width: 18))
    }

    print("\nClues pro Tier (1 = leicht … 5 = Experte):")
    let maxTier = r.byTier.values.max() ?? 1
    for t in 1 ... 5 {
        let n = r.byTier[t] ?? 0
        print("  \(t)  \(pad(String(n), 9))\(bar(n, max: maxTier))")
    }

    print("\nLizenzen:")
    for (l, n) in r.byLicense.sorted(by: { $0.value > $1.value }) { print("  \(l): \(n)") }

    if !lengthGaps.isEmpty {
        print("\nLücken bei Länge \(lengthGaps.map(String.init).joined(separator: ", "))"
            + " — dort reicht das Vokabular für dichte Gitter noch nicht.")
    }
}

let argv = Array(CommandLine.arguments.dropFirst())
guard let sub = argv.first else {
    print("""
    catalogbuild <befehl>

      build   Baut catalog.sqlite aus allen verfügbaren Quellen.
              Flags: --out --wiktionary --wikipedia --wikipedia-extra
                     --leipzig --leipzig-meta --widths --abbreviations
    """)
    exit(0)
}
switch sub {
case "build", "wikipedia": cmdBuild(Args(Array(argv.dropFirst())))
default: die("unbekannter Befehl: \(sub)")
}
