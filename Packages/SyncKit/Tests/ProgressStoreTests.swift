import Testing
import Foundation
import PuzzleKit
@testable import SyncKit

@Suite("Spielstand-Speicher")
struct ProgressStoreTests {
    private func tempStore(deviceID: UInt32 = 1) throws -> ProgressStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kreuzwort-store-\(UInt32.random(in: 1 ... .max))")
        return try ProgressStore(directory: dir, deviceID: deviceID)
    }

    private func makePuzzle(seed: UInt64 = 1, generatorVersion: Int = 1,
                            catalogVersion: Int = 1) -> Puzzle {
        let size = GridSize(rows: 3, cols: 3)
        let entry = Entry(slot: Slot(id: 0, start: Cell(0, 0), direction: .across, length: 3),
                          answerID: 1, answer: "BOT", clueID: 1, clueText: "Frage",
                          clueShortText: nil, number: 1, arrow: nil, ownerCell: nil)
        return Puzzle(seed: seed, variant: .classic, difficulty: .leicht,
                      generatorVersion: generatorVersion,
                      catalogVersion: catalogVersion, size: size,
                      layout: .classic(blocks: [Bool](repeating: false, count: 9)),
                      entries: [entry])
    }

    @Test func savesAndLoadsRoundTrip() throws {
        let store = try tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let puzzle = makePuzzle()
        var progress = PuzzleProgress(puzzle: puzzle, deviceID: store.deviceID)
        progress.set(Alphabet.index(of: "B"), at: 0)
        progress.elapsedSeconds = 42
        try store.save(progress)

        let loaded = try #require(store.load(puzzleID: puzzle.id))
        #expect(loaded.letter(at: 0) == Alphabet.index(of: "B"))
        #expect(loaded.elapsedSeconds == 42)
        #expect(loaded.puzzleID == puzzle.id)
    }

    @Test func deviceIDSurvivesReopening() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kreuzwort-device-\(UInt32.random(in: 1 ... .max))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try ProgressStore(directory: dir)
        let second = try ProgressStore(directory: dir)
        // Eine wechselnde Geräte-ID würde den Merge-Tiebreak unbrauchbar machen.
        #expect(first.deviceID == second.deviceID)
        #expect(first.deviceID != 0)
    }

    @Test func mergeInsteadOfOverwrite() throws {
        let store = try tempStore(deviceID: 1)
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let puzzle = makePuzzle()

        var local = PuzzleProgress(puzzle: puzzle, deviceID: 1)
        local.set(Alphabet.index(of: "B"), at: 0)
        try store.save(local)

        // Ein anderes Gerät hat eine andere Zelle gefüllt.
        var remote = PuzzleProgress(puzzle: puzzle, deviceID: 2)
        remote.set(Alphabet.index(of: "T"), at: 2)

        let merged = try store.merge(remote)
        #expect(merged.letter(at: 0) == Alphabet.index(of: "B"),
                "Überschreiben hätte die lokale Eingabe verworfen")
        #expect(merged.letter(at: 2) == Alphabet.index(of: "T"))
        #expect(store.load(puzzleID: puzzle.id)?.filledCells == 2)
    }

    @Test func resumeCardPicksTheNewestUnfinished() throws {
        let store = try tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        // Gelöst — soll nicht als „Weiterspielen" erscheinen.
        var done = PuzzleProgress(puzzle: makePuzzle(seed: 1), deviceID: store.deviceID)
        done.set(1, at: 0)
        done.completedAtEpoch = 100
        try store.save(done)

        // Angefangen.
        var open = PuzzleProgress(puzzle: makePuzzle(seed: 2), deviceID: store.deviceID)
        open.set(1, at: 0)
        try store.save(open)

        // Unberührt — auch nicht.
        try store.save(PuzzleProgress(puzzle: makePuzzle(seed: 3), deviceID: store.deviceID))

        let resume = try #require(store.mostRecentUnfinished())
        #expect(resume.puzzleID == open.puzzleID)
        #expect(store.count == 3)
    }

    @Test func staleProgressIsNotOfferedForResume() throws {
        let store = try tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        // Ein Stand aus einer früheren Katalogrunde. Er beschreibt nur Seed und
        // Buchstaben — das Gitter entsteht daraus neu. Mit einem anderen Katalog
        // ist das ein anderes Gitter, die Buchstaben lägen in fremden Zellen.
        var old = PuzzleProgress(puzzle: makePuzzle(seed: 7, catalogVersion: 111),
                                 deviceID: store.deviceID)
        old.set(1, at: 0)
        try store.save(old)

        // Ohne Angabe wie bisher: der Stand kommt zurück.
        #expect(store.mostRecentUnfinished()?.puzzleID == old.puzzleID)

        // Mit dem heutigen Abdruck: nicht mehr.
        #expect(store.mostRecentUnfinished(generatorVersion: 1, catalogVersion: 222) == nil)
        // Generatorversion zählt genauso.
        #expect(store.mostRecentUnfinished(generatorVersion: 2, catalogVersion: 111) == nil)
        // Passt beides, wird er angeboten.
        #expect(store.mostRecentUnfinished(generatorVersion: 1,
                                           catalogVersion: 111)?.puzzleID == old.puzzleID)

        // Und der Stand bleibt gespeichert — er wird nur nicht angeboten. Ein
        // Rätsel kann später wieder passen, etwa nach einem Rückbau.
        #expect(store.count == 1)
    }

    @Test func deleteRemovesTheEntry() throws {
        let store = try tempStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let puzzle = makePuzzle()
        try store.save(PuzzleProgress(puzzle: puzzle, deviceID: store.deviceID))
        #expect(store.load(puzzleID: puzzle.id) != nil)
        store.delete(puzzleID: puzzle.id)
        #expect(store.load(puzzleID: puzzle.id) == nil)
    }
}
