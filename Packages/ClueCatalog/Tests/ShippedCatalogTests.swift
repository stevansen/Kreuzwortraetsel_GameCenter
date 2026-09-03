import Testing
import Foundation
import PuzzleKit
@testable import ClueCatalog

/// Prüft den **ausgelieferten** Katalog gegen die ausgelieferte Seed-Liste.
///
/// Diese Verbindung war die Lücke: `catalogVersion` war eine von Hand gepflegte
/// Zahl, und wer den Inhalt änderte ohne sie zu erhöhen, machte die geprüften
/// Seeds still ungültig — Spielstände zeigten auf ein anderes Gitter, geteilte
/// Links öffneten etwas anderes. Jetzt ist die Zahl ein Abdruck des Inhalts, und
/// dieser Test stellt sicher, dass beide Dateien zueinander passen.
@Suite("Ausgelieferter Katalog")
struct ShippedCatalogTests {
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    static var catalogPath: String {
        repoRoot.appendingPathComponent("Resources/catalog.sqlite").path
    }

    static var seedsText: String? {
        try? String(contentsOf: repoRoot.appendingPathComponent("Resources/seeds.txt"),
                    encoding: .utf8)
    }

    /// Der Katalog ist ein generiertes 43-MB-Artefakt und liegt nicht im Git.
    /// Fehlt er, ist das kein Testfehler — aber dann darf auch nichts geprüft
    /// werden, was ihn braucht.
    static var hasCatalog: Bool { FileManager.default.fileExists(atPath: catalogPath) }

    @Test func seedListMatchesTheCatalogue() throws {
        try #require(Self.hasCatalog, "Resources/catalog.sqlite fehlt — `catalogbuild build`")
        let reader = try CatalogReader(path: Self.catalogPath)
        let seeds = try VerifiedSeeds.parse(try #require(Self.seedsText))
        #expect(seeds.catalogVersion == reader.catalogVersion,
                "Seed-Liste gilt für Katalog \(seeds.catalogVersion), ausgeliefert ist \(reader.catalogVersion) — `puzzlegen verify` erneut laufen lassen")
    }

    @Test func schemaVersionIsReadableByThisCode() throws {
        try #require(Self.hasCatalog)
        let reader = try CatalogReader(path: Self.catalogPath)
        #expect(reader.schemaVersion == CatalogSchema.version,
                "Katalog hat Schema \(reader.schemaVersion), dieser Leser erwartet \(CatalogSchema.version)")
    }

    @Test func fingerprintIsStableAndContentDependent() throws {
        let a = CatalogAnswer(surface: "EIS", zipf: 4.0, flags: [], topics: [],
                              wordClass: "noun", sourceRef: "t:1")
        let b = CatalogAnswer(surface: "TAL", zipf: 3.5, flags: [], topics: [],
                              wordClass: "noun", sourceRef: "t:2")
        let clues: [String: [CatalogClue]] = [
            "EIS": [CatalogClue(text: "Gefrorenes Wasser", shortText: "Gefrorenes",
                                shortWidth: 100, kind: .definition, tier: 1,
                                locale: "de", license: "x", sourceRef: "t:1")],
            "TAL": [CatalogClue(text: "Tiefergelegenes Gelände", shortText: "Gelände",
                                shortWidth: 90, kind: .definition, tier: 1,
                                locale: "de", license: "x", sourceRef: "t:2")],
        ]
        let first = CatalogSchema.contentFingerprint(answers: [a, b], cluesByAnswer: clues)

        // Gleicher Inhalt, andere Reihenfolge: derselbe Abdruck. Sonst wäre er
        // von der Aufzählungsreihenfolge abhängig und damit unbrauchbar.
        #expect(CatalogSchema.contentFingerprint(answers: [b, a],
                                                 cluesByAnswer: clues) == first)

        // Eine geänderte Frage ändert den Abdruck — genau der Fall, der vorher
        // still durchging.
        var changed = clues
        changed["EIS"] = [CatalogClue(text: "Gefrorenes Wasser QS Bedeutungen",
                                      shortText: "Gefrorenes", shortWidth: 100,
                                      kind: .definition, tier: 1, locale: "de",
                                      license: "x", sourceRef: "t:1")]
        #expect(CatalogSchema.contentFingerprint(answers: [a, b],
                                                 cluesByAnswer: changed) != first)

        // Und eine geänderte Häufigkeit ebenso: sie entscheidet mit, welche
        // Wörter eine Stufe überhaupt sieht.
        var rarer = a
        rarer.zipf = 2.0
        #expect(CatalogSchema.contentFingerprint(answers: [rarer, b],
                                                 cluesByAnswer: clues) != first)

        #expect(first > 0, "Abdruck muss positiv sein, er wandert in eine PuzzleID")
    }
}
