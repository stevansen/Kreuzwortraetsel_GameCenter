/// Deterministische Textbreitenmessung in **1/1000 em**.
///
/// Warum eine eingecheckte Tabelle statt CoreText: die Breite eines Kurzclues
/// entscheidet, ob er in eine Fragezelle passt — sie ist damit ein
/// Generator-Constraint. Würde sie zur Laufzeit gemessen, könnten iOS und macOS
/// aus demselben Seed unterschiedliche Rätsel erzeugen, sobald sich Fontmetriken
/// zwischen OS-Versionen um ein Hundertstel verschieben.
///
/// Die Tabelle wird einmal per `scripts/gen-glyphwidths.swift` gegen die
/// ausgelieferte Schrift erzeugt und eingecheckt. `GlyphWidthDriftTests`
/// vergleicht sie mit dem echten Rendering.
public struct GlyphWidthTable: Sendable, Codable {
    public let fontName: String
    public let unitsPerEm: Int
    public let widths: [String: Int]
    public let fallbackWidth: Int

    public init(fontName: String, unitsPerEm: Int, widths: [String: Int], fallbackWidth: Int) {
        self.fontName = fontName
        self.unitsPerEm = unitsPerEm
        self.widths = widths
        self.fallbackWidth = fallbackWidth
    }

    /// Breite in 1/1000 em. Unbekannte Zeichen zählen mit `fallbackWidth` —
    /// bewusst großzügig, damit die Schätzung nie zu klein ausfällt.
    public func width(of s: String) -> Int {
        var total = 0
        for ch in s { total += widths[String(ch)] ?? fallbackWidth }
        return total
    }

    /// Notfalltabelle für Tests und Bootstrap: grobe Helvetica-Klassen.
    /// Für die Auslieferung immer die generierte Tabelle verwenden.
    public static let bootstrap: GlyphWidthTable = {
        var w: [String: Int] = [:]
        func put(_ chars: String, _ v: Int) { for c in chars { w[String(c)] = v } }
        put("iljI.,:;'|!", 280)
        put("ftr()[]-/\\ ", 360)
        put("abcdeghknopqsuvxyzäöü", 556)
        put("mw", 833)
        put("ABCDEFGHJKLNOPQRSTUVXYZÄÖÜ", 667)
        put("MW", 944)
        put("0123456789", 556)
        return GlyphWidthTable(fontName: "bootstrap-helvetica-like",
                               unitsPerEm: 1000, widths: w, fallbackWidth: 600)
    }()
}
