import Foundation
import PuzzleKit
import ClueCatalog

// puzzlegen — Offline-Werkzeug für Templates, Batch-Generierung und Vorschau.
// Bewusst ohne Argument-Parser-Abhängigkeit: ein paar Zeilen Handarbeit sind
// billiger als eine Dependency in einem Projekt mit null Dependencies.

struct Args {
    var positional: [String] = []
    var flags: [String: String] = [:]

    init(_ argv: [String]) {
        var i = 0
        while i < argv.count {
            let a = argv[i]
            if a.hasPrefix("--") {
                let key = String(a.dropFirst(2))
                if i + 1 < argv.count, !argv[i + 1].hasPrefix("--") {
                    flags[key] = argv[i + 1]; i += 2
                } else {
                    flags[key] = "1"; i += 1
                }
            } else {
                positional.append(a); i += 1
            }
        }
    }

    func string(_ k: String, _ d: String) -> String { flags[k] ?? d }
    func int(_ k: String, _ d: Int) -> Int { flags[k].flatMap(Int.init) ?? d }
    func uint64(_ k: String, _ d: UInt64) -> UInt64 { flags[k].flatMap(UInt64.init) ?? d }
    var has: (String) -> Bool { { flags[$0] != nil } }
}

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(Data(("fehler: " + msg + "\n").utf8))
    exit(1)
}

func repoRoot() -> URL {
    // Die CLI läuft aus .build/…; die Wurzel kommt über das aktuelle
    // Verzeichnis oder --root, nicht über #filePath (das zeigt auf die Quelle).
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}

// MARK: - templates

func cmdTemplates(_ args: Args) {
    let root = args.flags["root"].map { URL(fileURLWithPath: $0) } ?? repoRoot()
    let outDir = root.appendingPathComponent(args.string("out", "Resources/grids/classic"))
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let count = args.int("count", 24)
    let seed = args.uint64("seed", 20_260_823)

    // Zielgrößen und Bänder kommen aus den Profilen — nicht aus der Kommandozeile.
    // Balancing gehört an eine Stelle, und das ist DifficultyProfile.
    var jobs: [(GridSize, DifficultyProfile, Difficulty)] = []
    for d in Difficulty.allCases {
        let p = DifficultyProfile.profile(.classic, d)
        for s in p.sizes { jobs.append((s, p, d)) }
    }

    var summary: [String] = []
    for (size, profile, diff) in jobs {
        let t0 = Date()
        let result = TemplateSearch.detailedSearch(
            size: size, ratio: profile.deadCellRatio,
            minWord: profile.wordLength.lowerBound,
            maxWord: profile.wordLength.upperBound,
            crossRatio: profile.crossRatio, count: count, seed: seed)
        let found = result.templates
        let secs = Date().timeIntervalSince(t0)
        guard !found.isEmpty else {
            let why = result.failures.sorted { $0.value > $1.value }
                .prefix(4).map { "\($0.key.rawValue)×\($0.value)" }.joined(separator: ", ")
            summary.append("  \(size.label) [\(diff.rawValue)]: KEINE gefunden "
                + "(\(result.attempts) Versuche: \(why))")
            continue
        }
        let set = TemplateSet(templates: found)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = outDir.appendingPathComponent("\(size.cols)x\(size.rows).json")
        do { try enc.encode(set).write(to: url) } catch { die("schreiben: \(error)") }
        let ratios = found.map(\.blockRatio)
        summary.append("  \(size.label) [\(diff.rawValue)]: \(found.count) Templates, "
            + "Schwarzanteil \(pct(ratios.min()!))–\(pct(ratios.max()!)), "
            + "\(fmt(secs, 1)) s → \(url.lastPathComponent)")
    }
    print("Templatesuche:")
    summary.forEach { print($0) }

    // Eine Stichprobe zeigen — beim Balancing will man das Muster sehen.
    if let example = try? Data(contentsOf: outDir.appendingPathComponent("11x11.json")),
       let set = try? JSONDecoder().decode(TemplateSet.self, from: example),
       let first = set.templates.first {
        print("\nBeispiel 11×11 (\(pct(first.blockRatio)) Schwarzfelder):")
        print(first.pretty)
    }
}

// MARK: - gen

func loadWidths(_ path: String) -> GlyphWidthTable {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let t = try? JSONDecoder().decode(GlyphWidthTable.self, from: d)
    else { return .bootstrap }
    return t
}

func loadTemplates(_ dir: URL) -> [GridTemplate] {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return [] }
    var out: [GridTemplate] = []
    for name in names.sorted() where name.hasSuffix(".json") {
        if let d = try? Data(contentsOf: dir.appendingPathComponent(name)),
           let set = try? JSONDecoder().decode(TemplateSet.self, from: d) {
            out += set.templates
        }
    }
    return out
}

