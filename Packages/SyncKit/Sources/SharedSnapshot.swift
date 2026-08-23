import Foundation
import PuzzleKit

/// Der kleine Datenstand, den ein Widget anzeigt.
///
/// Bewusst **eine flache Momentaufnahme** und nicht der Zugriff auf Katalog und
/// Speicher: ein Widget hat wenig Zeit, wenig Speicher und darf keine 43 MB
/// Katalogdatei öffnen. Die App schreibt beim Beenden und nach jedem Abschluss,
/// das Widget liest nur.
public struct SharedSnapshot: Codable, Sendable, Equatable {
    public var points: Int
    public var solved: Int
    public var streak: Int
    /// Wurde das Tagesrätsel heute schon gelöst? Nach Variante.
    public var dailyDone: [String: Bool]
    /// Angefangenes Rätsel, falls es eines gibt.
    public var resumeVariant: String?
    public var resumeDifficulty: String?
    public var resumeCompletion: Double?
    /// Sekunden seit Epoche — nur zur Anzeige von „Stand von …".
    public var updatedAtEpoch: Double

    public init(points: Int = 0, solved: Int = 0, streak: Int = 0,
                dailyDone: [String: Bool] = [:], resumeVariant: String? = nil,
                resumeDifficulty: String? = nil, resumeCompletion: Double? = nil,
                updatedAtEpoch: Double = 0) {
        self.points = points
        self.solved = solved
        self.streak = streak
        self.dailyDone = dailyDone
        self.resumeVariant = resumeVariant
        self.resumeDifficulty = resumeDifficulty
        self.resumeCompletion = resumeCompletion
        self.updatedAtEpoch = updatedAtEpoch
    }

    public static let empty = SharedSnapshot()
}

/// Liest und schreibt die Momentaufnahme an einem Ort, den App und Widget teilen.
///
/// **Zur App Group.** Ein Widget läuft in einem eigenen Container und kommt an
/// die Daten der App nur über eine App Group — und die braucht ein bezahltes
/// Entwicklerkonto und ein Provisioning-Profil. Ohne konfigurierte Gruppe fällt
/// der Speicher auf den eigenen Container zurück: die App funktioniert dann
/// vollständig, das Widget zeigt nur nichts. Das ist der ehrlichere Ausgang als
/// ein Absturz.
public final class SharedSnapshotStore: @unchecked Sendable {
    public let url: URL
    /// Wurde ein geteilter Ort verwendet?
    ///
    /// **Kein verlässliches Signal auf macOS.** Dort lässt sich der Pfad unter
    /// `~/Library/Group Containers/` auch ohne Entitlement anlegen, eine
    /// erfundene Gruppe sieht also aus wie eine bereitgestellte. Auf iOS gibt
    /// `containerURL(forSecurityApplicationGroupIdentifier:)` ohne Entitlement
    /// `nil` zurück und die Auskunft stimmt. Verlassen sollte sich darauf
    /// niemand — die Zusage dieses Typs ist, dass Lesen und Schreiben *immer*
    /// funktionieren, notfalls im eigenen Container.
    public let isShared: Bool
    private let lock = NSLock()

    public init(appGroupIdentifier: String? = "group.com.kreuzwort",
                directory: URL? = nil) throws {
        if let directory {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            url = directory.appendingPathComponent("snapshot.json")
            isShared = false
            return
        }
        // Nur fragen genügt nicht: auf macOS liefert
        // `containerURL(forSecurityApplicationGroupIdentifier:)` auch für eine
        // **nicht bereitgestellte** Gruppe eine URL — der Pfad wird konstruiert,
        // das Verzeichnis existiert nicht, und erst das Schreiben scheitert.
        // Deshalb wird die Benutzbarkeit geprüft, nicht die Auskunft.
        if let appGroupIdentifier,
           let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier),
           (try? FileManager.default.createDirectory(at: container,
                                                     withIntermediateDirectories: false))
            != nil || FileManager.default.fileExists(atPath: container.path) {
            url = container.appendingPathComponent("snapshot.json")
            isShared = true
            return
        }
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("Kreuzwort")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("snapshot.json")
        isShared = false
    }

    public func read() -> SharedSnapshot {
        lock.withLock {
            guard let data = try? Data(contentsOf: url),
                  let snapshot = try? JSONDecoder().decode(SharedSnapshot.self, from: data)
            else { return .empty }
            return snapshot
        }
    }

    public func write(_ snapshot: SharedSnapshot) throws {
        try lock.withLock {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: .atomic)
        }
    }

    /// Baut die Momentaufnahme aus Profil und Spielstand.
    public func update(profile: PlayerProfile, today: Int,
                       resumable: PuzzleProgress?, letterCells: Int,
                       now: Double) throws {
        var snapshot = SharedSnapshot(
            points: profile.points.total,
            solved: profile.solved.total,
            streak: profile.currentStreak(today: today),
            dailyDone: [:],
            updatedAtEpoch: now)
        // Ob das Tagesrätsel erledigt ist, steht im Profil nur pauschal — die
        // Variante kommt aus den Tagesmengen, die der Aufrufer pflegt.
        snapshot.dailyDone = [
            PuzzleVariant.classic.rawValue: profile.dailyDays.contains(today),
            PuzzleVariant.arrow.rawValue: profile.dailyDays.contains(today),
        ]
        if let resumable {
            snapshot.resumeVariant = resumable.variant.rawValue
            snapshot.resumeDifficulty = resumable.difficulty.rawValue
            snapshot.resumeCompletion = resumable.completion(
                letterCells: max(letterCells, 1))
        }
        try write(snapshot)
    }
}
