import Testing
@testable import PuzzleKit

@Suite("Spielstand und Merge")
struct ProgressTests {
    private func makeProgress(deviceID: UInt32, cells: Int = 40) -> PuzzleProgress {
        PuzzleProgress(puzzleID: "test", seed: 1, variant: .classic, difficulty: .mittel,
                       generatorVersion: 1, catalogVersion: 1,
                       cells: [CellState](repeating: .empty, count: cells),
                       elapsedSeconds: 0, hints: .none, completedAtEpoch: nil,
                       scoreAwarded: nil, clock: 0, deviceID: deviceID)
    }

    @Test func settingALetterStampsTheCell() {
        var p = makeProgress(deviceID: 7)
        p.set(Alphabet.index(of: "B"), at: 3)
        #expect(p.letter(at: 3) == Alphabet.index(of: "B"))
        #expect(p.cells[3].stamp == 1)
        #expect(p.cells[3].deviceID == 7)
        p.set(Alphabet.index(of: "C"), at: 3)
        #expect(p.cells[3].stamp == 2)
        #expect(p.filledCells == 1)
    }

    @Test func cellMergeIsCommutativeAndIdempotent() {
        let a = CellState(letter: 1, stamp: 5, deviceID: 1)
        let b = CellState(letter: 2, stamp: 5, deviceID: 2)
        #expect(CellState.merged(a, b) == CellState.merged(b, a))
        #expect(CellState.merged(a, b).deviceID == 2)   // Tiebreak: höhere ID
        #expect(CellState.merged(a, a) == a)
        let newer = CellState(letter: 3, stamp: 9, deviceID: 1)
        #expect(CellState.merged(a, newer).letter == 3)
    }

    @Test func noSetLetterIsEverLost() {
        // Das Szenario, um das es geht: iPhone und iPad beide offline am selben
        // Rätsel, jedes hat andere Zellen gefüllt.
        var phone = makeProgress(deviceID: 1)
        var pad = makeProgress(deviceID: 2)
        for i in stride(from: 0, to: 40, by: 2) { phone.set(UInt8(i % 29), at: i) }
        for i in stride(from: 1, to: 40, by: 2) { pad.set(UInt8(i % 29), at: i) }

        let merged = PuzzleProgress.merged(phone, pad)
        #expect(merged.filledCells == 40, Comment(rawValue:
            "\(merged.filledCells) von 40 — Last-Writer-Wins hätte die Hälfte verworfen"))
        for i in 0 ..< 40 { #expect(merged.letter(at: i) == UInt8(i % 29)) }
    }

    @Test func mergeIsOrderIndependentAndIdempotent() {
        // Property-Test mit festem Seed: der Merge muss kommutativ und
        // idempotent sein, sonst hängt das Ergebnis davon ab, in welcher
        // Reihenfolge sich zwei Geräte melden.
        var rng = SplitMix64(seed: 2026)
        for round in 0 ..< 60 {
            var a = makeProgress(deviceID: 1)
            var b = makeProgress(deviceID: 2)
            for _ in 0 ..< 20 {
                a.set(UInt8(rng.int(below: 29)), at: rng.int(below: 40))
                b.set(UInt8(rng.int(below: 29)), at: rng.int(below: 40))
            }
            a.elapsedSeconds = Double(rng.int(below: 900))
            b.elapsedSeconds = Double(rng.int(below: 900))
            a.hints = HintUsage(lettersRevealed: rng.int(below: 4),
                                gridChecks: rng.int(below: 3))
            b.hints = HintUsage(lettersRevealed: rng.int(below: 4),
                                wordsRevealed: rng.int(below: 2))

            let ab = PuzzleProgress.merged(a, b)
            let ba = PuzzleProgress.merged(b, a)
            #expect(ab.cells.map(\.letter) == ba.cells.map(\.letter),
                    Comment(rawValue: "Runde \(round): Merge nicht kommutativ"))
            #expect(ab.elapsedSeconds == ba.elapsedSeconds)
            #expect(ab.hints == ba.hints)
            // Idempotenz: nochmal mergen ändert nichts.
            let again = PuzzleProgress.merged(ab, b)
            #expect(again.cells.map(\.letter) == ab.cells.map(\.letter),
                    Comment(rawValue: "Runde \(round): Merge nicht idempotent"))
        }
    }

    @Test func elapsedAndHintsTakeTheMaximum() {
        var a = makeProgress(deviceID: 1)
        var b = makeProgress(deviceID: 2)
        a.elapsedSeconds = 300; b.elapsedSeconds = 120
        a.hints = HintUsage(lettersRevealed: 3, gridChecks: 1)
        b.hints = HintUsage(lettersRevealed: 1, wordsRevealed: 2)
        let m = PuzzleProgress.merged(a, b)
        #expect(m.elapsedSeconds == 300)
        // Eine benutzte Hilfe lässt sich nicht zurücknehmen.
        #expect(m.hints.lettersRevealed == 3)
        #expect(m.hints.wordsRevealed == 2)
        #expect(m.hints.gridChecks == 1)
    }

    @Test func earlierCompletionWinsAndTheScoreFollowsIt() {
        // Sonst bekäme dasselbe Rätsel auf zwei Geräten zweimal Punkte.
        var early = makeProgress(deviceID: 1)
        var late = makeProgress(deviceID: 2)
        early.completedAtEpoch = 1000; early.scoreAwarded = 275
        late.completedAtEpoch = 2000; late.scoreAwarded = 310

        for m in [PuzzleProgress.merged(early, late), PuzzleProgress.merged(late, early)] {
            #expect(m.completedAtEpoch == 1000)
            #expect(m.scoreAwarded == 275)
        }
    }

    @Test func oneSidedCompletionSurvives() {
        var done = makeProgress(deviceID: 1)
        done.completedAtEpoch = 500; done.scoreAwarded = 200
        let open = makeProgress(deviceID: 2)
        #expect(PuzzleProgress.merged(open, done).scoreAwarded == 200)
        #expect(PuzzleProgress.merged(done, open).scoreAwarded == 200)
    }

    @Test func mergeRefusesDifferentPuzzles() {
        let a = makeProgress(deviceID: 1)
        var b = makeProgress(deviceID: 2)
        b = PuzzleProgress(puzzleID: "andere", seed: 2, variant: .arrow,
                           difficulty: .schwer, generatorVersion: 1, catalogVersion: 1,
                           cells: b.cells, elapsedSeconds: 99, hints: .none,
                           completedAtEpoch: nil, scoreAwarded: nil, clock: 0, deviceID: 2)
        // Kein stiller Mischmasch: der eigene Stand bleibt unverändert.
        #expect(PuzzleProgress.merged(a, b).elapsedSeconds == 0)
    }

    @Test func completionRatioForTheResumeCard() {
        var p = makeProgress(deviceID: 1, cells: 100)
        for i in 0 ..< 62 { p.set(1, at: i) }
        #expect(p.completion(letterCells: 100) == 0.62)
        #expect(p.completion(letterCells: 0) == 0)
    }
}
