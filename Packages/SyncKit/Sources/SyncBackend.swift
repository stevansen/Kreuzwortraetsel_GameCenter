import Foundation
import PuzzleKit

/// Wohin synchronisiert wird.
///
/// Absichtlich schmal: hochladen, Änderungen holen, Verfügbarkeit melden. Die
/// **Zusammenführung gehört nicht hierher** — sie passiert lokal, weil nur dort
/// beide Fassungen vorliegen, und sie ist für Spielstand und Profil bereits
/// konfliktfrei gelöst.
public protocol SyncBackend: Sendable {
    var isAvailable: Bool { get }
    func start() async

    /// Lädt hoch. Wirft `SyncError.conflict`, wenn ein Datensatz sich seit dem
    /// letzten Herunterladen dieses Geräts geändert hat.
    ///
    /// **Optimistische Sperre, kein blindes Überschreiben.** Ohne sie verliert
    /// ein Gerät, das ohne vorheriges Holen hochlädt, die Daten des anderen —
    /// nicht lokal, aber in der Cloud, und damit für jedes dritte Gerät. Genau
    /// das ist CloudKits `serverRecordChanged`, und die Antwort darauf ist immer
    /// dieselbe: fremden Stand holen, lokal zusammenführen, erneut senden.
    func upload(_ records: [SyncRecord]) async throws

    /// Alles, was sich seit dem letzten Aufruf geändert hat.
    func downloadChanges() async throws -> [SyncRecord]
}

/// Kein Sync. Die App ist damit vollständig benutzbar — nur eben auf einem Gerät.
///
/// Der Prompt verlangt diese Variante ausdrücklich, und der Grund ist praktisch:
/// CloudKit braucht ein bezahltes Entwicklerkonto und einen bereitgestellten
/// Container. Ohne diesen Rückfall wäre die App in der Entwicklung nicht
/// startbar.
public struct LocalOnlySyncBackend: SyncBackend {
    public init() {}
    public var isAvailable: Bool { false }
    public func start() async {}
    public func upload(_ records: [SyncRecord]) async throws {}
    public func downloadChanges() async throws -> [SyncRecord] { [] }
}

/// Ein Backend im Speicher — für Tests, die **zwei Geräte** simulieren.
///
/// Genau das ist der Fall, der in der Praxis Arbeit vernichtet: iPhone und iPad
/// beide offline am selben Rätsel. Ohne eine Möglichkeit, das zu simulieren,
/// wäre die Merge-Logik nur in der Theorie richtig.
public final class InMemorySyncBackend: SyncBackend, @unchecked Sendable {
    /// Gemeinsame „Cloud", die mehrere Instanzen teilen können.
    public final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var records: [String: SyncRecord] = [:]
        /// Fortlaufende Nummer je Datensatz, damit jedes Gerät weiß, was neu ist.
        private var versions: [String: Int] = [:]
        private var clock = 0

        public init() {}

        func put(_ record: SyncRecord) {
            lock.withLock {
                clock += 1
                let key = "\(record.kind.rawValue):\(record.id)"
                records[key] = record
                versions[key] = clock
            }
        }

        func changes(since cursor: Int) -> (records: [SyncRecord], cursor: Int) {
            lock.withLock {
                let fresh = versions.filter { $0.value > cursor }
                    .sorted { $0.value < $1.value }
                    .compactMap { records[$0.key] }
                return (fresh, clock)
            }
        }

        func version(of key: String) -> Int { lock.withLock { versions[key] ?? 0 } }
        func record(for key: String) -> SyncRecord? { lock.withLock { records[key] } }

        public var count: Int { lock.withLock { records.count } }
    }

    private let storage: Storage
    private let lock = NSLock()
    /// Globaler Stand für das Herunterladen.
    private var cursor = 0
    /// Bekannte Version **je Datensatz**. CloudKit führt dafür einen
    /// `recordChangeTag` je `CKRecord`; eine globale Uhr wäre zu grob — nach
    /// einem Konflikt an einem Datensatz gälten sonst alle als bekannt.
    private var seen: [String: Int] = [:]
    public var isAvailable: Bool
    /// Nächster Upload schlägt fehl — für den Test des Offline-Falls.
    public var failsUploads = false

    public init(storage: Storage, isAvailable: Bool = true) {
        self.storage = storage
        self.isAvailable = isAvailable
    }

    public func start() async {}

    public func upload(_ records: [SyncRecord]) async throws {
        guard isAvailable else { throw SyncError.unavailable }
        if failsUploads { throw SyncError.uploadFailed("Test") }

        let stale: [SyncRecord] = lock.withLock {
            records.compactMap { record in
                let key = "\(record.kind.rawValue):\(record.id)"
                let serverVersion = storage.version(of: key)
                guard serverVersion > (seen[key] ?? 0) else { return nil }
                return storage.record(for: key)
            }
        }
        if !stale.isEmpty {
            // Der Aufrufer bekommt den Server-Stand mitgeliefert und weiß ihn
            // damit — sein nächster Versuch darf nicht am selben Konflikt scheitern.
            lock.withLock {
                for record in stale {
                    let key = "\(record.kind.rawValue):\(record.id)"
                    seen[key] = storage.version(of: key)
                }
            }
            throw SyncError.conflict(remote: stale)
        }

        for record in records { storage.put(record) }
        lock.withLock {
            for record in records {
                let key = "\(record.kind.rawValue):\(record.id)"
                seen[key] = storage.version(of: key)
            }
        }
    }

    public func downloadChanges() async throws -> [SyncRecord] {
        guard isAvailable else { throw SyncError.unavailable }
        let start = lock.withLock { cursor }
        let result = storage.changes(since: start)
        lock.withLock {
            cursor = result.cursor
            for record in result.records {
                let key = "\(record.kind.rawValue):\(record.id)"
                seen[key] = storage.version(of: key)
            }
        }
        return result.records
    }
}

public enum SyncError: Error, Sendable, CustomStringConvertible {
    case unavailable
    case uploadFailed(String)
    case downloadFailed(String)
    /// Der Server hat einen neueren Stand. Die mitgelieferten Datensätze sind
    /// dieser Stand — der Aufrufer führt zusammen und sendet erneut.
    case conflict(remote: [SyncRecord])

    public var description: String {
        switch self {
        case .unavailable: "Sync ist nicht verfügbar"
        case .uploadFailed(let why): "Hochladen fehlgeschlagen: \(why)"
        case .downloadFailed(let why): "Herunterladen fehlgeschlagen: \(why)"
        case .conflict(let remote): "Konflikt bei \(remote.count) Datensätzen"
        }
    }
}
