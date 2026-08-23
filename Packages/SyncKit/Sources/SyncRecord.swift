import Foundation
import PuzzleKit

/// Ein Datensatz, wie er über die Leitung geht.
///
/// Bewusst ein **Umschlag mit Nutzlast** statt typisierter Felder: der Sync muss
/// nicht wissen, was drinsteht, und ein neues Feld im Profil erfordert keine
/// Änderung am Backend. Die Zusammenführung passiert ohnehin lokal, weil nur
/// dort beide Fassungen vorliegen.
public struct SyncRecord: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case progress
        case profile
        case settings
    }

    public let kind: Kind
    /// Eindeutig je Art: die `puzzleID` beim Spielstand, ein fester Name beim Profil.
    public let id: String
    public let payload: Data
    /// Nur zur Diagnose und für Konfliktstatistik — die Zusammenführung braucht
    /// ihn nicht, weil alle Merges konfliktfrei sind.
    public let deviceID: UInt32

    public init(kind: Kind, id: String, payload: Data, deviceID: UInt32) {
        self.kind = kind
        self.id = id
        self.payload = payload
        self.deviceID = deviceID
    }

    public static let profileRecordID = "player-profile"

    // MARK: - Verpacken

    public static func progress(_ progress: PuzzleProgress,
                                deviceID: UInt32) throws -> SyncRecord {
        SyncRecord(kind: .progress, id: progress.puzzleID,
                   payload: try JSONEncoder().encode(progress), deviceID: deviceID)
    }

    public static func profile(_ profile: PlayerProfile,
                               deviceID: UInt32) throws -> SyncRecord {
        SyncRecord(kind: .profile, id: profileRecordID,
                   payload: try JSONEncoder().encode(profile), deviceID: deviceID)
    }

    public func decodeProgress() throws -> PuzzleProgress {
        try JSONDecoder().decode(PuzzleProgress.self, from: payload)
    }

    public func decodeProfile() throws -> PlayerProfile {
        try JSONDecoder().decode(PlayerProfile.self, from: payload)
    }
}
