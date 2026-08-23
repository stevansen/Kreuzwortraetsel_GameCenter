import Foundation
import PuzzleKit

/// Speichert das Spielerprofil lokal.
///
/// Getrennt vom `ProgressStore`, weil beides unterschiedlich oft schreibt: der
/// Spielstand bei jedem Buchstaben, das Profil nur beim Abschluss eines Rätsels.
///
/// Beim Laden und Schreiben wird **zusammengeführt**, nicht überschrieben. Das
/// kostet hier fast nichts (alle Felder des Profils sind konfliktfrei) und ist
/// die Voraussetzung dafür, dass CloudKit später einfach hineinschreiben kann.
public final class ProfileStore: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    public init(directory: URL? = nil) throws {
        let base = try directory ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("Kreuzwort")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("profile.json")
    }

    public func load() -> PlayerProfile {
        lock.withLock {
            guard let data = try? Data(contentsOf: url),
                  let profile = try? JSONDecoder().decode(PlayerProfile.self, from: data)
            else { return PlayerProfile() }
            return profile
        }
    }

    public func save(_ profile: PlayerProfile) throws {
        try lock.withLock {
            let data = try JSONEncoder().encode(profile)
            try data.write(to: url, options: .atomic)
        }
    }

    /// Führt ein eingehendes Profil mit dem gespeicherten zusammen und gibt das
    /// Ergebnis zurück.
    @discardableResult
    public func merge(_ incoming: PlayerProfile) throws -> PlayerProfile {
        let result = PlayerProfile.merged(load(), incoming)
        try save(result)
        return result
    }
}
