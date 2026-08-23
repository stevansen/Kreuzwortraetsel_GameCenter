import Testing
import Foundation
import PuzzleKit
@testable import GameServices

@Suite("Game Center")
struct GameCenterTests {
    private func tempOutbox(limit: Int = 500) throws -> SubmissionOutbox {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kreuzwort-outbox-\(UInt32.random(in: 1 ... .max))")
        return try SubmissionOutbox(directory: dir, limit: limit)
    }

    private func completion(difficulty: Difficulty = .mittel,
                            variant: PuzzleVariant = .classic,
                            points: Int = 250, hints: HintUsage = .none,
                            seconds: Double = 600) -> PlayerProfile.Completion {
        PlayerProfile.Completion(variant: variant, difficulty: difficulty, points: points,
                                 hints: hints, elapsedSeconds: seconds, answerIDs: [1, 2],
                                 isDaily: false, day: 20_000, hour: 12, platform: "phone")
    }

    @Test func leaderboardIdentifiersAreUniqueAndTyped() {
        #expect(Set(Leaderboard.allCases.map(\.rawValue)).count == Leaderboard.allCases.count)
        #expect(Leaderboard.fastestExpertClassic.isTime)
        #expect(!Leaderboard.totalPoints.isTime)
        #expect(Leaderboard.fastestExpert(for: .arrow) == .fastestExpertArrow)
    }

    @Test func unauthenticatedServiceKeepsEverythingInTheOutbox() async throws {
        // Der Normalfall, nicht der Ausnahmefall: gespielt wird, bevor sich
        // jemand anmeldet. Ohne Puffer wären die Punkte lautlos verloren.
        let service = FakeGameCenterService(isAuthenticated: false)
        let outbox = try tempOutbox()
        defer { outbox.clear() }
        outbox.add([.score(leaderboard: Leaderboard.totalPoints.rawValue, value: 500)])

        let result = await outbox.flush(using: service)
        #expect(result.sent == 0)
        #expect(result.kept == 1)
        #expect(service.submittedScores.isEmpty)

        // Nach der Anmeldung geht es raus.
        service.setAuthenticated(true)
        let second = await outbox.flush(using: service)
        #expect(second.sent == 1)
        #expect(second.kept == 0)
        #expect(service.submittedScores.first?.1 == 500)
    }

    @Test func outboxCollapsesRepeatedSubmissions() throws {
        // Zehn Punktestände desselben Leaderboards abzusetzen ist neunmal Arbeit
        // für nichts — es zählt der letzte.
        let outbox = try tempOutbox()
        defer { outbox.clear() }
        for value in [100, 200, 300] {
            outbox.add([.score(leaderboard: Leaderboard.totalPoints.rawValue, value: value)])
        }
        #expect(outbox.count == 1)

        outbox.add([.achievement(id: Achievement.solve10.rawValue, percentComplete: 30),
                    .achievement(id: Achievement.solve10.rawValue, percentComplete: 60)])
        #expect(outbox.count == 2)
    }

    @Test func aFailingSubmissionDoesNotDiscardTheOthers() async throws {
        let service = FakeGameCenterService()
        let outbox = try tempOutbox()
        defer { outbox.clear() }
        outbox.add([.score(leaderboard: Leaderboard.totalPoints.rawValue, value: 1),
                    .achievement(id: Achievement.firstSolve.rawValue, percentComplete: 100)])
        service.failsSubmissions = true
        let failed = await outbox.flush(using: service)
        #expect(failed.sent == 0)
        #expect(failed.kept == 2, "eine abgelehnte Punktzahl darf die Achievements nicht mitnehmen")

        service.failsSubmissions = false
        let ok = await outbox.flush(using: service)
        #expect(ok.sent == 2)
        #expect(ok.kept == 0)
    }

