// Erzeugt Resources/glyphwidths.json — die eingecheckte Breitentabelle.
//
// Läuft EINMAL und wird dann eingecheckt. Der Generator darf Breiten nie zur
// Laufzeit messen: CoreText-Metriken können zwischen OS-Versionen um
// Hundertstel abweichen, und weil die Kurzclue-Breite ein Füll-Constraint ist,
// würden iPhone und Mac aus demselben Seed unterschiedliche Rätsel bauen.
//
//   swift scripts/gen-glyphwidths.swift Resources/glyphwidths.json
//
// Schrift: Helvetica. Bewusst nicht die System-Schrift — deren Metriken sind
// nicht über OS-Versionen stabil, und genau darauf käme es hier an.
import Foundation
import CoreText

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/glyphwidths.json"
let fontName = "Helvetica"
let unitsPerEm = 1000
let size: CGFloat = 100   // 100 pt → Breite × 10 = 1/1000 em

let font = CTFontCreateWithName(fontName as CFString, size, nil)

var chars: [Character] = []
chars += Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
chars += Array("abcdefghijklmnopqrstuvwxyz")
chars += Array("0123456789")
chars += Array("ÄÖÜäöüß")
chars += Array(" .,;:!?-–/()[]'\u{2019}\"&%+*=<>@#§°")

var widths: [String: Int] = [:]
var missing: [String] = []
for ch in chars {
    let s = String(ch)
    var unichars = Array(s.utf16)
    var glyphs = [CGGlyph](repeating: 0, count: unichars.count)
    guard CTFontGetGlyphsForCharacters(font, &unichars, &glyphs, unichars.count) else {
        missing.append(s); continue
    }
    var advances = [CGSize](repeating: .zero, count: glyphs.count)
    CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, &advances, glyphs.count)
    let total = advances.reduce(0.0) { $0 + $1.width }
    widths[s] = Int((total / size * Double(unitsPerEm)).rounded())
}

// Fallback bewusst großzügig: eine unbekannte Glyphe darf die Schätzung nie zu
// KLEIN machen, sonst passt ein Clue am Ende doch nicht in die Zelle.
let fallback = (widths.values.max() ?? 1000)

struct Table: Encodable {
    let fontName: String
    let unitsPerEm: Int
    let widths: [String: Int]
    let fallbackWidth: Int
}
let enc = JSONEncoder()
enc.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try enc.encode(Table(fontName: fontName, unitsPerEm: unitsPerEm,
                                widths: widths, fallbackWidth: fallback))
try data.write(to: URL(fileURLWithPath: outPath))
print("\(widths.count) Glyphen → \(outPath) (Fallback \(fallback))")
if !missing.isEmpty { print("nicht gefunden: \(missing.joined())") }
// Ein paar Kontrollwerte, damit man sieht, dass gemessen und nicht gezählt wird.
for probe in ["MM", "ill", "Hauptst. Frankreichs", "Gemüsesorte"] {
    let w = probe.reduce(0) { $0 + (widths[String($1)] ?? fallback) }
    print("  \(probe.padding(toLength: 22, withPad: " ", startingAt: 0)) \(w) (1/1000 em)")
}
