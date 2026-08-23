import Testing
import Foundation

/// Drei Quellcode-Scans, die die tragenden Architekturentscheidungen bewachen.
///
/// Ein Kommentar in einer Datei hält niemanden auf; ein fehlschlagender Test
/// schon. Diese drei sind die einzigen Tests im Projekt, die Quelltext lesen
/// statt Verhalten zu prüfen — genau deshalb sind sie hier zusammen und
/// ausführlich begründet.
@Suite("Seam-Scans")
struct SeamScanTests {
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)          // …/Packages/PuzzleKit/Tests/SeamScanTests.swift
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // PuzzleKit
            .deletingLastPathComponent()          // Packages
            .deletingLastPathComponent()          // Repo-Wurzel
    }

    static func swiftFiles(under relative: String) -> [(URL, String)] {
        let base = repoRoot.appendingPathComponent(relative)
        guard let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)
        else { return [] }
        var out: [(URL, String)] = []
        for case let url as URL in e where url.pathExtension == "swift" {
            if url.path.contains("/Tests/") { continue }
            if let s = try? String(contentsOf: url, encoding: .utf8) { out.append((url, s)) }
        }
        return out
    }

    /// Zeilen ohne Kommentare und ohne String-Literale — sonst schlagen die
    /// Scans an den Doku-Kommentaren an, die genau diese Regeln erklären.
    static func codeLines(_ source: String) -> [(Int, String)] {
        var out: [(Int, String)] = []
        var inBlockComment = false
        for (i, raw) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            var line = String(raw)
            if inBlockComment {
                if let end = line.range(of: "*/") { line = String(line[end.upperBound...]); inBlockComment = false }
                else { continue }
            }
            if let start = line.range(of: "/*") {
                if let end = line.range(of: "*/"), end.lowerBound > start.upperBound {
                    line = String(line[..<start.lowerBound]) + String(line[end.upperBound...])
                } else {
                    line = String(line[..<start.lowerBound]); inBlockComment = true
                }
            }
            if let c = line.range(of: "//") { line = String(line[..<c.lowerBound]) }
            // String-Literale entfernen (naiv, für diesen Zweck ausreichend).
            var stripped = "", inString = false, prev: Character = " "
            for ch in line {
                if ch == "\"" && prev != "\\" { inString.toggle(); prev = ch; continue }
                if !inString { stripped.append(ch) }
                prev = ch
            }
            out.append((i + 1, stripped))
        }
        return out
    }

    // MARK: - 1. Determinismus

    @Test("Kein nicht-seedbarer Zufall und keine Uhr im Generatorpfad")
    func noNondeterminismInPuzzleKit() {
        // `Date()` verboten: eine Uhr im Generator macht dasselbe Seed
        // datumsabhängig. `Hasher`/`hashValue` verboten: pro Prozess zufällig
        // geseedet, also als stabile ID unbrauchbar.
        let forbidden = ["SystemRandomNumberGenerator", "arc4random", "Date()",
                         "UUID(", ".random(", "hashValue", "Hasher("]
        var hits: [String] = []
        for (url, src) in Self.swiftFiles(under: "Packages/PuzzleKit/Sources") {
            for (line, text) in Self.codeLines(src) {
                for f in forbidden where text.contains(f) {
                    hits.append("\(url.lastPathComponent):\(line) → \(f)")
                }
            }
        }
        #expect(hits.isEmpty, Comment(rawValue: "Determinismus verletzt:\n" + hits.joined(separator: "\n")))
    }

    @Test("PuzzleKit importiert kein Foundation und kein Apple-Framework")
    func puzzleKitStaysPortable() {
        let forbidden = ["import Foundation", "import UIKit", "import AppKit",
                         "import SwiftUI", "import GameKit", "import CloudKit",
                         "import CoreText", "import CryptoKit"]
        var hits: [String] = []
        for (url, src) in Self.swiftFiles(under: "Packages/PuzzleKit/Sources") {
            for (line, text) in Self.codeLines(src) {
                for f in forbidden where text.contains(f) {
                    hits.append("\(url.lastPathComponent):\(line) → \(f)")
                }
            }
        }
        #expect(hits.isEmpty, Comment(rawValue: "PuzzleKit soll portabel bleiben:\n" + hits.joined(separator: "\n")))
    }

    // MARK: - 2. Varianten-Seam

    @Test("Kein Variantenvergleich außerhalb von Layout/")
    func variantSeamHolds() {
        var hits: [String] = []
        for (url, src) in Self.swiftFiles(under: "Packages/PuzzleKit/Sources") {
            if url.path.contains("/Layout/") { continue }
            // Die Deklarationsdatei darf ihre eigenen Fälle kennen (Anzeigename
            // je Variante). Verboten ist Logik, die *anderswo* nach der Variante
            // verzweigt — das gehört hinter den LayoutProvider.
            if url.lastPathComponent == "Variant.swift" { continue }
            for (line, text) in Self.codeLines(src) {
                let compact = text.replacingOccurrences(of: " ", with: "")
                if compact.contains("variant==") || compact.contains("variant!=")
                    || compact.contains("==.arrow") || compact.contains("==.classic") {
                    hits.append("\(url.lastPathComponent):\(line) → \(text.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(hits.isEmpty, Comment(rawValue:
            "Variantenunterscheidung gehört nach Layout/:\n" + hits.joined(separator: "\n")))
    }

    // MARK: - 3. Plattform-Seam

    @Test("Kein verhaltenswirksames #if os() in der geteilten UI")
    func platformSeamHolds() {
        // Reine Import-Verzweigungen sind erlaubt — Verhalten gehört über
        // SurfaceCapabilities, weil die Fähigkeiten auch innerhalb einer
        // Plattform variieren (iPad mit und ohne Tastatur).
        // Über `codeLines`, nicht über die Rohzeilen: dieser Scan hat sich sonst
        // an seiner eigenen Dokumentation gefangen — `SurfaceCapabilities`
        // erklärt im Kommentar, warum `#if os(tvOS)` die falsche Antwort ist.
        var hits: [String] = []
        for (url, src) in Self.swiftFiles(under: "Packages/KreuzwortUI") {
            let code = Self.codeLines(src)
            for (i, (line, text)) in code.enumerated() where text.contains("#if os(") {
                let window = code[(i + 1) ..< min(i + 4, code.count)]
                    .map(\.1).joined(separator: " ")
                let importOnly = window.contains("import") && !window.contains("func")
                if !importOnly { hits.append("\(url.lastPathComponent):\(line)") }
            }
        }
        #expect(hits.isEmpty, Comment(rawValue:
            "Plattformverhalten gehört über SurfaceCapabilities:\n" + hits.joined(separator: "\n")))
    }
}