struct GenContext {
    let index: PatternIndex
    let clues: CatalogClueSource
    let widths: GlyphWidthTable
    let templates: [GridTemplate]
}

func makeContext(_ args: Args) -> GenContext {
    let root = args.flags["root"].map { URL(fileURLWithPath: $0) } ?? repoRoot()
    let catalogPath = args.string("catalog", "Resources/catalog.sqlite")
    let reader: CatalogReader
    do { reader = try CatalogReader(path: catalogPath) }
    catch { die("Katalog \(catalogPath): \(error)") }

    let t0 = Date()
    let lexicon: Lexicon
    do { lexicon = try reader.loadLexicon() } catch { die("Lexicon: \(error)") }
    let loadSecs = Date().timeIntervalSince(t0)

    let t1 = Date()
    let index = PatternIndex(lexicon: lexicon)
    let indexSecs = Date().timeIntervalSince(t1)

    print("Katalog: \(lexicon.count) Antworten (Version \(reader.catalogVersion)), "
        + "geladen in \(fmt(loadSecs, 2)) s, Index in \(fmt(indexSecs, 2)) s")
    let templates = loadTemplates(root.appendingPathComponent("Resources/grids/classic"))
    print("Templates: \(templates.count)")
    return GenContext(index: index,
                      clues: CatalogClueSource(reader: reader,
                                               widths: loadWidths(args.string("widths", "Resources/glyphwidths.json"))),
                      widths: loadWidths(args.string("widths", "Resources/glyphwidths.json")),
                      templates: templates)
}

func cmdGen(_ args: Args) {
    let ctx = makeContext(args)
    let variantName = args.string("variant", "classic")
    guard let variant = PuzzleVariant(rawValue: variantName) else {
        die("unbekannte Variante: \(variantName)")
    }
    let diffName = args.string("difficulty", "mittel")
    guard let difficulty = Difficulty(rawValue: diffName) else {
        die("unbekannte Stufe: \(diffName)")
    }
    let layout: any LayoutProvider
    switch variant {
    case .classic: layout = ClassicLayout(templates: ctx.templates)
    case .arrow: layout = ArrowLayout()
    }

    let gen = Generator(layout: layout, index: ctx.index, clues: ctx.clues, widths: ctx.widths,
                        branchLimit: args.int("branch", 80),
                        lcvWidth: args.int("lcv", 18))
    let seed = args.uint64("seed", 1)
    let t0 = Date()

    // Fortschrittsdiagnose: einen Versuch von Hand fahren, damit bei Fehlschlag
    // sichtbar ist, wie weit die Suche kam und an welchem Slot sie hing.
    if args.has("trace") {
        var rng = SplitMix64(seed: SplitMix64.derive(seed, 0))
        let size = profile2(variant, difficulty).sizes[0]
        if let topo = try? layout.makeTopology(size: size,
                                               profile: profile2(variant, difficulty), rng: &rng) {
            let p = profile2(variant, difficulty)
            let filters = gen.slotFilters(topology: topo, profile: p)
            let engine = FillEngine(index: ctx.index, topology: topo, profile: p,
                                    slotFilters: filters, branchLimit: args.int("branch", 80))
            let box = FillEngine.TraceBox()
            _ = try? engine.fill(rng: &rng, trace: box)
            let t = box.trace
            print("\nSpur: \(t.maxFilled)/\(topo.slots.count) Slots maximal belegt, "
                + "\(t.nodes) Knoten")
            let worst = t.blockedBySlot.sorted { $0.value > $1.value }.prefix(6)
            if !worst.isEmpty {
                print("häufigste Blockade:")
                for (id, hits) in worst {
                    if let s = topo.slots.first(where: { $0.id == id }) {
                        let cands = ctx.index.mask(length: s.length,
                                                   filter: filters[topo.slots.firstIndex(of: s)!])
                        print("  Slot \(id) Länge \(s.length) \(s.direction.label) "
                            + "bei (\(s.start.row),\(s.start.col)) · \(hits)× blockiert · "
                            + "\(cands.count) Startkandidaten")
                    }
                }
            }
        }
    }

    do {
        let (puzzle, report) = try gen.generate(seed: seed, difficulty: difficulty)
        let secs = Date().timeIntervalSince(t0)
        print("\n" + AsciiRender.summary(puzzle))
        print("Versuche \(report.attempts) · Suchknoten \(report.nodes) · \(fmt(secs, 2)) s\n")
        print(AsciiRender.grid(puzzle))
        print("\nFragen:")
        print(AsciiRender.clueList(puzzle, limit: args.int("clues", 12)))
    } catch {
        print("\nGENERIERUNG GESCHEITERT nach \(fmt(Date().timeIntervalSince(t0), 2)) s")
        print("\(error)")
        exit(2)
    }
}

