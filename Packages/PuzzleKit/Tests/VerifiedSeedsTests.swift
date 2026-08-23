import Testing
@testable import PuzzleKit

@Suite("Geprüfte Seeds")
struct VerifiedSeedsTests {
    private let sample = """
    kwseeds 1
    # Kommentar wird überlesen
    generator 1
    catalog 2
    classic leicht 1 4 9
    arrow experte 7
    """

    @Test func parsesHeaderAndTable() throws {
        let s = try VerifiedSeeds.parse(sample)
        #expect(s.generatorVersion == 1)
        #expect(s.catalogVersion == 2)
        #expect(s.seeds(.classic, .leicht) == [1, 4, 9])
        #expect(s.seeds(.arrow, .experte) == [7])
        #expect(s.seeds(.arrow, .leicht).isEmpty)
        #expect(s.count == 4)
    }

    @Test func roundTripsThroughText() throws {
        let s = try VerifiedSeeds.parse(sample)
        let again = try VerifiedSeeds.parse(s.serialized())
        #expect(again == s)
    }

    @Test func incompleteListIsDetected() throws {
        // Eine halbe Zusage ist schlimmer als keine: fehlt eine Kombination,
        // darf die Liste nicht als vollständig gelten.
        #expect(try VerifiedSeeds.parse(sample).isComplete == false)
    }

    @Test func rejectsUnsupportedFormatAndGarbage() throws {
        #expect(throws: VerifiedSeeds.ParseError.unsupportedFormat(99)) {
            try VerifiedSeeds.parse("kwseeds 99\ngenerator 1\ncatalog 2")
        }
        #expect(throws: VerifiedSeeds.ParseError.missingHeader) {
            try VerifiedSeeds.parse("generator 1\ncatalog 2")
        }
        #expect(throws: VerifiedSeeds.ParseError.missingVersions) {
            try VerifiedSeeds.parse("kwseeds 1\ncatalog 2")
        }
        // Eine unparsbare Zahl verwirft die Datei, statt still einen Teil zu laden.
        #expect(throws: VerifiedSeeds.ParseError.badNumber("zwölf")) {
            try VerifiedSeeds.parse("kwseeds 1\ngenerator 1\ncatalog 2\nclassic leicht 1 zwölf")
        }
        #expect(throws: VerifiedSeeds.ParseError.unknownDifficulty("mittelschwer")) {
            try VerifiedSeeds.parse("kwseeds 1\ngenerator 1\ncatalog 2\nclassic mittelschwer 1")
        }
    }

    @Test func unknownKeyLinesAreSkipped() throws {
        // Eine spätere Erweiterung darf alte Leser nicht zerbrechen.
        let s = try VerifiedSeeds.parse("""
        kwseeds 1
        generator 1
        catalog 2
        zukunft irgendwas 1 2 3
        classic leicht 5
        """)
        #expect(s.seeds(.classic, .leicht) == [5])
    }

    @Test func dailySeedIsStableAndFromTheList() throws {
        let s = try VerifiedSeeds.parse(sample)
        let a = try #require(s.dailySeed(isoDate: "2026-08-23", variant: .classic,
                                         difficulty: .leicht))
        let b = try #require(s.dailySeed(isoDate: "2026-08-23", variant: .classic,
                                         difficulty: .leicht))
        #expect(a == b)                                  // dasselbe Datum, dasselbe Rätsel
        #expect([1, 4, 9].contains(a))                   // und immer erzeugbar
        // Fehlt die Kombination, gibt es keinen Seed statt einen erfundenen.
        #expect(s.dailySeed(isoDate: "2026-08-23", variant: .arrow, difficulty: .leicht) == nil)
    }

    @Test func differentDatesSpreadOverTheList() throws {
        let s = try VerifiedSeeds.parse(sample)
        var seen: Set<UInt64> = []
        for day in 1 ... 28 {
            let iso = "2026-09-\(day < 10 ? "0" : "")\(day)"
            if let v = s.dailySeed(isoDate: iso, variant: .classic, difficulty: .leicht) {
                seen.insert(v)
            }
        }
        // Über einen Monat müssen mehrere verschiedene Rätsel vorkommen, sonst
        // wäre der Index-Hash unbrauchbar.
        #expect(seen.count >= 2)
    }

    @Test func freePlayPickWrapsAround() throws {
        let s = try VerifiedSeeds.parse(sample)
        // Beliebiger Wert von außen, immer ein erzeugbarer Seed.
        for pick in [UInt64(0), 1, 2, 3, 99, .max] {
            let v = try #require(s.seed(variant: .classic, difficulty: .leicht, pick: pick))
            #expect([1, 4, 9].contains(v))
        }
    }
}
