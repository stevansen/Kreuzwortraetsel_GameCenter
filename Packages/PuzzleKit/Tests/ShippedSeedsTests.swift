import Testing
import Foundation
@testable import PuzzleKit

/// Prüft die **ausgelieferte** Seed-Liste, nicht eine gebaute.
///
/// Genau wie bei den Templates ist der Inhalt von `Resources/` das Versprechen.
/// Eine Liste, die nicht parst oder eine Kombination auslässt, lässt die App
/// still auf blindes Seed-Wählen zurückfallen — und das wäre erst im Feld zu
/// merken, an den Tagen ohne Rätsel.
@Suite("Ausgelieferte Seeds")
struct ShippedSeedsTests {
    static var seedsFile: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/seeds.txt")
    }

    static var text: String? {
        try? String(contentsOf: seedsFile, encoding: .utf8)
    }

    @Test func fileExistsAndParses() throws {
        let text = try #require(Self.text, "Resources/seeds.txt fehlt — `puzzlegen verify`")
        _ = try VerifiedSeeds.parse(text)
    }

    @Test func everyCombinationHasSeeds() throws {
        let seeds = try VerifiedSeeds.parse(try #require(Self.text))
        for variant in PuzzleVariant.allCases {
            for difficulty in Difficulty.allCases {
                #expect(!seeds.seeds(variant, difficulty).isEmpty,
                        "keine geprüften Seeds für \(variant.rawValue)/\(difficulty.rawValue)")
            }
        }
        #expect(seeds.isComplete)
    }

    @Test func seedsAreUniquePerCombination() throws {
        let seeds = try VerifiedSeeds.parse(try #require(Self.text))
        for variant in PuzzleVariant.allCases {
            for difficulty in Difficulty.allCases {
                let list = seeds.seeds(variant, difficulty)
                #expect(Set(list).count == list.count,
                        "doppelte Seeds bei \(variant.rawValue)/\(difficulty.rawValue)")
            }
        }
    }

    @Test func generatorVersionMatchesTheCode() throws {
        let seeds = try VerifiedSeeds.parse(try #require(Self.text))
        // Wird `Generator.currentVersion` erhöht, ist die Liste ungültig und muss
        // neu erzeugt werden. Dieser Test sagt es beim Bauen statt im Feld.
        #expect(seeds.generatorVersion == Generator.currentVersion,
                "Seed-Liste gilt für Generator \(seeds.generatorVersion), der Code ist Version \(Generator.currentVersion)")
    }

    @Test func aMonthOfDailyPuzzlesIsCovered() throws {
        let seeds = try VerifiedSeeds.parse(try #require(Self.text))
        // Für jeden Tag eines Monats muss jede Kombination einen Seed liefern.
        for day in 1 ... 31 {
            let iso = "2026-10-\(day < 10 ? "0" : "")\(day)"
            for variant in PuzzleVariant.allCases {
                for difficulty in Difficulty.allCases {
                    #expect(seeds.dailySeed(isoDate: iso, variant: variant,
                                            difficulty: difficulty) != nil,
                            "kein Tagesrätsel am \(iso) für \(variant.rawValue)/\(difficulty.rawValue)")
                }
            }
        }
    }
}
