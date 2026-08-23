import Testing
// Foundation ist nur im **Test** erlaubt: die Quellen von PuzzleKit müssen ohne
// auskommen (ein Seam-Scan prüft das), der Codable-Rundlauf braucht es aber.
import Foundation
@testable import PuzzleKit

@Suite("Spielerprofil")
struct ProfileTests {
    private func completion(variant: PuzzleVariant = .classic,
                            difficulty: Difficulty = .mittel,
                            points: Int = 250, hints: HintUsage = .none,
                            seconds: Double = 600, answers: [Int32] = [1, 2, 3],
                            daily: Bool = false, day: Int = 20_000,
                            hour: Int = 12, platform: String = "phone")
        -> PlayerProfile.Completion {
        PlayerProfile.Completion(variant: variant, difficulty: difficulty, points: points,
                                 hints: hints, elapsedSeconds: seconds, answerIDs: answers,
                                 isDaily: daily, day: day, hour: hour, platform: platform)
    }

    @Test func growOnlyCounterSumsPerDevice() {
        var a = GrowOnlyCounter()
        a.increment(3, device: 1)
        var b = GrowOnlyCounter()
        b.increment(5, device: 2)
        // Genau der Fall, den ein Skalar falsch macht: zwei Geräte erhöhen
        // unabhängig, die Summe muss beides enthalten.
        #expect(GrowOnlyCounter.merged(a, b).total == 8)
        #expect(GrowOnlyCounter.merged(a, b).total == GrowOnlyCounter.merged(b, a).total)
        #expect(GrowOnlyCounter.merged(a, a).total == 3)
    }

    @Test func mergeIsCommutativeAndIdempotent() {
        var a = PlayerProfile()
        a.record(completion(variant: .classic, points: 100, answers: [1, 2]), device: 1)
        var b = PlayerProfile()
        b.record(completion(variant: .arrow, points: 200, answers: [2, 3]), device: 2)

        let ab = PlayerProfile.merged(a, b)
        let ba = PlayerProfile.merged(b, a)
        #expect(ab.solved.total == ba.solved.total)
        #expect(ab.solved.total == 2)
        #expect(ab.points.total == 300)
        #expect(ab.seenAnswers == Set<Int32>([1, 2, 3]))
        // Idempotenz: nochmal mergen ändert nichts.
        #expect(PlayerProfile.merged(ab, b).points.total == 300)
    }

    @Test func streakCountsConsecutiveDaysAndToleratesToday() {
        var p = PlayerProfile()
        for day in [100, 101, 102] { p.record(completion(daily: true, day: day), device: 1) }
        #expect(p.currentStreak(today: 102) == 3)
        // Heute noch nicht gespielt: die Serie darf nicht um Mitternacht reißen.
        #expect(p.currentStreak(today: 103) == 3)
        // Zwei Tage Pause: gerissen.
        #expect(p.currentStreak(today: 104) == 0)
        #expect(p.bestStreak == 3)
    }

    @Test func streakIgnoresGaps() {
        var p = PlayerProfile()
        for day in [10, 11, 20, 21, 22, 23] {
            p.record(completion(daily: true, day: day), device: 1)
        }
        #expect(p.currentStreak(today: 23) == 4)
        #expect(p.bestStreak == 4)
    }

    @Test func sameDayFromTwoDevicesCountsOnce() {
        // Der Grund, warum die Serie aus einer Menge von Tagen berechnet wird
        // und nicht als Zähler geführt: sonst würde derselbe Tag doppelt zählen.
        var phone = PlayerProfile()
        phone.record(completion(daily: true, day: 50), device: 1)
        var pad = PlayerProfile()
        pad.record(completion(daily: true, day: 50), device: 2)
        let merged = PlayerProfile.merged(phone, pad)
        #expect(merged.dailyDays == Set([50]))
        #expect(merged.currentStreak(today: 50) == 1)
        // Die Lösungen selbst zählen dagegen beide.
        #expect(merged.solved.total == 2)
    }

    @Test func comebackNeedsThirtyDaysAway() {
        var p = PlayerProfile()
        p.record(completion(daily: true, day: 100), device: 1)
        p.record(completion(daily: true, day: 120), device: 1)
        #expect(!p.madeComeback)
        p.record(completion(daily: true, day: 160), device: 1)
        #expect(p.madeComeback)
    }

    @Test func timeOfDayMarks() {
        var night = PlayerProfile()
        night.record(completion(hour: 2), device: 1)
        #expect(night.solvedAtNight)
        #expect(!night.solvedAtDawn)

        var dawn = PlayerProfile()
        dawn.record(completion(hour: 5), device: 1)
        #expect(dawn.solvedAtDawn)
        #expect(!dawn.solvedAtNight)

        var day = PlayerProfile()
        day.record(completion(hour: 14), device: 1)
        #expect(!day.solvedAtNight && !day.solvedAtDawn)
    }

    @Test func cleanAndSpeedrunConditions() {
        var p = PlayerProfile()
        // Mit Hilfe: weder fehlerfrei noch Speedrun.
        p.record(completion(difficulty: .mittel, hints: HintUsage(lettersRevealed: 1),
                            seconds: 100), device: 1)
        #expect(p.flawless.total == 0)
        #expect(p.speedruns.total == 0)

        // Ohne Hilfe und unter vier Minuten.
        p.record(completion(difficulty: .mittel, seconds: 200), device: 1)
        #expect(p.flawless.total == 1)
        #expect(p.speedruns.total == 1)

        // Experte ohne Hilfe zählt getrennt je Variante.
        p.record(completion(variant: .arrow, difficulty: .experte, seconds: 3000), device: 1)
        #expect(p.expertClean[PuzzleVariant.arrow.rawValue]?.total == 1)
        #expect(p.expertClean[PuzzleVariant.classic.rawValue] == nil)
    }

