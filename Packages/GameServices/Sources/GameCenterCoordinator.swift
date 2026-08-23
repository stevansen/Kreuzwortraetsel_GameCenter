import Foundation
import PuzzleKit

/// Bindet Profil, Outbox und Game Center zusammen.
///
/// Die Aufgabenteilung ist der Kern von M7: das **Profil** ist die Wahrheit, die
/// **Outbox** überbrückt fehlende Anmeldung oder Netz, und Game Center ist die
/// Anzeige. Kein Spielstand und kein Punkt hängt davon ab, dass GameKit
/// antwortet.
public actor GameCenterCoordinator {
    private let service: any GameCenterService
    private let outbox: SubmissionOutbox
    private let deviceID: UInt32
    /// Letzter gemeldeter Achievement-Stand, um Wiederholungen zu vermeiden.
    private var lastReported: [AchievementProgress] = []

    public init(service: any GameCenterService, outbox: SubmissionOutbox, deviceID: UInt32) {
        self.service = service
        self.outbox = outbox
        self.deviceID = deviceID
    }

    public var isAuthenticated: Bool { service.isAuthenticated }
    public var canPresentDashboard: Bool { service.canPresentDashboard }
    public var playerDisplayName: String? { service.playerDisplayName }
    public var pendingSubmissions: Int { outbox.count }

    /// Beim App-Start aufrufen. Blockiert die Oberfläche nicht: der Aufrufer
    /// startet das als Task und spielt weiter.
    public func start() async {
        await service.authenticate()
        await flush()
    }

    /// Ein gelöstes Rätsel verbuchen: Profil fortschreiben, Meldungen einreihen,
    /// absetzen was geht.
    ///
    /// Nimmt das Profil als Wert und gibt das neue zurück, statt `inout` zu
    /// verwenden: `inout` über eine Aktorgrenze ist nicht erlaubt, und der
    /// Rückgabewert macht ohnehin sichtbar, dass hier etwas entsteht.
    @discardableResult
    public func record(_ completion: PlayerProfile.Completion,
                       profile: PlayerProfile,
                       today: Int) async -> (profile: PlayerProfile,
                                             changed: [AchievementProgress]) {
        var profile = profile
        let before = AchievementEvaluator.progress(for: profile, today: today)
        profile.record(completion, device: deviceID)
        let after = AchievementEvaluator.progress(for: profile, today: today)
        let changed = AchievementEvaluator.changed(from: before, to: after)

        var submissions: [Submission] = [
            .score(leaderboard: Leaderboard.totalPoints.rawValue, value: profile.points.total),
            .score(leaderboard: Leaderboard.dailyPoints.rawValue, value: completion.points),
            .score(leaderboard: Leaderboard.weeklyPoints.rawValue, value: completion.points),
        ]
        // Zeit-Leaderboard nur bei Experte und nur ohne Hilfen: eine mit
        // aufgedeckten Buchstaben erspielte Bestzeit wäre keine.
        if completion.difficulty == .experte, completion.hints.isClean {
            submissions.append(.score(
                leaderboard: Leaderboard.fastestExpert(for: completion.variant).rawValue,
                value: Int((completion.elapsedSeconds * 100).rounded())))
        }
        submissions += changed.map {
            .achievement(id: $0.achievement.rawValue, percentComplete: $0.percentComplete)
        }

        outbox.add(submissions)
        lastReported = after
        await flush()
        return (profile, changed)
    }

    /// Nach einem Sync aufrufen: das zusammengeführte Profil kann Achievements
    /// erfüllen, die auf diesem Gerät nie erspielt wurden.
    public func reconcile(profile: PlayerProfile, today: Int) async {
        let current = AchievementEvaluator.progress(for: profile, today: today)
        let changed = AchievementEvaluator.changed(from: lastReported, to: current)
        guard !changed.isEmpty else { return }
        outbox.add(changed.map {
            .achievement(id: $0.achievement.rawValue, percentComplete: $0.percentComplete)
        })
        outbox.add([.score(leaderboard: Leaderboard.totalPoints.rawValue,
                           value: profile.points.total)])
        lastReported = current
        await flush()
    }

    @discardableResult
    public func flush() async -> (sent: Int, kept: Int) {
        await outbox.flush(using: service)
    }
}
