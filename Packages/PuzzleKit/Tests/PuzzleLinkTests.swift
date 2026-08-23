import Testing
@testable import PuzzleKit

@Suite("Rätsel-Links")
struct PuzzleLinkTests {
    @Test func roundTripThroughBothForms() throws {
        let link = PuzzleLink(seed: 4_711, variant: .arrow, difficulty: .schwer)
        #expect(link.customURLString == "kreuzwort://p/arrow/schwer/4711")
        #expect(link.universalURLString == "https://kreuzwort.app/p/arrow/schwer/4711")
        for text in [link.customURLString, link.universalURLString] {
            let parsed = try PuzzleLink.parse(text)
            #expect(parsed == link)
        }
    }

    @Test func versionsAreOptionalAndSurviveTheRoundTrip() throws {
        let pinned = PuzzleLink(seed: 1, variant: .classic, difficulty: .leicht,
                                generatorVersion: 3, catalogVersion: 7)
        #expect(pinned.customURLString.hasSuffix("?g=3&c=7"))
        #expect(try PuzzleLink.parse(pinned.customURLString) == pinned)

        // Ohne Versionen zeigt der Link auf das Rätsel, das heute aus diesem Seed
        // entsteht — er soll nicht brechen, weil der Katalog gewachsen ist.
        let loose = try PuzzleLink.parse("kreuzwort://p/classic/leicht/1")
        #expect(loose.generatorVersion == nil)
        #expect(loose.catalogVersion == nil)
    }

    @Test func toleratesTrailingSlashAndCase() throws {
        for text in ["KREUZWORT://p/arrow/mittel/9/",
                     "kreuzwort://p/ARROW/Mittel/9",
                     "  kreuzwort://p/arrow/mittel/9  "] {
            let parsed = try PuzzleLink.parse(text)
            #expect(parsed.seed == 9)
            #expect(parsed.variant == .arrow)
            #expect(parsed.difficulty == .mittel)
        }
    }

    @Test func rejectsInsteadOfGuessing() {
        // Ein Tippfehler darf nicht das falsche Rätsel öffnen.
        #expect(throws: PuzzleLink.ParseError.unknownVariant("swedish")) {
            try PuzzleLink.parse("kreuzwort://p/swedish/mittel/1")
        }
        #expect(throws: PuzzleLink.ParseError.unknownDifficulty("hart")) {
            try PuzzleLink.parse("kreuzwort://p/classic/hart/1")
        }
        #expect(throws: PuzzleLink.ParseError.badSeed("abc")) {
            try PuzzleLink.parse("kreuzwort://p/classic/mittel/abc")
        }
        #expect(throws: PuzzleLink.ParseError.notAPuzzleLink) {
            try PuzzleLink.parse("https://example.com/p/classic/mittel/1")
        }
        #expect(throws: PuzzleLink.ParseError.notAPuzzleLink) {
            try PuzzleLink.parse("kreuzwort://x/classic/mittel/1")
        }
        #expect(throws: PuzzleLink.ParseError.notAPuzzleLink) {
            try PuzzleLink.parse("kreuzwort://p/classic/mittel")
        }
    }

    @Test func handoffPayloadRoundTrip() {
        let link = PuzzleLink(seed: 123, variant: .arrow, difficulty: .experte,
                              generatorVersion: 2, catalogVersion: 5)
        let payload = link.activityPayload
        #expect(payload["variant"] == "arrow")
        #expect(payload["seed"] == "123")
        let back = PuzzleLink(activityPayload: payload)
        #expect(back == link)

        // Unvollständige Nutzlast wird nicht geraten.
        #expect(PuzzleLink(activityPayload: ["variant": "arrow"]) == nil)
        #expect(PuzzleLink(activityPayload: ["variant": "arrow", "difficulty": "mittel",
                                             "seed": "nichtszahl"]) == nil)
    }

    @Test func linkFromPuzzleMatchesTheSeed() {
        let size = GridSize(rows: 3, cols: 3)
        let entry = Entry(slot: Slot(id: 0, start: Cell(0, 0), direction: .across, length: 3),
                          answerID: 1, answer: "BOT", clueID: 1, clueText: "x",
                          clueShortText: nil, number: 1, arrow: nil, ownerCell: nil)
        let puzzle = Puzzle(seed: 555, variant: .arrow, difficulty: .mittel,
                            generatorVersion: 1, catalogVersion: 1, size: size,
                            layout: .classic(blocks: [Bool](repeating: false, count: 9)),
                            entries: [entry])
        #expect(PuzzleLink(puzzle: puzzle).seed == 555)
        #expect(PuzzleLink(puzzle: puzzle).generatorVersion == nil)
        #expect(PuzzleLink(puzzle: puzzle, pinVersions: true).catalogVersion == 1)
    }
}
