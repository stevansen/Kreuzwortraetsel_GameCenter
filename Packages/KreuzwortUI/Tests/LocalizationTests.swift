import Testing
import Foundation
import PuzzleKit
@testable import KreuzwortUI

/// Bewacht die drei Sprachen gegeneinander.
///
/// Die häufigste Lokalisierungsschuld ist ein Schlüssel, den nur eine Sprache
/// kennt: die App zeigt dann in einer Sprache den rohen Schlüssel an, und das
/// fällt erst einem Nutzer auf. Ein Test sieht es sofort.
@Suite("Lokalisierung")
struct LocalizationTests {
    static let languages = ["de", "en", "it"]

    /// Schlüssel-Wert-Paare einer Sprache, direkt aus der `.strings`-Datei.
    static func entries(_ language: String) throws -> [String: String] {
        let url = try #require(Bundle.module.url(forResource: "Localizable",
                                                 withExtension: "strings",
                                                 subdirectory: nil,
                                                 localization: language),
                               "keine Localizable.strings für \(language)")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: String])
    }

    @Test func allLanguagesArePresent() throws {
        for language in Self.languages {
            let table = try Self.entries(language)
            #expect(!table.isEmpty, Comment(rawValue: "\(language) ist leer"))
        }
    }

    @Test func noLanguageIsMissingAKey() throws {
        var tables: [String: [String: String]] = [:]
        for language in Self.languages { tables[language] = try Self.entries(language) }
        let allKeys = Set(tables.values.flatMap(\.keys))

        for language in Self.languages {
            let missing = allKeys.subtracting(tables[language]!.keys).sorted()
            #expect(missing.isEmpty, Comment(rawValue:
                "\(language) fehlen \(missing.count) Schlüssel: \(missing.prefix(5))"))
        }
    }

    @Test func noLanguageHasAnEmptyValue() throws {
        for language in Self.languages {
            let empty = try Self.entries(language)
                .filter { $0.value.trimmingCharacters(in: .whitespaces).isEmpty }
                .keys.sorted()
            #expect(empty.isEmpty, Comment(rawValue: "\(language): leere Werte \(empty)"))
        }
    }

    @Test func formatPlaceholdersMatchAcrossLanguages() throws {
        // Eine Übersetzung mit anderer Platzhalterzahl stürzt zur Laufzeit ab
        // oder zeigt Müll — und zwar nur in dieser einen Sprache.
        func placeholders(_ s: String) -> [String] {
            var out: [String] = []
            var iterator = s.makeIterator()
            var current: Character? = iterator.next()
            while let c = current {
                if c == "%" {
                    var spec = "%"
                    while let n = iterator.next() {
                        spec.append(n)
                        if "@dflsu%".contains(n) { break }
                    }
                    if spec != "%%" { out.append(spec) }
                    current = iterator.next()
                } else {
                    current = iterator.next()
                }
            }
            return out
        }

        let reference = try Self.entries("de")
        for language in Self.languages.filter({ $0 != "de" }) {
            let table = try Self.entries(language)
            for (key, germanValue) in reference {
                guard let translated = table[key] else { continue }
                #expect(placeholders(germanValue) == placeholders(translated),
                        Comment(rawValue: "\(language) »\(key)«: "
                            + "\(placeholders(germanValue)) gegen \(placeholders(translated))"))
            }
        }
    }

    @Test func coreTypesResolveToText() {
        // Kein Schlüssel darf ungelöst durchfallen — dann stünde in der App
        // wörtlich »variant.arrow«.
        for variant in PuzzleVariant.allCases {
            #expect(!variant.displayName.hasPrefix("variant."), Comment(rawValue:
                "\(variant.rawValue) unaufgelöst: \(variant.displayName)"))
        }
        for difficulty in Difficulty.allCases {
            #expect(!difficulty.displayName.hasPrefix("difficulty."))
        }
        for direction in Direction.allCases {
            #expect(!direction.displayName.hasPrefix("direction."))
        }
    }

    @Test func everyScoreLineKindHasAName() {
        let kinds: [ScoreBreakdown.Line.Kind] = [
            .base, .size, .time, .timeWithoutBonus, .clean, .streak, .daily, .hints, .total,
        ]
        for kind in kinds {
            #expect(!kind.displayName.hasPrefix("score."), Comment(rawValue:
                "unaufgelöst: \(kind.displayName)"))
        }
        #expect(ScoreBreakdown.Line.Kind.total.isTotal)
        #expect(!ScoreBreakdown.Line.Kind.base.isTotal)
    }

    @Test func puzzleKitKeepsNoDisplayStrings() {
        // Der Kern liefert Strukturen, die Oberfläche die Sprache. Die Roh-Labels
        // heißen `debugLabel` und sind ausdrücklich nur für CLI und Debugging.
        #expect(PuzzleVariant.arrow.debugLabel == "Schwedenrätsel")
        #expect(PuzzleVariant.arrow.displayName != PuzzleVariant.arrow.debugLabel
            || Locale.current.language.languageCode?.identifier == "de")
    }
}
