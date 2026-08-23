import Testing
import Foundation
import PuzzleKit
@testable import SyncKit

@Suite("Synchronisierung")
struct SyncTests {
    /// Ein simuliertes Gerät: eigene Speicher, eigenes Backend, gemeinsame Cloud.
    private struct Device {
        let progressStore: ProgressStore
        let profileStore: ProfileStore
        let backend: InMemorySyncBackend
        let coordinator: SyncCoordinator
        let id: UInt32
        let directory: URL

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }

    private func makeDevice(id: UInt32,
                            cloud: InMemorySyncBackend.Storage) throws -> Device {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kreuzwort-sync-\(id)-\(UInt32.random(in: 1 ... .max))")
        let progressStore = try ProgressStore(directory: dir.appendingPathComponent("progress"),
                                              deviceID: id)
        let profileStore = try ProfileStore(directory: dir)
        let backend = InMemorySyncBackend(storage: cloud)
        return Device(progressStore: progressStore, profileStore: profileStore,
                      backend: backend,
                      coordinator: SyncCoordinator(backend: backend,
                                                   progressStore: progressStore,
                                                   profileStore: profileStore, deviceID: id),
                      id: id, directory: dir)
    }

    private func makePuzzle(seed: UInt64 = 1) -> Puzzle {
        let size = GridSize(rows: 3, cols: 3)
        let entry = Entry(slot: Slot(id: 0, start: Cell(0, 0), direction: .across, length: 3),
                          answerID: 1, answer: "BOT", clueID: 1, clueText: "x",
                          clueShortText: nil, number: 1, arrow: nil, ownerCell: nil)
        return Puzzle(seed: seed, variant: .classic, difficulty: .leicht,
                      generatorVersion: 1, catalogVersion: 1, size: size,
                      layout: .classic(blocks: [Bool](repeating: false, count: 9)),
                      entries: [entry])
    }

    @Test func twoOfflineDevicesConvergeAndLoseNothing() async throws {
        // Der Fall, um den es geht: iPhone und iPad beide am selben Rätsel,
        // jedes hat andere Zellen gefüllt.
        let cloud = InMemorySyncBackend.Storage()
        let phone = try makeDevice(id: 1, cloud: cloud)
        let pad = try makeDevice(id: 2, cloud: cloud)
        defer { phone.cleanUp(); pad.cleanUp() }
        let puzzle = makePuzzle()

        var onPhone = PuzzleProgress(puzzle: puzzle, deviceID: 1)
        onPhone.set(Alphabet.index(of: "B"), at: 0)
        try phone.progressStore.save(onPhone)
        await phone.coordinator.push(progress: onPhone)

        var onPad = PuzzleProgress(puzzle: puzzle, deviceID: 2)
        onPad.set(Alphabet.index(of: "T"), at: 2)
        try pad.progressStore.save(onPad)
        await pad.coordinator.push(progress: onPad)

        // Beide synchronisieren. Der zweite Upload läuft in einen Konflikt —
        // der Server ist weiter — und die Schicht löst ihn: holen, lokal
        // zusammenführen, erneut senden.
        _ = await phone.coordinator.synchronize()
        _ = await pad.coordinator.synchronize()
        _ = await phone.coordinator.synchronize()

        let onPhoneAfter = try #require(phone.progressStore.load(puzzleID: puzzle.id))
        let onPadAfter = try #require(pad.progressStore.load(puzzleID: puzzle.id))
        for stand in [onPhoneAfter, onPadAfter] {
            #expect(stand.letter(at: 0) == Alphabet.index(of: "B"))
            #expect(stand.letter(at: 2) == Alphabet.index(of: "T"))
            #expect(stand.filledCells == 2, "Überschreiben hätte eine Eingabe verworfen")
        }
    }

