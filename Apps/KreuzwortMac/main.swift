import SwiftUI
import PuzzleKit
import ClueCatalog
import KreuzwortUI

// macOS-Host für die geteilte Oberfläche.
//
// Hier — und nur hier — darf nach der Plattform gefragt werden. `KreuzwortUI`
// bleibt frei von `#if os(...)`; ein Test scannt das Verzeichnis darauf.

@MainActor
final class PuzzleLoader {
    private var index: PatternIndex?
    private var clues: CatalogClueSource?
    private var templates: [GridTemplate] = []
    private var widths: GlyphWidthTable = .bootstrap

    /// Aktuelle Auswahl. Vor der App-Oberfläche gibt es noch keinen Startbildschirm
    /// (M5 baut zuerst die Spielansicht), deshalb hier als schlichter Zustand.
    var variant: PuzzleVariant = .classic
    var difficulty: Difficulty = .mittel
    private var seed: UInt64 = 1

    func prepare(root: URL) throws {
        let catalog = root.appendingPathComponent("Resources/catalog.sqlite").path
        let reader = try CatalogReader(path: catalog)
        index = PatternIndex(lexicon: try reader.loadLexicon())
        clues = CatalogClueSource(reader: reader, widths: widths)
        if let d = try? Data(contentsOf: root
            .appendingPathComponent("Resources/glyphwidths.json")),
           let t = try? JSONDecoder().decode(GlyphWidthTable.self, from: d) {
            widths = t
        }
        let dir = root.appendingPathComponent("Resources/grids/classic")
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] {
            guard name.hasSuffix(".json"),
                  let d = try? Data(contentsOf: dir.appendingPathComponent(name)),
                  let set = try? JSONDecoder().decode(TemplateSet.self, from: d) else { continue }
            templates += set.templates
        }
    }

    func nextPuzzle() throws -> Puzzle {
        guard let index, let clues else { throw LoaderError.notPrepared }
        let layout: any LayoutProvider = variant == .classic
            ? ClassicLayout(templates: templates) : ArrowLayout()
        let generator = Generator(layout: layout, index: index, clues: clues, widths: widths)
        defer { seed += 1 }
        return try generator.generate(seed: seed, difficulty: difficulty).puzzle
    }

    enum LoaderError: Error { case notPrepared }
}

struct RootView: View {
    let loader: PuzzleLoader
    @State private var session: PuzzleSession?
    @State private var error: String?

    /// Auf dem Mac: Zeiger vorhanden, Tastatur zuerst, kein Zoom nötig.
    private let capabilities = SurfaceCapabilities.desktop

    var body: some View {
        Group {
            if let session {
                PuzzleScreen(session: session, capabilities: capabilities,
                             onNextPuzzle: load)
                .id(session.puzzle.id)
            } else if let error {
                VStack(spacing: 10) {
                    Text("Konnte kein Rätsel erzeugen").font(.headline)
                    Text(error).font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
            } else {
                ProgressView("Rätsel wird erzeugt …").padding(40)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .task { load() }
        .toolbar {
            Picker("Variante", selection: Binding(
                get: { loader.variant },
                set: { loader.variant = $0; load() })) {
                ForEach(PuzzleVariant.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            Picker("Stufe", selection: Binding(
                get: { loader.difficulty },
                set: { loader.difficulty = $0; load() })) {
                ForEach(Difficulty.allCases, id: \.self) { Text($0.label).tag($0) }
            }
        }
    }

    private func load() {
        session = nil
        error = nil
        Task { @MainActor in
            do { session = PuzzleSession(puzzle: try loader.nextPuzzle()) }
            catch { self.error = "\(error)" }
        }
    }
}

@main
struct KreuzwortMacApp: App {
    @State private var loader = PuzzleLoader()
    @State private var setupError: String?

    init() {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        do { try loader.prepare(root: root) }
        catch { setupError = "Katalog nicht gefunden (\(error)). "
            + "Die App aus dem Projektverzeichnis starten." }
    }

    var body: some Scene {
        WindowGroup("Kreuzwort") {
            if let setupError {
                Text(setupError).padding(40).frame(minWidth: 520)
            } else {
                RootView(loader: loader)
            }
        }
    }
}
