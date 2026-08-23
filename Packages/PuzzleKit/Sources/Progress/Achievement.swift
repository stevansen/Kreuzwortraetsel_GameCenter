/// Ein Achievement, wie es in App Store Connect angelegt wird.
///
/// Die Kennungen sind hier **festgeschrieben**: sie müssen mit den in App Store
/// Connect angelegten übereinstimmen und lassen sich nachträglich nicht
/// umbenennen, ohne den Fortschritt aller Spieler zu verlieren.
public enum Achievement: String, Sendable, CaseIterable, Codable {
    case firstSolve = "first_solve"
    case solve10 = "solve_10"
    case solve100 = "solve_100"
    case solve1000 = "solve_1000"
    case arrowFirst = "arrow_first"
    case arrow100 = "arrow_100"
    case classic100 = "classic_100"
    case ambidextrous = "ambidextrous"
    case allDifficulties = "all_difficulties"
    case bentArrows = "bent_arrows"
    case expertClean = "expert_clean"
    case speedrunMittel = "speedrun_mittel"
    case streak7 = "streak_7"
    case streak30 = "streak_30"
    case streak365 = "streak_365"
    case flawless25 = "flawless_25"
    case vocab5000 = "vocab_5000"
    case nightOwl = "night_owl"
    case earlyBird = "early_bird"
    case comeback = "comeback"
    case points100k = "points_100k"
    case onTheBigScreen = "on_the_big_screen"

    /// Zielwert für inkrementelle Achievements, `1` für einmalige.
    public var target: Int {
        switch self {
        case .firstSolve, .arrowFirst, .ambidextrous, .allDifficulties, .bentArrows,
             .expertClean, .speedrunMittel, .nightOwl, .earlyBird, .comeback,
             .onTheBigScreen:
            1
        case .solve10: 10
        case .solve100, .arrow100, .classic100: 100
        case .solve1000: 1000
        case .streak7: 7
        case .streak30: 30
        case .streak365: 365
        case .flawless25: 25
        case .vocab5000: 5000
        case .points100k: 100_000
        }
    }
}

/// Ein gemeldeter Fortschritt.
public struct AchievementProgress: Sendable, Hashable {
    public let achievement: Achievement
    /// Erreichter Wert, ungeklemmt — der Aufrufer sieht, wie weit es ist.
    public let value: Int
    public let target: Int

    public init(achievement: Achievement, value: Int, target: Int) {
        self.achievement = achievement
        self.value = value
        self.target = target
    }

    /// 0…100 für GameKit.
    public var percentComplete: Double {
        guard target > 0 else { return 0 }
        return min(100, Double(value) / Double(target) * 100)
    }

    public var isComplete: Bool { value >= target }
}

/// Leitet den Achievement-Fortschritt aus dem Profil ab.
///
/// Bewusst **berechnet statt gespeichert**: das Profil hält die Rohzahlen, und
/// daraus folgt jeder Fortschritt eindeutig. Achievement-Zustände zusätzlich zu
/// speichern hieße, zwei Wahrheiten zu pflegen, die auseinanderlaufen können —
/// und genau das ist der Grund, warum Game Center nicht die Quelle ist.
public enum AchievementEvaluator {
    public static func progress(for profile: PlayerProfile,
                                today: Int) -> [AchievementProgress] {
        func make(_ achievement: Achievement, _ value: Int) -> AchievementProgress {
            AchievementProgress(achievement: achievement, value: value,
                                target: achievement.target)
        }
        func flag(_ achievement: Achievement, _ condition: Bool) -> AchievementProgress {
            make(achievement, condition ? 1 : 0)
        }

        let solved = profile.solved.total
        let arrow = profile.solvedByVariant[PuzzleVariant.arrow.rawValue]?.total ?? 0
        let classic = profile.solvedByVariant[PuzzleVariant.classic.rawValue]?.total ?? 0
        let streak = profile.currentStreak(today: today)
        // Für die Serien-Achievements zählt der **beste** Lauf: eine erreichte
        // Auszeichnung darf nicht verschwinden, weil die Serie später reißt.
        let bestStreak = max(streak, profile.bestStreak)
        let allDifficulties = Difficulty.allCases.allSatisfy {
            (profile.solvedByDifficulty[$0.rawValue]?.total ?? 0) > 0
        }

        return [
            make(.firstSolve, min(solved, 1)),
            make(.solve10, solved),
            make(.solve100, solved),
            make(.solve1000, solved),
            flag(.arrowFirst, arrow > 0),
            make(.arrow100, arrow),
            make(.classic100, classic),
            flag(.ambidextrous, !profile.ambidextrousDays.isEmpty),
            flag(.allDifficulties, allDifficulties),
            flag(.bentArrows,
                 (profile.expertClean[PuzzleVariant.arrow.rawValue]?.total ?? 0) > 0),
            flag(.expertClean,
                 (profile.expertClean[PuzzleVariant.classic.rawValue]?.total ?? 0) > 0),
            flag(.speedrunMittel, profile.speedruns.total > 0),
            make(.streak7, bestStreak),
            make(.streak30, bestStreak),
            make(.streak365, bestStreak),
            make(.flawless25, profile.flawless.total),
            make(.vocab5000, profile.seenAnswers.count),
            flag(.nightOwl, profile.solvedAtNight),
            flag(.earlyBird, profile.solvedAtDawn),
            flag(.comeback, profile.madeComeback),
            make(.points100k, profile.points.total),
            flag(.onTheBigScreen, profile.platforms.contains("tv")),
        ]
    }

    /// Nur was sich gegenüber einem vorigen Stand geändert hat.
    ///
    /// GameKit nimmt Wiederholungen hin, aber jede Meldung ist ein Netzaufruf.
    /// Bei 22 Achievements nach jedem gelösten Rätsel wären das 22 überflüssige.
    public static func changed(from previous: [AchievementProgress],
                              to current: [AchievementProgress]) -> [AchievementProgress] {
        var before: [Achievement: Int] = [:]
        for item in previous { before[item.achievement] = item.value }
        return current.filter { before[$0.achievement] != $0.value }
    }
}
