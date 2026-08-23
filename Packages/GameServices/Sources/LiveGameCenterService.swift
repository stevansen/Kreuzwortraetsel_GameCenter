import Foundation
import PuzzleKit

#if canImport(GameKit)
import GameKit

/// Die echte Anbindung an GameKit.
///
/// **Verfügbarkeit wird geprüft, nicht angenommen.** `GKAccessPoint` und
/// `GKGameCenterViewController` gibt es nicht auf jeder Plattform und nicht in
/// jedem Zustand; die Oberfläche fragt `canPresentDashboard`, statt einen Knopf
/// anzubieten, der nichts tut.
///
/// **Die Anmeldung blockiert nichts.** `authenticateHandler` wird beim Start
/// gesetzt und liefert später — oder nie. Bis dahin läuft die App vollständig,
/// Meldungen sammelt die `SubmissionOutbox`.
public final class LiveGameCenterService: GameCenterService, @unchecked Sendable {
    private let lock = NSLock()
    private var authenticated = false

    public init() {}

    public var isAuthenticated: Bool {
        lock.withLock { authenticated } || GKLocalPlayer.local.isAuthenticated
    }

    public var canPresentDashboard: Bool {
        #if os(iOS) || os(tvOS) || os(macOS)
        return GKLocalPlayer.local.isAuthenticated
        #else
        return false
        #endif
    }

    public var playerDisplayName: String? {
        GKLocalPlayer.local.isAuthenticated ? GKLocalPlayer.local.displayName : nil
    }

    /// Setzt den Anmelde-Handler und wartet auf das erste Ergebnis.
    ///
    /// GameKit ruft den Handler mehrfach auf — beim Start, nach einem
    /// Kontowechsel, nach dem Aufwachen. Deshalb wird er gesetzt und nicht
    /// „einmal aufgerufen"; das `await` hier wartet nur auf die erste Antwort,
    /// damit der Aufrufer weiß, ob er sofort melden kann.
    public func authenticate() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            GKLocalPlayer.local.authenticateHandler = { [weak self] _, error in
                let ok = GKLocalPlayer.local.isAuthenticated
                self?.lock.withLock { self?.authenticated = ok }
                if let error, !ok {
                    // Kein Grund zum Abbruch: ohne Anmeldung ist die App
                    // vollständig spielbar.
                    print("Game Center: nicht angemeldet (\(error.localizedDescription))")
                }
                if !resumed { resumed = true; continuation.resume() }
            }
        }
    }

    public func submit(score: Int, to leaderboard: Leaderboard) async throws {
        guard GKLocalPlayer.local.isAuthenticated else {
            throw GameCenterError.notAuthenticated
        }
        do {
            try await GKLeaderboard.submitScore(
                score, context: 0, player: GKLocalPlayer.local,
                leaderboardIDs: [leaderboard.rawValue])
        } catch {
            throw GameCenterError.submissionFailed(error.localizedDescription)
        }
    }

    public func report(_ progress: [AchievementProgress]) async throws {
        guard GKLocalPlayer.local.isAuthenticated else {
            throw GameCenterError.notAuthenticated
        }
        guard !progress.isEmpty else { return }
        let achievements = progress.map { item -> GKAchievement in
            let achievement = GKAchievement(identifier: item.achievement.rawValue)
            achievement.percentComplete = item.percentComplete
            // Das Banner erscheint nur beim Erreichen, nicht bei jedem
            // Zwischenschritt — sonst blinkt es nach jedem gelösten Rätsel.
            achievement.showsCompletionBanner = item.isComplete
            return achievement
        }
        do {
            try await GKAchievement.report(achievements)
        } catch {
            throw GameCenterError.submissionFailed(error.localizedDescription)
        }
    }
}

#else

/// Fallback für Plattformen ohne GameKit. Die App bleibt vollständig spielbar.
public final class LiveGameCenterService: GameCenterService, @unchecked Sendable {
    public init() {}
    public var isAuthenticated: Bool { false }
    public var canPresentDashboard: Bool { false }
    public var playerDisplayName: String? { nil }
    public func authenticate() async {}
    public func submit(score: Int, to leaderboard: Leaderboard) async throws {
        throw GameCenterError.unavailable
    }
    public func report(_ progress: [AchievementProgress]) async throws {
        throw GameCenterError.unavailable
    }
}

#endif