    @Test func orderOfSynchronisationDoesNotMatter() async throws {
        // Die Reihenfolge, in der sich Geräte melden, darf das Ergebnis nicht
        // beeinflussen — sonst hängt der Spielstand vom Zufall ab.
        func run(phoneFirst: Bool) async throws -> Int {
            let cloud = InMemorySyncBackend.Storage()
            let phone = try makeDevice(id: 1, cloud: cloud)
            let pad = try makeDevice(id: 2, cloud: cloud)
            defer { phone.cleanUp(); pad.cleanUp() }
            let puzzle = makePuzzle()

            var a = PuzzleProgress(puzzle: puzzle, deviceID: 1)
            a.set(1, at: 0); a.set(2, at: 1)
            var b = PuzzleProgress(puzzle: puzzle, deviceID: 2)
            b.set(3, at: 2); b.set(4, at: 3)

            try phone.progressStore.save(a)
            try pad.progressStore.save(b)
            if phoneFirst {
                await phone.coordinator.push(progress: a)
                _ = await phone.coordinator.synchronize()
                await pad.coordinator.push(progress: b)
                _ = await pad.coordinator.synchronize()
            } else {
                await pad.coordinator.push(progress: b)
                _ = await pad.coordinator.synchronize()
                await phone.coordinator.push(progress: a)
                _ = await phone.coordinator.synchronize()
            }
            _ = await phone.coordinator.synchronize()
            return phone.progressStore.load(puzzleID: puzzle.id)?.filledCells ?? -1
        }
        let first = try await run(phoneFirst: true)
        let second = try await run(phoneFirst: false)
        #expect(first == second)
        #expect(first == 4)
    }

    @Test func profileCountersAddUpAcrossDevices() async throws {
        let cloud = InMemorySyncBackend.Storage()
        let phone = try makeDevice(id: 1, cloud: cloud)
        let pad = try makeDevice(id: 2, cloud: cloud)
        defer { phone.cleanUp(); pad.cleanUp() }

        func completion(_ points: Int) -> PlayerProfile.Completion {
            PlayerProfile.Completion(variant: .classic, difficulty: .mittel, points: points,
                                     hints: .none, elapsedSeconds: 600, answerIDs: [1],
                                     isDaily: false, day: 1, hour: 12, platform: "phone")
        }

        var a = PlayerProfile(); a.record(completion(100), device: 1)
        try phone.profileStore.save(a)
        await phone.coordinator.push(profile: a)

        var b = PlayerProfile(); b.record(completion(200), device: 2)
        try pad.profileStore.save(b)
        await pad.coordinator.push(profile: b)

        _ = await phone.coordinator.synchronize()
        _ = await pad.coordinator.synchronize()
        _ = await phone.coordinator.synchronize()
        let merged = phone.profileStore.load()
        // Genau der Fall, den ein Skalar falsch macht.
        #expect(merged.points.total == 300)
        #expect(merged.solved.total == 2)
    }

    @Test func conflictIsResolvedByMergingAndRetrying() async throws {
        // Ein Gerät lädt hoch, ohne vorher zu holen — CloudKits
        // serverRecordChanged. Verworfen werden darf dabei nichts.
        let cloud = InMemorySyncBackend.Storage()
        let phone = try makeDevice(id: 1, cloud: cloud)
        let pad = try makeDevice(id: 2, cloud: cloud)
        defer { phone.cleanUp(); pad.cleanUp() }
        let puzzle = makePuzzle()

        var onPhone = PuzzleProgress(puzzle: puzzle, deviceID: 1)
        onPhone.set(Alphabet.index(of: "B"), at: 0)
        try phone.progressStore.save(onPhone)
        await phone.coordinator.push(progress: onPhone)
        #expect(await phone.coordinator.pendingCount == 0)

        // Das Pad hat den fremden Stand nie gesehen und lädt trotzdem hoch.
        var onPad = PuzzleProgress(puzzle: puzzle, deviceID: 2)
        onPad.set(Alphabet.index(of: "T"), at: 2)
        try pad.progressStore.save(onPad)
        await pad.coordinator.push(progress: onPad)

        // Der Konflikt wurde aufgelöst, nicht verschoben.
        #expect(await pad.coordinator.pendingCount == 0)
        let padStand = try #require(pad.progressStore.load(puzzleID: puzzle.id))
        #expect(padStand.filledCells == 2)
        #expect(padStand.letter(at: 0) == Alphabet.index(of: "B"))

        // Und das Telefon bekommt beim nächsten Holen den vollen Stand.
        _ = try await phone.coordinator.fetch()
        #expect(phone.progressStore.load(puzzleID: puzzle.id)?.filledCells == 2)
    }