func profile2(_ v: PuzzleVariant, _ d: Difficulty) -> DifficultyProfile {
    DifficultyProfile.profile(v, d)
}

// MARK: - sweep

/// Der Robustheitstest aus dem Prompt: viele Seeds, beide Varianten, alle
/// Stufen — und die Erfolgsquote als Zahl statt als Gefühl.
func cmdSweep(_ args: Args) {
    let ctx = makeContext(args)
    let seeds = args.int("seeds", 100)
    let variantNames = args.string("variant", "classic").split(separator: ",").map(String.init)

    for name in variantNames {
        guard let variant = PuzzleVariant(rawValue: name) else { die("Variante? \(name)") }
        let layout: any LayoutProvider = variant == .classic
            ? ClassicLayout(templates: ctx.templates) : ArrowLayout()
        let gen = Generator(layout: layout, index: ctx.index, clues: ctx.clues, widths: ctx.widths)
        print("\n== \(variant.label) ==")
        for difficulty in Difficulty.allCases {
            var ok = 0, firstTry = 0, nodes = 0, words = 0, shortClues = 0
            var reasons: [String: Int] = [:]
            let t0 = Date()
            var worst = 0.0
            for i in 0 ..< seeds {
                let s0 = Date()
                do {
                    let (puzzle, report) = try gen.generate(seed: UInt64(i + 1),
                                                            difficulty: difficulty)
                    ok += 1
                    if report.attempts == 1 { firstTry += 1 }
                    nodes += report.nodes
                    words += puzzle.entries.count
                    shortClues += puzzle.entries.count { $0.clueShortText != nil }
                } catch {
                    let key = "\(error)".prefix(60)
                    reasons[String(key), default: 0] += 1
                }
                worst = max(worst, Date().timeIntervalSince(s0))
            }
            let secs = Date().timeIntervalSince(t0)
            let rate = Double(ok) / Double(seeds)
            print("  \(difficulty.label.padding(toLength: 8, withPad: " ", startingAt: 0))"
                + "Erfolg \(pct(rate))  erster Versuch \(pct(Double(firstTry) / Double(seeds)))"
                + "  ø Wörter \(ok > 0 ? words / ok : 0)"
                + "  ø Kurzfragen \(ok > 0 ? shortClues / ok : 0)"
                + "  ø Knoten \(ok > 0 ? nodes / ok : 0)"
                + "  max \(fmt(worst, 2)) s  gesamt \(fmt(secs, 1)) s")
            for (r, n) in reasons.sorted(by: { $0.value > $1.value }).prefix(2) {
                print("      \(n)× \(r)")
            }
        }
    }
}

// MARK: - diag

func cmdDiag(_ args: Args) {
    let ctx = makeContext(args)
    let diffName = args.string("difficulty", "mittel")
    guard let difficulty = Difficulty(rawValue: diffName) else { die("Stufe? \(diffName)") }
    let variantName = args.string("variant", "classic")
    guard let variant = PuzzleVariant(rawValue: variantName) else { die("Variante? \(variantName)") }
    let profile = DifficultyProfile.profile(variant, difficulty)
    let layout: any LayoutProvider = variant == .classic
        ? ClassicLayout(templates: ctx.templates) : ArrowLayout()
    var rng = SplitMix64(seed: args.uint64("seed", 1))
    let size = profile.sizes[rng.int(below: profile.sizes.count)]
    guard let topo = try? layout.makeTopology(size: size, profile: profile, rng: &rng) else {
        die("keine Topologie für \(size.label)")
    }
    let gen = Generator(layout: layout, index: ctx.index, clues: ctx.clues, widths: ctx.widths)
    let filters = gen.slotFilters(topology: topo, profile: profile)
    let engine = FillEngine(index: ctx.index, topology: topo, profile: profile, slotFilters: filters)

    print("\n\(variant.label) \(difficulty.label) \(size.label) · \(topo.slots.count) Slots · "
        + "Zipf >= \(fmt(profile.minZipf, 1)) · Tier \(profile.clueTiers.lowerBound)–"
        + "\(profile.clueTiers.upperBound) · Wortlänge \(profile.wordLength.lowerBound)–"
        + "\(profile.wordLength.upperBound)")
    for r in 0 ..< size.rows {
        print(String((0 ..< size.cols).map { c -> Character in
            switch topo.kinds[size.index(Cell(r, c))] {
            case .letter: "."
            case .block: "#"
            case .clue: "?"
            }
        }))
    }
    // Bei arrow entscheidet die besitzende Fragezelle über das Breitenbudget:
    // eine Zelle mit zwei Fragen halbiert es. Deshalb hier getrennt zählen.
    var budgets: [Int: Int] = [:]
    for f in filters { if let b = f.maxShortWidth { budgets[b, default: 0] += 1 } }
    if !budgets.isEmpty {
        print("\nSlots je Breitenbudget: "
            + budgets.sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }.joined(separator: " · "))
    }

    let diag = engine.diagnose().sorted { $0.candidates < $1.candidates }
    print("\nengste Slots:")
    for d in diag.prefix(12) {
        print("  Länge \(d.slot.length) \(d.slot.direction.label) bei "
            + "(\(d.slot.start.row),\(d.slot.start.col)) · \(d.candidates) Kandidaten "
            + "· \(d.crossings) Kreuzungen")
    }
    var byLength: [Int: (count: Int, minCands: Int)] = [:]
    for d in diag {
        let cur = byLength[d.slot.length] ?? (0, Int.max)
        byLength[d.slot.length] = (cur.count + 1, min(cur.minCands, d.candidates))
    }
    print("\nSlots und Vokabular pro Länge:")
    for len in byLength.keys.sorted() {
        let v = byLength[len]!
        print("  Länge \(len): \(v.count) Slots, kleinster Kandidatenpool \(v.minCands)")
    }
}