    @Test func outboxSurvivesRestart() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kreuzwort-persist-\(UInt32.random(in: 1 ... .max))")
        let first = try SubmissionOutbox(directory: dir)
        first.add([.score(leaderboard: Leaderboard.dailyPoints.rawValue, value: 42)])
        // Ein Spieler kann tagelang offline bleiben — der Puffer muss App-Starts
        // überleben.
        let second = try SubmissionOutbox(directory: dir)
        #expect(second.count == 1)
        second.clear()
    }

    @Test func outboxRespectsItsLimit() throws {
        let outbox = try tempOutbox(limit: 3)
        defer { outbox.clear() }
        for i in 0 ..< 10 {
            outbox.add([.achievement(id: Achievement.allCases[i % Achievement.allCases.count]
                .rawValue, percentComplete: Double(i))])
        }
        #expect(outbox.count <= 3)
    }

    @Test func coordinatorSubmitsPointsAndChangedAchievements() async throws {
        let service = FakeGameCenterService()
        let outbox = try tempOutbox()
        defer { outbox.clear() }
        let coordinator = GameCenterCoordinator(service: service, outbox: outbox, deviceID: 1)

        let result = await coordinator.record(completion(), profile: PlayerProfile(),
                                              today: 20_000)
        let profile = result.profile
        let changed = result.changed

        #expect(profile.solved.total == 1)
        #expect(profile.points.total == 250)
        #expect(changed.contains { $0.achievement == .firstSolve })
        // Punkte-Leaderboards immer, Zeit-Leaderboard hier nicht (nicht Experte).
        let boards = service.submittedScores.map(\.0)
        #expect(boards.contains(.totalPoints))
        #expect(!boards.contains(.fastestExpertClassic))
        #expect(!service.reportedAchievements.isEmpty)
    }

    @Test func timeLeaderboardOnlyForCleanExpertRuns() async throws {
        let service = FakeGameCenterService()
        let outbox = try tempOutbox()
        defer { outbox.clear() }
        let coordinator = GameCenterCoordinator(service: service, outbox: outbox, deviceID: 1)

        // Experte, aber mit Hilfe: keine Bestzeit.
        var profile = await coordinator.record(
            completion(difficulty: .experte, hints: HintUsage(lettersRevealed: 1)),
            profile: PlayerProfile(), today: 1).profile
        #expect(!service.submittedScores.map(\.0).contains(.fastestExpertClassic))

        // Experte ohne Hilfe: jetzt schon, in Hundertstelsekunden.
        service.reset()
        profile = await coordinator.record(completion(difficulty: .experte, seconds: 1234.5),
                                           profile: profile, today: 1).profile
        _ = profile
        let time = service.submittedScores.first { $0.0 == .fastestExpertClassic }
        #expect(time?.1 == 123_450)
    }

    @Test func coordinatorWorksWithoutGameCenter() async throws {
        // Kein Punkt und kein Spielstand hängt davon ab, dass GameKit antwortet.
        let service = FakeGameCenterService(isAuthenticated: false,
                                            canPresentDashboard: false,
                                            playerDisplayName: nil)
        let outbox = try tempOutbox()
        defer { outbox.clear() }
        let coordinator = GameCenterCoordinator(service: service, outbox: outbox, deviceID: 1)

        let profile = await coordinator.record(completion(), profile: PlayerProfile(),
                                               today: 1).profile
        #expect(profile.points.total == 250, "Punkte entstehen lokal")
        #expect(await coordinator.pendingSubmissions > 0, "und warten im Puffer")
        #expect(await coordinator.canPresentDashboard == false)
    }

    @Test func reconcileReportsWhatAnotherDeviceEarned() async throws {
        // Nach einem Sync kann das Profil Achievements erfüllen, die auf diesem
        // Gerät nie erspielt wurden.
        let service = FakeGameCenterService()
        let outbox = try tempOutbox()
        defer { outbox.clear() }
        let coordinator = GameCenterCoordinator(service: service, outbox: outbox, deviceID: 1)

        var remote = PlayerProfile()
        for _ in 0 ..< 12 {
            remote.record(PlayerProfile.Completion(
                variant: .arrow, difficulty: .mittel, points: 100, hints: .none,
                elapsedSeconds: 600, answerIDs: [], isDaily: false, day: 1,
                hour: 12, platform: "pad"), device: 99)
        }
        await coordinator.reconcile(profile: remote, today: 1)
        let ids = service.reportedAchievements.map(\.achievement)
        #expect(ids.contains(.solve10))
        #expect(ids.contains(.arrowFirst))
    }
}
