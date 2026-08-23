import Foundation
import PuzzleKit

/// Lokaler Speicher für Spielstände.
///
/// Ein Spielstand ist winzig — Seed, Buchstaben, Uhr, Hilfen —, weil das Rätsel
/// selbst nie gespeichert wird, sondern aus dem Seed regeneriert. Deshalb genügt
/// eine Datei pro Rätsel als JSON; eine Datenbank wäre hier Ballast.
///
/// Das ist gleichzeitig die Grundlage des CloudKit-Sync (M8): der Store ist die
/// lokale Wahrheit, die Synchronisierung schreibt später nur hinein und liest
/// heraus. `merged` steckt schon in `PuzzleProgress`.
public final class ProgressStore: @unchecked Sendable {
    public let directory: URL
    private let queue = DispatchQueue(label: "com.kreuzwort.progressstore")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Kennung dieses Geräts. Wird für den Tiebreak beim Zusammenführen
    /// gebraucht und muss über App-Starts stabil bleiben.
    public let deviceID: UInt32

    public init(directory: URL? = nil, deviceID: UInt32? = nil) throws {
        let base = try directory ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("Kreuzwort/progress")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.directory = base
        encoder.outputFormatting = [.sortedKeys]

        if let deviceID {
            self.deviceID = deviceID
        } else {
            // Einmal erzeugen und ablegen. Eine wechselnde Geräte-ID würde den
            // Merge-Tiebreak unbrauchbar machen.
            let file = base.appendingPathComponent("device-id")
            if let text = try? String(contentsOf: file, encoding: .utf8),
               let value = UInt32(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                self.deviceID = value
            } else {
                let value = UInt32.random(in: 1 ... UInt32.max)
                try? String(value).write(to: file, atomically: true, encoding: .utf8)
                self.deviceID = value
            }
        }
    }

    private func url(for puzzleID: String) -> URL {
        directory.appendingPathComponent("\(puzzleID).json")
    }

    public func save(_ progress: PuzzleProgress) throws {
        try queue.sync {
            let data = try encoder.encode(progress)
            try data.write(to: url(for: progress.puzzleID), options: .atomic)
        }
    }

    public func load(puzzleID: String) -> PuzzleProgress? {
        queue.sync {
            guard let data = try? Data(contentsOf: url(for: puzzleID)) else { return nil }
            return try? decoder.decode(PuzzleProgress.self, from: data)
        }
    }

    /// Alle gespeicherten Spielstände, neueste Aktivität zuerst.
    public func all() -> [PuzzleProgress] {
        queue.sync {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey]))
                ?? []
            let entries: [(PuzzleProgress, Date)] = files
                .filter { $0.pathExtension == "json" }
                .compactMap { url in
                    guard let data = try? Data(contentsOf: url),
                          let progress = try? decoder.decode(PuzzleProgress.self, from: data)
                    else { return nil }
                    let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate) ?? .distantPast
                    return (progress, date)
                }
            return entries.sorted { $0.1 > $1.1 }.map(\.0)
        }
    }

    /// Der angefangene, aber nicht gelöste Spielstand mit der neuesten Aktivität —
    /// die Grundlage der „Weiterspielen"-Karte.
    public func mostRecentUnfinished() -> PuzzleProgress? {
        all().first { $0.completedAtEpoch == nil && $0.filledCells > 0 }
    }

    /// Zusammenführen statt überschreiben: liegt schon ein Stand vor, gewinnt
    /// nicht der zuletzt Schreibende, sondern das Ergebnis des Merges. Sonst
    /// verliert ein Gerät, das zwischenzeitlich gespielt hat, seine Eingaben.
    public func merge(_ incoming: PuzzleProgress) throws -> PuzzleProgress {
        let result = load(puzzleID: incoming.puzzleID)
            .map { PuzzleProgress.merged($0, incoming) } ?? incoming
        try save(result)
        return result
    }

    public func delete(puzzleID: String) {
        queue.sync { try? FileManager.default.removeItem(at: url(for: puzzleID)) }
    }

    public var count: Int {
        queue.sync {
            ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
                .count { $0.hasSuffix(".json") }
        }
    }
}