// MARK: - arrowdiag

func cmdArrowDiag(_ args: Args) {
    let diffName = args.string("difficulty", "leicht")
    guard let difficulty = Difficulty(rawValue: diffName) else { die("Stufe? \(diffName)") }
    let profile = DifficultyProfile.profile(.arrow, difficulty)
    let layout = ArrowLayout()
    var rng = SplitMix64(seed: args.uint64("seed", 1))
    let size = profile.sizes[0]
    let (kinds, score) = layout.bestEffortPlacement(size: size, profile: profile, rng: &rng)

    print("Schwedenrätsel \(difficulty.label) \(size.label)")
    print("Fragezellen \(fmt(profile.deadCellRatio.lowerBound, 2))–"
        + "\(fmt(profile.deadCellRatio.upperBound, 2)) · Kreuzung "
        + "\(fmt(profile.crossRatio.lowerBound, 2))–\(fmt(profile.crossRatio.upperBound, 2)) · "
        + "Wortlänge \(profile.wordLength.lowerBound)–\(profile.wordLength.upperBound) · "
        + "Knick <= \(pct(profile.maxBentArrowRatio)) · Doppel <= \(pct(profile.maxDoubleArrowRatio))")
    print("\nbeste Platzierung, Restverstoß \(fmt(score, 2)):")
    for r in 0 ..< size.rows {
        print(String((0 ..< size.cols).map { kinds[size.index(Cell(r, $0))] == .clue ? "?" : "." }))
    }
    var rng2 = SplitMix64(seed: args.uint64("seed", 1))
    let counts = layout.stageCounts(size: size, profile: profile, rng: &rng2)
    print("\nStufen über 24 Versuche: Platzierung gescheitert \(counts.placementFailed) · "
        + "keine Slots \(counts.noSlots) · Zuweisung gescheitert \(counts.assignmentFailed) · "
        + "Erfolg \(counts.success)")

    print("\nAufschlüsselung:")
    for (name, value) in ArrowLayout.violationBreakdown(size: size, kinds: kinds,
                                                        profile: profile) where value != 0 {
        print("  \(name): \(fmt(value, 1))")
    }
}

// MARK: - main

let argv = Array(CommandLine.arguments.dropFirst())
guard let sub = argv.first else {
    print("""
    puzzlegen <befehl>

      templates   Sucht gültige classic-Schwarzfeldmuster und schreibt sie nach
                  Resources/grids/classic/. Flags: --count --seed --out --root
      sweep       Robustheitstest über viele Seeds. Flags: --seeds --variant
      gen         Generiert ein Rätsel und zeigt es als ASCII.
                  Flags: --variant --difficulty --seed --catalog --clues
    """)
    exit(0)
}
let args = Args(Array(argv.dropFirst()))
switch sub {
case "templates": cmdTemplates(args)
case "gen": cmdGen(args)
case "diag": cmdDiag(args)
case "sweep": cmdSweep(args)
case "arrowdiag": cmdArrowDiag(args)
default: die("unbekannter Befehl: \(sub)")
}
