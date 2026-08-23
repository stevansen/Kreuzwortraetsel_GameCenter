import SwiftUI
import AppKit
import PuzzleKit
import ClueCatalog
import KreuzwortUI

// uishot — rendert Spielansichten headless in PNGs.
//
// Ein Build beweist, dass etwas kompiliert, nicht dass es aussieht. `ImageRenderer`
// rastert eine SwiftUI-Ansicht ohne Fenster, ohne Simulator und deterministisch —
// damit lässt sich eine Oberfläche prüfen, und dieselbe Mechanik trägt später die
// Snapshot-Tests (hell/dunkel, kleinster und größter Dynamic Type).

struct Args {
    var flags: [String: String] = [:]
    init(_ argv: [String]) {
        var i = 0
        while i < argv.count {
            let a = argv[i]
            if a.hasPrefix("--") {
                let k = String(a.dropFirst(2))
                if i + 1 < argv.count, !argv[i + 1].hasPrefix("--") { flags[k] = argv[i + 1]; i += 2 }
                else { flags[k] = "1"; i += 1 }
            } else { i += 1 }
        }
    }
    func str(_ k: String, _ d: String) -> String { flags[k] ?? d }
    func int(_ k: String, _ d: Int) -> Int { flags[k].flatMap(Int.init) ?? d }
    func uint64(_ k: String, _ d: UInt64) -> UInt64 { flags[k].flatMap(UInt64.init) ?? d }
    func has(_ k: String) -> Bool { flags[k] != nil }
}

func die(_ m: String) -> Never {
    FileHandle.standardError.write(Data(("fehler: " + m + "\n").utf8))
    exit(1)
}

@MainActor
func render(_ view: some View, size: CGSize, scheme: ColorScheme, to path: String) throws {
    let renderer = ImageRenderer(content:
        view.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
            .background(scheme == .dark ? Color.black : Color.white))
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else { die("Rendern fehlgeschlagen") }
    try png.write(to: URL(fileURLWithPath: path))
}

@MainActor
func run() throws {
    let args = Args(Array(CommandLine.arguments.dropFirst()))
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let outDir = args.str("out", "build/shots")
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

    let reader = try CatalogReader(path: root.appendingPathComponent("Resources/catalog.sqlite").path)
    let index = PatternIndex(lexicon: try reader.loadLexicon())
    var widths = GlyphWidthTable.bootstrap
    if let d = try? Data(contentsOf: root.appendingPathComponent("Resources/glyphwidths.json")),
       let t = try? JSONDecoder().decode(GlyphWidthTable.self, from: d) { widths = t }
    let clues = CatalogClueSource(reader: reader, widths: widths)
    var templates: [GridTemplate] = []
    let gridDir = root.appendingPathComponent("Resources/grids/classic")
    for name in (try? FileManager.default.contentsOfDirectory(atPath: gridDir.path)) ?? []
    where name.hasSuffix(".json") {
        if let d = try? Data(contentsOf: gridDir.appendingPathComponent(name)),
           let set = try? JSONDecoder().decode(TemplateSet.self, from: d) {
            templates += set.templates
        }
    }

    let variantName = args.str("variant", "classic")
    guard let variant = PuzzleVariant(rawValue: variantName) else { die("Variante? \(variantName)") }
    let diffName = args.str("difficulty", "mittel")
    guard let difficulty = Difficulty(rawValue: diffName) else { die("Stufe? \(diffName)") }

    let layout: any LayoutProvider = variant == .classic
        ? ClassicLayout(templates: templates) : ArrowLayout()
    let generator = Generator(layout: layout, index: index, clues: clues, widths: widths)
    let puzzle = try generator.generate(seed: args.uint64("seed", 1),
                                        difficulty: difficulty).puzzle
    print("gerendert: \(puzzle.variant.label) \(puzzle.difficulty.label) "
        + "\(puzzle.size.label), \(puzzle.entries.count) Wörter")

    // Drei Flächen, damit der Unterschied sichtbar ist: Schreibtisch mit
    // Seitenspalte, Handheld mit Leiste, Wohnzimmer ohne Fragen in den Zellen.
    let surfaces: [(String, SurfaceCapabilities, CGSize)] = [
        ("desktop", .desktop, CGSize(width: 1000, height: 680)),
        ("touch", .touch, CGSize(width: 420, height: 780)),
        ("tv", .livingRoom, CGSize(width: 1000, height: 620)),
    ]
    let stem = "\(variant.rawValue)-\(difficulty.rawValue)"

    for (name, caps, size) in surfaces {
        let session = PuzzleSession(puzzle: puzzle)
        if args.has("filled") { session.fillWithSolution(except: args.int("filled", 3)) }
        let screen = PuzzleScreen(session: session, capabilities: caps)
        for scheme in [ColorScheme.light, .dark] {
            let suffix = scheme == .dark ? "dark" : "light"
            let path = "\(outDir)/\(stem)-\(name)-\(suffix).png"
            try render(screen, size: size, scheme: scheme, to: path)
            print("  \(path)")
        }
    }

    // Die Fragenliste getrennt: in der zusammengesetzten Ansicht steckt sie in
    // einer Scroll-Hülle, und die rendert headless nicht.
    let listSession = PuzzleSession(puzzle: puzzle)
    try render(ClueListContent(session: listSession, onSelect: { _ in })
                .frame(width: 340, alignment: .leading),
               size: CGSize(width: 340, height: 900), scheme: .light,
               to: "\(outDir)/\(stem)-cluelist.png")
    print("  \(outDir)/\(stem)-cluelist.png")

    // Abschlussbildschirm getrennt: er überlagert das Gitter und wäre sonst
    // nur halb zu sehen.
    let solved = PuzzleSession(puzzle: puzzle)
    solved.fillWithSolution()
    try render(CompletionView(session: solved, onNext: {}),
               size: CGSize(width: 460, height: 560), scheme: .light,
               to: "\(outDir)/\(stem)-completion.png")
    print("  \(outDir)/\(stem)-completion.png")
}

try await MainActor.run { try run() }
