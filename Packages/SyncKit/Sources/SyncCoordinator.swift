import Foundation
import PuzzleKit

/// Bindet die lokalen Speicher an ein Backend.
///
/// **Offline zuerst.** Die lokalen Speicher sind die Wahrheit; der Sync ist ein
/// Anhang, der ausfallen darf. Nichts in der App wartet auf ihn, und eine
/// gescheiterte Übertragung verliert keine Daten — sie bleibt in `pending`.
///
/// **Zusammengeführt wird lokal.** Weder CloudKit noch irgendein Backend
/// entscheidet, welche Fassung gewinnt: `PuzzleProgress.merged` und
/// `PlayerProfile.merged` tun das, und beide sind kommutativ und idempotent.
/// Deshalb ist die Reihenfolge, in der Geräte sich melden, ohne Bedeutung — der
/// Fehler, den ein Nutzer sofort bemerkt und nicht verzeiht.
public actor SyncCoordinator {
    private let backend: any SyncBackend
    private let progressStore: ProgressStore
    private let profileStore: ProfileStore
    private let deviceID: UInt32
    /// Datensätze, die noch nicht hochgeladen werden konnten.
    private var pending: [String: SyncRecord] = [:]

    public init(backend: any SyncBackend, progressStore: ProgressStore,
                profileStore: ProfileStore, deviceID: UInt32) {
        self.backend = backend
        self.progressStore = progressStore
        self.profileStore = profileStore
        self.deviceID = deviceID
    }

    public var isAvailable: Bool { backend.isAvailable }
    public var pendingCount: Int { pending.count }

    public func start() async {
        await backend.start()
    }

    // MARK: - Hochladen

    /// Merkt einen Spielstand für den Upload vor und versucht ihn abzusetzen.
    ///
    /// Vormerken **und** absetzen in einem Schritt, weil der Aufrufer sich nicht
    /// darum kümmern soll, ob gerade Netz da ist.
    public func push(progress: PuzzleProgress) async {
        guard let record = try? SyncRecord.progress(progress, deviceID: deviceID) else { return }
        // Je Rätsel bleibt nur der neueste Stand — ältere sind entbehrlich, weil
        // der Spielstand kumulativ ist.
        pending["\(record.kind.rawValue):\(record.id)"] = record
        await flush()
    }

    public func push(profile: PlayerProfile) async {
        guard let record = try? SyncRecord.profile(profile, deviceID: deviceID) else { return }
        pending["\(record.kind.rawValue):\(record.id)"] = record
        await flush()
    }

    @discardableResult
    public func flush(retriesOnConflict: Int = 1) async -> (sent: Int, kept: Int) {
        guard backend.isAvailable, !pending.isEmpty else { return (0, pending.count) }
        let work = pending
        do {
            try await backend.upload(Array(work.values))
            for key in work.keys { pending.removeValue(forKey: key) }
            return (work.count, pending.count)
        } catch SyncError.conflict(let remote) where retriesOnConflict > 0 {
            // Der Server ist weiter. Fremden Stand lokal zusammenführen, aus dem
            // Speicher neu verpacken und einmal erneut senden. Das ist der
            // gesamte Konfliktfall — es gibt keinen, in dem etwas verworfen wird,
            // weil beide Merges konfliktfrei sind.
            await ingest(remote)
            repackPending()
            return await flush(retriesOnConflict: retriesOnConflict - 1)
        } catch {
            // Nichts verwerfen: der nächste Versuch nimmt es mit.
            return (0, pending.count)
        }
    }

    /// Verpackt die vorgemerkten Datensätze aus dem **aktuellen** Speicherstand
    /// neu — nach einem Merge ist der eingereihte Schnappschuss veraltet.
    private func repackPending() {
        for (key, record) in pending {
            switch record.kind {
            case .progress:
                if let stored = progressStore.load(puzzleID: record.id),
                   let fresh = try? SyncRecord.progress(stored, deviceID: deviceID) {
                    pending[key] = fresh
                }
            case .profile:
                if let fresh = try? SyncRecord.profile(profileStore.load(),
                                                       deviceID: deviceID) {
                    pending[key] = fresh
                }
            case .settings:
                break
            }
        }
    }

    // MARK: - Herunterladen

    public struct FetchResult: Sendable {
        public var mergedProgress: [String] = []
        public var mergedProfile = false
        public var skipped = 0
    }

    /// Holt fremde Änderungen und führt sie in die lokalen Speicher ein.
    @discardableResult
    public func fetch() async throws -> FetchResult {
        guard backend.isAvailable else { throw SyncError.unavailable }
        var result = FetchResult()

        let downloaded = try await backend.downloadChanges()
        result = await ingest(downloaded)
        return result
    }

    /// Führt fremde Datensätze in die lokalen Speicher ein.
    @discardableResult
    private func ingest(_ records: [SyncRecord]) async -> FetchResult {
        var result = FetchResult()
        for record in records {
            switch record.kind {
            case .progress:
                guard let incoming = try? record.decodeProgress() else {
                    result.skipped += 1; continue
                }
                _ = try? progressStore.merge(incoming)
                result.mergedProgress.append(incoming.puzzleID)

            case .profile:
                guard let incoming = try? record.decodeProfile() else {
                    result.skipped += 1; continue
                }
                _ = try? profileStore.merge(incoming)
                result.mergedProfile = true

            case .settings:
                // Einstellungen folgen; ein unbekannter Typ darf den Lauf nicht
                // abbrechen, sonst blockiert eine neuere App-Version die ältere.
                result.skipped += 1
            }
        }
        return result
    }

    /// Ein Durchlauf: hochladen was liegt, dann holen was fehlt.
    @discardableResult
    public func synchronize() async -> FetchResult {
        await flush()
        return (try? await fetch()) ?? FetchResult()
    }
}
