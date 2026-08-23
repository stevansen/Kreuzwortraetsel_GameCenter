import Testing
import Foundation
@testable import PuzzleKit

/// Prüft die **eingecheckten** Templates, nicht frisch gesuchte. Die Suche kann
/// später gefixt werden — was ausgeliefert wird, ist der Inhalt von
/// `Resources/grids/classic/`, und genau der muss den Validator passieren.
@Suite("ClassicLayout")
struct ClassicLayoutTests {
    static var gridsDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/grids/classic")
    }

    static func loadAll() -> [(String, TemplateSet)] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: gridsDir.path) else { return [] }
        return names.filter { $0.hasSuffix(".json") }.sorted().compactMap { name in
            guard let d = try? Data(contentsOf: gridsDir.appendingPathComponent(name)),
                  let s = try? JSONDecoder().decode(TemplateSet.self, from: d) else { return nil }
            return (name, s)
        }
    }

    @Test func templatesExistForEveryClassicSize() {
        var needed: Set<String> = []
        for d in Difficulty.allCases {
            for s in DifficultyProfile.profile(.classic, d).sizes {
                needed.insert("\(s.cols)x\(s.rows).json")
            }
        }
        let present = Set(Self.loadAll().map(\.0))
        #expect(needed.subtracting(present).isEmpty,
                Comment(rawValue: "fehlende Templatedateien: \(needed.subtracting(present).sorted())"))
    }

    @Test func everyShippedTemplatePassesTheValidator() {
        var checked = 0
        for (name, set) in Self.loadAll() {
            #expect(!set.templates.isEmpty, Comment(rawValue: "\(name) ist leer"))
            for t in set.templates {
                #expect(t.isWellFormed, Comment(rawValue: "\(name): Zeilen inkonsistent"))
                let size = t.size
                // Das Profil finden, dessen Größenliste dieses Gitter enthält.
                guard let profile = Difficulty.allCases
                    .map({ DifficultyProfile.profile(.classic, $0) })
                    .first(where: { $0.sizes.contains(size) })
                else {
                    Issue.record("kein Profil für \(size.label)"); continue
                }
                let layout = ClassicLayout(templates: [t])
                let topo = ClassicLayout.topology(size: size, kinds: t.kinds, profile: profile)
                let issues = layout.validate(topology: topo, profile: profile)
                    .filter(\.isError)
                #expect(issues.isEmpty, Comment(rawValue:
                    "\(name) \(size.label):\n" + t.pretty + "\n"
                        + issues.map(\.description).joined(separator: "\n")))
                checked += 1
            }
        }
        // Pro Größe mindestens drei Muster, sonst sehen aufeinanderfolgende
        // Rätsel derselben Stufe gleich aus. Die Gesamtzahl ist absichtlich
        // keine Zusage: für 15×15 findet die Suche naturgemäß am wenigsten.
        for (name, set) in Self.loadAll() {
            #expect(set.templates.count >= 3,
                    Comment(rawValue: "\(name): nur \(set.templates.count) Muster"))
        }
        #expect(checked >= 40, Comment(rawValue: "nur \(checked) Templates geprüft"))
    }

    @Test func noShippedTemplateHasStackedFullSpanEntries() {
        // Der Fehler, an dem der erste Generatorlauf scheiterte: **gestapelte**
        // Wörter über die volle Gitterkante. Zwei davon übereinander zu füllen
        // gilt schon unter Handkonstrukteuren als das Schwerste; prozedural mit
        // wenigen tausend Kandidaten ist es aussichtslos.
        for (name, set) in Self.loadAll() {
            for t in set.templates {
                let size = t.size
                guard let profile = Difficulty.allCases
                    .map({ DifficultyProfile.profile(.classic, $0) })
                    .first(where: { $0.sizes.contains(size) }) else { continue }
                let runs = GridRuns.runs(size: size, kinds: t.kinds)
                let longest = runs.map(\.length).max() ?? 0
                #expect(longest <= profile.wordLength.upperBound,
                        Comment(rawValue: "\(name): längster Lauf \(longest) > "
                            + "\(profile.wordLength.upperBound)\n\(t.pretty)"))

                // Vollspannige Läufe je Zeile bzw. Spalte einsammeln …
                var fullRows = Set<Int>(), fullCols = Set<Int>()
                for r in runs {
                    if r.direction == .across, r.length == size.cols { fullRows.insert(r.start.row) }
                    if r.direction == .down, r.length == size.rows { fullCols.insert(r.start.col) }
                }
                // … und keine zwei benachbarten zulassen.
                for i in fullRows {
                    #expect(!fullRows.contains(i + 1), Comment(rawValue:
                        "\(name): vollspannige Zeilen \(i) und \(i + 1) gestapelt\n\(t.pretty)"))
                }
                for i in fullCols {
                    #expect(!fullCols.contains(i + 1), Comment(rawValue:
                        "\(name): vollspannige Spalten \(i) und \(i + 1) gestapelt\n\(t.pretty)"))
                }
            }
        }
    }

    @Test func templatePickIsDeterministicForASeed() throws {
        let sets = Self.loadAll()
        let eleven = try #require(sets.first { $0.0 == "11x11.json" }?.1)
        let layout = ClassicLayout(templates: eleven.templates)
        let profile = DifficultyProfile.profile(.classic, .mittel)
        var a = SplitMix64(seed: 12345)
        var b = SplitMix64(seed: 12345)
        let x = try layout.makeTopology(size: GridSize(square: 11), profile: profile, rng: &a)
        let y = try layout.makeTopology(size: GridSize(square: 11), profile: profile, rng: &b)
        #expect(x.kinds == y.kinds)
        #expect(x.slots == y.slots)
        #expect(x.slots.count > 20)
    }

    @Test func searchRejectsImpossibleConstraints() {
        // 92 % Schwarzfelder und gleichzeitig ein zusammenhängendes Gitter mit
        // Wörtern ab Länge 3 gibt es in einem 5×5 nicht. (Mit den gelockerten
        // Regeln — Läufe der Länge 1 erlaubt — sind 60 % übrigens erreichbar;
        // die frühere Fassung dieses Tests war deshalb überholt.)
        let found = TemplateSearch.search(size: GridSize(square: 5), ratio: 0.90 ... 0.95,
                                          minWord: 3, maxWord: 5,
                                          crossRatio: 0.5 ... 1.0, count: 3, seed: 1,
                                          attemptsPerTemplate: 20)
        #expect(found.isEmpty)
    }
}