    @Test func failedUploadKeepsTheRecord() async throws {
        let cloud = InMemorySyncBackend.Storage()
        let device = try makeDevice(id: 1, cloud: cloud)
        defer { device.cleanUp() }
        device.backend.failsUploads = true

        var progress = PuzzleProgress(puzzle: makePuzzle(), deviceID: 1)
        progress.set(1, at: 0)
        await device.coordinator.push(progress: progress)
        #expect(await device.coordinator.pendingCount == 1)
        #expect(cloud.count == 0)

        device.backend.failsUploads = false
        let result = await device.coordinator.flush()
        #expect(result.sent == 1)
        #expect(await device.coordinator.pendingCount == 0)
        #expect(cloud.count == 1)
    }

    @Test func repeatedPushesOfTheSamePuzzleCollapse() async throws {
        let cloud = InMemorySyncBackend.Storage()
        let device = try makeDevice(id: 1, cloud: cloud)
        defer { device.cleanUp() }
        device.backend.failsUploads = true
        let puzzle = makePuzzle()

        var progress = PuzzleProgress(puzzle: puzzle, deviceID: 1)
        for i in 0 ..< 5 {
            progress.set(UInt8(i + 1), at: i)
            await device.coordinator.push(progress: progress)
        }
        // Der Spielstand ist kumulativ — es zählt der neueste.
        #expect(await device.coordinator.pendingCount == 1)
    }

    @Test func localOnlyBackendIsUsableAndReportsItself() async throws {
        // Ohne diesen Rückfall wäre die App in der Entwicklung nicht startbar:
        // CloudKit braucht ein bezahltes Konto und einen Container.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kreuzwort-local-\(UInt32.random(in: 1 ... .max))")
        defer { try? FileManager.default.removeItem(at: dir) }
        let coordinator = SyncCoordinator(
            backend: LocalOnlySyncBackend(),
            progressStore: try ProgressStore(directory: dir.appendingPathComponent("p"),
                                             deviceID: 1),
            profileStore: try ProfileStore(directory: dir), deviceID: 1)

        #expect(await coordinator.isAvailable == false)
        var progress = PuzzleProgress(puzzle: makePuzzle(), deviceID: 1)
        progress.set(1, at: 0)
        await coordinator.push(progress: progress)
        // Vorgemerkt, nicht verloren — falls später ein Konto dazukommt.
        #expect(await coordinator.pendingCount == 1)
        await #expect(throws: SyncError.self) { try await coordinator.fetch() }
    }

    @Test func unknownRecordKindDoesNotAbortTheRun() async throws {
        // Eine neuere App-Version darf die ältere nicht blockieren.
        let cloud = InMemorySyncBackend.Storage()
        let device = try makeDevice(id: 1, cloud: cloud)
        defer { device.cleanUp() }

        let puzzle = makePuzzle()
        var progress = PuzzleProgress(puzzle: puzzle, deviceID: 2)
        progress.set(9, at: 1)
        try await device.backend.upload([
            SyncRecord(kind: .settings, id: "future", payload: Data([0x01]), deviceID: 2),
            try SyncRecord.progress(progress, deviceID: 2),
        ])

        let result = try await device.coordinator.fetch()
        #expect(result.skipped == 1)
        #expect(result.mergedProgress == [puzzle.id])
        #expect(device.progressStore.load(puzzleID: puzzle.id)?.letter(at: 1) == 9)
    }
}
