import Foundation
import PuzzleKit

/// Die Leaderboards, wie sie in App Store Connect angelegt werden.
///
/// Punkte-Leaderboards sind **varianten- und plattformübergreifend**: ein
/// getrenntes Ranking je Variante würde die Punkte-Formel entwerten, die
/// bewusst keinen Varianten-Faktor hat. Nur Zeiten werden getrennt, weil eine
/// Zeit über verschiedene Rätselformen hinweg nichts aussagt.
public enum Leaderboard: String, Sendable, CaseIterable {
    case totalPoints = "total_points"
    case dailyPoints = "daily_points"
    case weeklyPoints = "weekly_points"
    case fastestExpertClassic = "fastest_expert_classic"
    case fastestExpertArrow = "fastest_expert_arrow"

    /// Zeit-Leaderboards werden in Hundertstelsekunden gemeldet und aufsteigend
    /// gewertet; Punkte absteigend.
    public var isTime: Bool {
        self == .fastestExpertClassic || self == .fastestExpertArrow
    }

    public static func fastestExpert(for variant: PuzzleVariant) -> Leaderboard {
        variant == .classic ? .fastestExpertClassic : .fastestExpertArrow
    }
}

/// Eine noch nicht abgesetzte Meldung.
public enum Submission: Codable, Sendable, Hashable {
    case score(leaderboard: String, value: Int)
    case achievement(id: String, percentComplete: Double)
}

/// Was die App von Game Center braucht.
///
/// **Nicht blockierend, nicht vorausgesetzt.** Die App ist ohne Game Center
/// vollständig spielbar: Punkte werden lokal gezählt, Meldungen landen in der
/// Outbox und gehen ab, sobald eine Anmeldung besteht. Ein Spieler ohne
/// Apple-Account soll nicht auf einen Anmeldedialog starren.
///
/// Verfügbarkeit wird **geprüft, nicht angenommen**: `canPresentDashboard` ist
/// nicht überall wahr, und die Oberfläche fragt danach, statt einen Knopf zu
/// zeigen, der nichts tut.
public protocol GameCenterService: Sendable {
    var isAuthenticated: Bool { get }
    var canPresentDashboard: Bool { get }
    /// Anzeigename des angemeldeten Spielers, falls vorhanden.
    var playerDisplayName: String? { get }

    func authenticate() async
    func submit(score: Int, to leaderboard: Leaderboard) async throws
    func report(_ progress: [AchievementProgress]) async throws
}

/// Für Tests und für den Simulator ohne App-Store-Connect-Konfiguration.
///
/// Ohne diese Variante wäre die halbe Anbindung nur auf einem echten Gerät mit
/// eingerichteten Leaderboards prüfbar — also praktisch nie.
public final class FakeGameCenterService: GameCenterService, @unchecked Sendable {
    private let lock = NSLock()
    private var _isAuthenticated: Bool
    public var canPresentDashboard: Bool
    public var playerDisplayName: String?
    /// Wird die nächste Meldung scheitern? Für den Outbox-Test.
    public var failsSubmissions = false

    public private(set) var submittedScores: [(Leaderboard, Int)] = []
    public private(set) var reportedAchievements: [AchievementProgress] = []
    public private(set) var authenticateCalls = 0

    public init(isAuthenticated: Bool = true, canPresentDashboard: Bool = true,
                playerDisplayName: String? = "Testspieler") {
        self._isAuthenticated = isAuthenticated
        self.canPresentDashboard = canPresentDashboard
        self.playerDisplayName = playerDisplayName
    }

    public var isAuthenticated: Bool { lock.withLock { _isAuthenticated } }

    public func setAuthenticated(_ value: Bool) {
        lock.withLock { _isAuthenticated = value }
    }

    // `withLock` statt lock()/unlock(): Swift 6 verbietet das manuelle Paar in
    // asynchronen Funktionen, weil ein Suspendieren zwischen beiden Aufrufen
    // eine klassische Deadlock-Quelle ist.
    public func authenticate() async {
        lock.withLock { authenticateCalls += 1 }
    }

    public func submit(score: Int, to leaderboard: Leaderboard) async throws {
        try lock.withLock {
            guard _isAuthenticated else { throw GameCenterError.notAuthenticated }
            if failsSubmissions { throw GameCenterError.submissionFailed("Test") }
            submittedScores.append((leaderboard, score))
        }
    }

    public func report(_ progress: [AchievementProgress]) async throws {
        try lock.withLock {
            guard _isAuthenticated else { throw GameCenterError.notAuthenticated }
            if failsSubmissions { throw GameCenterError.submissionFailed("Test") }
            reportedAchievements += progress
        }
    }

    public func reset() {
        lock.withLock {
            submittedScores = []
            reportedAchievements = []
            authenticateCalls = 0
        }
    }
}

public enum GameCenterError: Error, Sendable, CustomStringConvertible {
    case notAuthenticated
    case unavailable
    case submissionFailed(String)

    public var description: String {
        switch self {
        case .notAuthenticated: "Nicht bei Game Center angemeldet"
        case .unavailable: "Game Center ist auf dieser Plattform nicht verfügbar"
        case .submissionFailed(let why): "Meldung fehlgeschlagen: \(why)"
        }
    }
}
