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

/// Textgröße für den Durchlauf. `nil` heißt Standard.
///
/// Barrierefreiheit lässt sich nicht behaupten, sie muss zu sehen sein: mit
/// `--textsize accessibility3` rendert derselbe Bildschirm in der Größe, die ein
/// Nutzer mit eingeschränkter Sehkraft einstellt. Was dort abgeschnitten wird
/// oder überlappt, ist ein Fehler — und headless findet man ihn in Sekunden
/// statt am Gerät.
/// In `main.swift` darf eine Variable auf oberster Ebene keinen Global-Actor
/// tragen — deshalb ein Namensraum.
enum Shot {
    @MainActor static var textSize: DynamicTypeSize = .large
    // Kein Schalter für „Ohne Farbe unterscheiden": der Umgebungsschlüssel
    // `accessibilityDifferentiateWithoutColor` ist **nur lesbar**, SwiftUI
    // erlaubt kein Überschreiben, und `simctl ui` kennt die Einstellung
    // ebenfalls nicht (nur appearance, increase_contrast, content_size). Der
    // Zustand ist damit auf dieser Maschine nicht prüfbar — die Regel dafür
    // steht in GridView und ist eine einzeilige Bedingung.
}

@MainActor
func render(_ view: some View, size: CGSize, scheme: ColorScheme, to path: String) throws {
    let renderer = ImageRenderer(content:
        view.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, Shot.textSize)
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
    // Sprache erzwingen, damit sich alle drei Fassungen ansehen lassen.
    Loc.forcedLanguage = args.flags["lang"]
    if let name = args.flags["textsize"] {
        let sizes: [String: DynamicTypeSize] = [
            "large": .large, "xxxLarge": .xxxLarge,
            "accessibility1": .accessibility1, "accessibility2": .accessibility2,
            "accessibility3": .accessibility3, "accessibility4": .accessibility4,
            "accessibility5": .accessibility5,
        ]
        guard let size = sizes[name] else {
            die("Textgröße? \(name) — erlaubt: \(sizes.keys.sorted().joined(separator: ", "))")
        }
        Shot.textSize = size
    }
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
    print("gerendert: \(puzzle.variant.debugLabel) \(puzzle.difficulty.debugLabel) "
        + "\(puzzle.size.label), \(puzzle.entries.count) Wörter")

    // Drei Flächen, damit der Unterschied sichtbar ist: Schreibtisch mit
    // Seitenspalte, Handheld mit Leiste, Wohnzimmer ohne Fragen in den Zellen.
    let surfaces: [(String, SurfaceCapabilities, CGSize)] = [
        ("desktop", .desktop, CGSize(width: 1000, height: 680)),
        ("touch", .touch, CGSize(width: 420, height: 780)),
        ("tv", .livingRoom, CGSize(width: 1000, height: 620)),
    ]
    // Für Store-Bilder zählt die exakte Größe: Apple nimmt beim Mac nur
    // 1280x800, 1440x900, 2560x1600 oder 2880x1800. `--size 1280x800` rendert
    // genau das, statt es hinterher zuzuschneiden.
    let forcedSize: CGSize? = args.flags["size"].flatMap { text in
        let parts = text.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { die("Größe? \(text) — erwartet BxH, etwa 1280x800") }
        return CGSize(width: parts[0], height: parts[1])
    }
    let stem = "\(variant.rawValue)-\(difficulty.rawValue)"
        + (args.flags["lang"].map { "-\($0)" } ?? "")
        + (args.flags["textsize"].map { "-\($0)" } ?? "")
        + (args.flags["size"].map { "-\($0)" } ?? "")


    for (name, caps, defaultSize) in surfaces {
        let size = forcedSize ?? defaultSize
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
