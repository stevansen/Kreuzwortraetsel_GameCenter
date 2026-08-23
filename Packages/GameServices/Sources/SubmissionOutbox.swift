import Foundation
import PuzzleKit

/// Puffer für Meldungen, die noch nicht abgesetzt werden konnten.
///
/// Der Grund ist der Normalfall, nicht der Ausnahmefall: die App ist ohne
/// Anmeldung voll spielbar, also entstehen Punkte und Achievements regelmäßig
/// **bevor** Game Center erreichbar ist. Ohne Puffer wären sie verloren, und
/// zwar unbemerkt.
///
/// Die Ablage ist eine Datei. Sie überlebt App-Neustarts, weil ein Spieler auch
/// tagelang offline bleiben kann.
public final class SubmissionOutbox: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var pending: [Submission]
    /// Obergrenze, damit ein sehr lange offline gespielter Vorrat nicht
    /// unbegrenzt wächst. Punktestände sind ohnehin kumulativ — der neueste
    /// Wert genügt, ältere sind entbehrlich.
    public let limit: Int

    public init(directory: URL? = nil, limit: Int = 500) throws {
        let base = try directory ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("Kreuzwort")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.url = base.appendingPathComponent("outbox.json")
        self.limit = limit
        if let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode([Submission].self, from: data) {
            pending = stored
        } else {
            pending = []
        }
    }

    public var count: Int { lock.withLock { pending.count } }

    public func add(_ submissions: [Submission]) {
        guard !submissions.isEmpty else { return }
        let snapshot = lock.withLock { () -> [Submission] in
            pending += submissions
            collapse()
            if pending.count > limit { pending.removeFirst(pending.count - limit) }
            return pending
        }
        persist(snapshot)
    }

    /// Setzt alles ab, was geht, und behält, was scheitert.
    ///
    /// Bewusst **nicht** alles verwerfen, wenn eine Meldung scheitert: eine
    /// abgelehnte Punktzahl darf nicht die zwanzig Achievements mitnehmen, die
    /// danach kommen.
    @discardableResult
    public func flush(using service: any GameCenterService) async -> (sent: Int, kept: Int) {
        guard service.isAuthenticated else {
            return (0, count)
        }
        let work = lock.withLock { pending }

        var failed: [Submission] = []
        var sent = 0
        for submission in work {
            do {
                switch submission {
                case .score(let leaderboard, let value):
                    guard let board = Leaderboard(rawValue: leaderboard) else { continue }
                    try await service.submit(score: value, to: board)
                case .achievement(let id, let percent):
                    guard let achievement = Achievement(rawValue: id) else { continue }
                    let target = achievement.target
                    let value = Int((percent / 100 * Double(target)).rounded())
                    try await service.report([AchievementProgress(
                        achievement: achievement, value: value, target: target)])
                }
                sent += 1
            } catch {
                failed.append(submission)
            }
        }

        let snapshot = lock.withLock { () -> [Submission] in
            // Was während des Absetzens dazukam, bleibt erhalten.
            let added = pending.count > work.count ? Array(pending.dropFirst(work.count)) : []
            pending = failed + added
            return pending
        }
        persist(snapshot)
        return (sent, snapshot.count)
    }

    /// Fasst zusammen, was sich überschreibt: von jedem Leaderboard und jedem
    /// Achievement bleibt nur die letzte Meldung. Zehn Punktestände desselben
    /// Leaderboards abzusetzen ist neunmal Arbeit für nichts.
    private func collapse() {
        var lastScore: [String: Int] = [:]
        var lastAchievement: [String: Double] = [:]
        var order: [Submission] = []
        for submission in pending {
            switch submission {
            case .score(let board, let value): lastScore[board] = value
            case .achievement(let id, let percent):
                lastAchievement[id] = max(lastAchievement[id] ?? 0, percent)
            }
        }
        for board in lastScore.keys.sorted() {
            order.append(.score(leaderboard: board, value: lastScore[board]!))
        }
        for id in lastAchievement.keys.sorted() {
            order.append(.achievement(id: id, percentComplete: lastAchievement[id]!))
        }
        pending = order
    }

    private func persist(_ snapshot: [Submission]) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public func clear() {
        lock.withLock { pending = [] }
        try? FileManager.default.removeItem(at: url)
    }
}
