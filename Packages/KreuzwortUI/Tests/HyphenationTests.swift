import Testing
import Foundation
@testable import KreuzwortUI

@Suite("Worttrennung")
struct HyphenationTests {
    private let de = Locale(identifier: "de_DE")

    private func parts(_ s: String) -> [String] {
        s.split(separator: Hyphenation.soft).map(String.init)
    }

    @Test func longGermanWordsGetBreakPoints() throws {
        // Die Fälle aus dem gerenderten Rätsel: „Möbelstü ck" stand da, weil
        // SwiftUI ohne Trennstelle mitten im Wort brach.
        for word in ["Möbelstück", "Flüssigkeit", "Sprechweise", "Verbindungsglied"] {
            let out = Hyphenation.hyphenated(word, locale: de)
            #expect(out.contains(Hyphenation.soft), "keine Trennstelle in \(word)")
            // Jedes Bruchstück lang genug, „E-lefant" wäre korrekt und schlecht.
            for part in parts(out) {
                #expect(part.count >= Hyphenation.minimumFragment,
                        "zu kurzes Bruchstück in \(out)")
            }
        }
    }

    @Test func shortWordsStayWhole() throws {
        // Ein Trennstrich in „Stadt" wäre nur Unruhe.
        for word in ["Stadt", "Eis", "Ufer", "Abbau", "Sonne"] {
            #expect(!Hyphenation.hyphenated(word, locale: de).contains(Hyphenation.soft))
        }
    }

    @Test func textIsUnchangedApartFromSoftHyphens() throws {
        // Das weiche Trennzeichen ist die einzige erlaubte Änderung — sonst
        // stimmte die Frage nicht mehr mit dem Katalog überein.
        let source = "Tiefergelegenes Gelände zwischen Erhebungen"
        let out = Hyphenation.hyphenated(source, locale: de)
        #expect(out.filter { $0 != Hyphenation.soft } == source)
    }

    @Test func wordCountAndSpacesSurvive() throws {
        let source = "Abk. für Bundesautobahntankstelle"
        let out = Hyphenation.hyphenated(source, locale: de)
        #expect(out.split(separator: " ").count == 3)
        #expect(out.contains(Hyphenation.soft))
    }

    @Test func repeatedCallsAgree() throws {
        // Der Cache darf das Ergebnis nicht verändern.
        let source = "Gemeindeverwaltung"
        let first = Hyphenation.hyphenated(source, locale: de)
        #expect(Hyphenation.hyphenated(source, locale: de) == first)
    }

    @Test func localeWithoutDataLeavesTextAlone() throws {
        // Kein Absturz und keine erfundene Trennung, wenn Trenndaten fehlen.
        let out = Hyphenation.hyphenated("Möbelstück", locale: Locale(identifier: "xx_YY"))
        #expect(out.filter { $0 != Hyphenation.soft } == "Möbelstück")
    }
}