    @Test func codableRoundTrip() throws {
        var p = PlayerProfile()
        p.record(completion(answers: [7, 8, 9], daily: true), device: 42)
        p.recordBothVariants(onDay: 20_000)
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(PlayerProfile.self, from: data)
        #expect(back.points.total == p.points.total)
        #expect(back.seenAnswers == p.seenAnswers)
        #expect(back.ambidextrousDays == p.ambidextrousDays)
    }
}

@Suite("Achievements")
struct AchievementTests {
    private func profile(solved: Int = 0, arrow: Int = 0, points: Int = 0,
                         days: [Int] = [], answers: Int = 0) -> PlayerProfile {
        var p = PlayerProfile()
        for i in 0 ..< solved {
            p.record(PlayerProfile.Completion(
                variant: i < arrow ? .arrow : .classic, difficulty: .mittel,
                points: points / max(solved, 1), hints: .none, elapsedSeconds: 600,
                answerIDs: (0 ..< answers).map { Int32($0) }, isDaily: false,
                day: 20_000, hour: 12, platform: "phone"), device: 1)
        }
        for day in days {
            p.record(PlayerProfile.Completion(
                variant: .classic, difficulty: .mittel, points: 0, hints: .none,
                elapsedSeconds: 600, answerIDs: [], isDaily: true, day: day,
                hour: 12, platform: "phone"), device: 1)
        }
        return p
    }

    @Test func everyAchievementHasAPositiveTarget() {
        for achievement in Achievement.allCases {
            #expect(achievement.target >= 1, Comment(rawValue: achievement.rawValue))
        }
        #expect(Achievement.allCases.count == 22)
    }

    @Test func identifiersAreUnique() {
        // Doppelte Kennungen wären in App Store Connect nicht anlegbar und hier
        // still falsch.
        #expect(Set(Achievement.allCases.map(\.rawValue)).count
            == Achievement.allCases.count)
    }

    @Test func progressReflectsTheProfile() {
        let p = profile(solved: 12, arrow: 5, points: 1200, answers: 3)
        let progress = AchievementEvaluator.progress(for: p, today: 20_000)
        func value(_ a: Achievement) -> Int {
            progress.first { $0.achievement == a }?.value ?? -1
        }
        #expect(value(.firstSolve) == 1)
        #expect(value(.solve10) == 12)
        #expect(value(.arrowFirst) == 1)
        #expect(value(.arrow100) == 5)
        #expect(value(.classic100) == 7)

        let first = progress.first { $0.achievement == .firstSolve }!
        #expect(first.isComplete)
        #expect(first.percentComplete == 100)
        let hundred = progress.first { $0.achievement == .solve100 }!
        #expect(!hundred.isComplete)
        #expect(hundred.percentComplete == 12)
    }

    @Test func percentIsCappedAtHundred() {
        let p = profile(solved: 150)
        let progress = AchievementEvaluator.progress(for: p, today: 20_000)
        for item in progress { #expect(item.percentComplete <= 100) }
    }

    @Test func streakAchievementsUseTheBestRun() {
        // Eine erreichte Auszeichnung darf nicht verschwinden, weil die Serie
        // später reißt.
        var p = profile(days: Array(100 ..< 110))
        p.record(PlayerProfile.Completion(
            variant: .classic, difficulty: .mittel, points: 0, hints: .none,
            elapsedSeconds: 600, answerIDs: [], isDaily: true, day: 200,
            hour: 12, platform: "phone"), device: 1)
        let progress = AchievementEvaluator.progress(for: p, today: 200)
        let streak7 = progress.first { $0.achievement == .streak7 }!
        #expect(p.currentStreak(today: 200) == 1)
        #expect(streak7.isComplete, "beste Serie war 10 — das bleibt erreicht")
    }

    @Test func allDifficultiesNeedsAllFour() {
        var p = PlayerProfile()
        for difficulty in Difficulty.allCases.dropLast() {
            p.record(PlayerProfile.Completion(
                variant: .classic, difficulty: difficulty, points: 0, hints: .none,
                elapsedSeconds: 600, answerIDs: [], isDaily: false, day: 1,
                hour: 12, platform: "phone"), device: 1)
        }
        var progress = AchievementEvaluator.progress(for: p, today: 1)
        #expect(!progress.first { $0.achievement == .allDifficulties }!.isComplete)

        p.record(PlayerProfile.Completion(
            variant: .classic, difficulty: .experte, points: 0, hints: .none,
            elapsedSeconds: 600, answerIDs: [], isDaily: false, day: 1,
            hour: 12, platform: "phone"), device: 1)
        progress = AchievementEvaluator.progress(for: p, today: 1)
        #expect(progress.first { $0.achievement == .allDifficulties }!.isComplete)
    }

    @Test func onlyChangedProgressIsReported() {
        // 22 Achievements nach jedem Rätsel zu melden wären 22 Netzaufrufe für
        // meist eine Änderung.
        let before = AchievementEvaluator.progress(for: profile(solved: 5), today: 1)
        let after = AchievementEvaluator.progress(for: profile(solved: 6), today: 1)
        let changed = AchievementEvaluator.changed(from: before, to: after)
        #expect(!changed.isEmpty)
        #expect(changed.count < Achievement.allCases.count)
        #expect(AchievementEvaluator.changed(from: after, to: after).isEmpty)
    }
}
