import Testing
import Foundation
import PuzzleKit
@testable import SyncKit

@Suite("Widget-Momentaufnahme")
struct SnapshotTests {
    private func store() throws -> SharedSnapshotStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kreuzwort-snap-\(UInt32.random(in: 1 ... .max))")
        return try SharedSnapshotStore(appGroupIdentifier: nil, directory: dir)
    }

    @Test func emptyWhenNothingWritten() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.url) }
        #expect(store.read() == .empty)
        #expect(store.read().points == 0)
    }

    @Test func roundTrip() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.url) }
        var snapshot = SharedSnapshot(points: 1234, solved: 7, streak: 3)
        snapshot.resumeVariant = PuzzleVariant.arrow.rawValue
        snapshot.resumeCompletion = 0.42
        try store.write(snapshot)
        #expect(store.read() == snapshot)
    }

    @Test func builtFromProfileAndProgress() throws {
        let store = try store()
        defer { try? FileManager.default.removeItem(at: store.url) }

        var profile = PlayerProfile()
        for day in [10, 11, 12] {
            profile.record(PlayerProfile.Completion(
                variant: .classic, difficulty: .mittel, points: 100, hints: .none,
                elapsedSeconds: 600, answerIDs: [1], isDaily: true, day: day,
                hour: 12, platform: "phone"), device: 1)
        }

        let size = GridSize(rows: 3, cols: 3)
        let entry = Entry(slot: Slot(id: 0, start: Cell(0, 0), direction: .across, length: 3),
                          answerID: 1, answer: "BOT", clueID: 1, clueText: "x",
                          clueShortText: nil, number: 1, arrow: nil, ownerCell: nil)
        let puzzle = Puzzle(seed: 1, variant: .arrow, difficulty: .schwer,
                            generatorVersion: 1, catalogVersion: 1, size: size,
                            layout: .classic(blocks: [Bool](repeating: false, count: 9)),
                            entries: [entry])
        var progress = PuzzleProgress(puzzle: puzzle, deviceID: 1)
        progress.set(1, at: 0)
        progress.set(2, at: 1)

        try store.update(profile: profile, today: 12, resumable: progress,
                         letterCells: 4, now: 1_700_000_000)
        let snapshot = store.read()
        #expect(snapshot.points == 300)
        #expect(snapshot.solved == 3)
        #expect(snapshot.streak == 3)
        #expect(snapshot.dailyDone[PuzzleVariant.classic.rawValue] == true)
        #expect(snapshot.resumeVariant == PuzzleVariant.arrow.rawValue)
        #expect(snapshot.resumeCompletion == 0.5)
        #expect(snapshot.updatedAtEpoch == 1_700_000_000)
    }

    @Test func remainsUsableWithoutAProvisionedAppGroup() throws {
        // Die Zusage ist nicht „es gibt eine App Group", sondern „Lesen und
        // Schreiben funktionieren immer". Ohne bereitgestellte Gruppe
        // funktioniert die App vollständig, nur das Widget sieht nichts — das ist
        // der ehrlichere Ausgang als ein Absturz.
        //
        // `isShared` wird hier absichtlich **nicht** geprüft: auf macOS lässt
        // sich der Gruppenpfad auch ohne Entitlement anlegen, die Auskunft ist
        // dort also nicht aussagekräftig (siehe Kommentar am Typ).
        let name = "group.com.kreuzwort.test.\(UInt32.random(in: 1 ... .max))"
        let store = try SharedSnapshotStore(appGroupIdentifier: name)
        defer {
            try? FileManager.default.removeItem(at: store.url)
            try? FileManager.default.removeItem(at: store.url.deletingLastPathComponent())
        }
        try store.write(SharedSnapshot(points: 5))
        #expect(store.read().points == 5)
    }
}
