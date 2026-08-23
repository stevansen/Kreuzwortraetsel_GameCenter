import Foundation
import PuzzleKit

#if canImport(CloudKit)
import CloudKit

/// CloudKit-Anbindung über `CKSyncEngine`.
///
/// **Nicht verifiziert.** CloudKit braucht ein bezahltes Entwicklerkonto, einen
/// bereitgestellten Container und die entsprechenden Entitlements. Dieser Code
/// kompiliert und folgt dem dokumentierten Ablauf, ist aber gegen echtes
/// CloudKit nie gelaufen. Alles, was sich ohne Container prüfen lässt — die
/// Zusammenführung, der Konfliktpfad, die Wiederholung — steckt im
/// `SyncCoordinator` und ist über `InMemorySyncBackend` getestet. Das ist
/// Absicht: die Logik, die falsch sein *kann*, liegt außerhalb dieser Datei.
///
/// `CKSyncEngine` statt selbstgebauter `CKOperation`-Ketten: es übernimmt
/// Change-Tokens, Batching, Wiederholungen und die Zonenverwaltung — genau die
/// Dinge, die man von Hand jahrelang falsch macht.
public final class CloudKitSyncBackend: NSObject, SyncBackend, @unchecked Sendable {
    public static let containerIdentifier = "iCloud.com.kreuzwort"
    private static let zoneName = "Kreuzwort"
    private static let recordType = "SyncRecord"

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let stateURL: URL
    private let lock = NSLock()

    private var engine: CKSyncEngine?
    private var outgoing: [CKRecord.ID: SyncRecord] = [:]
    private var downloaded: [SyncRecord] = []
    private var available = false

    public init(containerIdentifier: String = CloudKitSyncBackend.containerIdentifier,
                stateDirectory: URL? = nil) throws {
        container = CKContainer(identifier: containerIdentifier)
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        let base = try stateDirectory ?? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true).appendingPathComponent("Kreuzwort")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        stateURL = base.appendingPathComponent("cksyncengine.state")
        super.init()
    }

    public var isAvailable: Bool { lock.withLock { available } }

    public func start() async {
        // Kontostatus zuerst: ohne angemeldete iCloud gibt es nichts zu tun, und
        // die App bleibt vollständig benutzbar.
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                lock.withLock { available = false }
                return
            }
        } catch {
            lock.withLock { available = false }
            return
        }

        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: loadState(),
            delegate: self)
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        lock.withLock {
            self.engine = engine
            self.available = true
        }
    }

    public func upload(_ records: [SyncRecord]) async throws {
        guard let engine = lock.withLock({ engine }) else { throw SyncError.unavailable }
        var ids: [CKRecord.ID] = []
        lock.withLock {
            for record in records {
                let id = CKRecord.ID(recordName: "\(record.kind.rawValue)-\(record.id)",
                                     zoneID: zoneID)
                outgoing[id] = record
                ids.append(id)
            }
        }
        engine.state.add(pendingRecordZoneChanges: ids.map { .saveRecord($0) })
        // `CKSyncEngine` sendet selbst und wiederholt selbst. Ein Warten hier
        // wäre gegen die Idee der Engine — die App soll nicht auf das Netz warten.
    }

    public func downloadChanges() async throws -> [SyncRecord] {
        guard lock.withLock({ engine }) != nil else { throw SyncError.unavailable }
        return lock.withLock {
            let result = downloaded
            downloaded = []
            return result
        }
    }

    // MARK: - Zustand

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func save(state: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    // MARK: - Umwandlung

    private func makeCKRecord(from record: SyncRecord, id: CKRecord.ID) -> CKRecord {
        let ck = CKRecord(recordType: Self.recordType, recordID: id)
        ck["kind"] = record.kind.rawValue as CKRecordValue
        ck["id"] = record.id as CKRecordValue
        ck["deviceID"] = Int64(record.deviceID) as CKRecordValue
        ck["payload"] = record.payload as CKRecordValue
        return ck
    }

    private func makeSyncRecord(from ck: CKRecord) -> SyncRecord? {
        guard let kindRaw = ck["kind"] as? String,
              let kind = SyncRecord.Kind(rawValue: kindRaw),
              let id = ck["id"] as? String,
              let payload = ck["payload"] as? Data
        else { return nil }
        let device = (ck["deviceID"] as? Int64).map { UInt32(truncatingIfNeeded: $0) } ?? 0
        return SyncRecord(kind: kind, id: id, payload: payload, deviceID: device)
    }
}

extension CloudKitSyncBackend: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            save(state: update.stateSerialization)

        case .fetchedRecordZoneChanges(let changes):
            let records = changes.modifications.compactMap { makeSyncRecord(from: $0.record) }
            lock.withLock { downloaded += records }

        case .sentRecordZoneChanges(let sent):
            // Fehlgeschlagene Speicherungen erneut vormerken. `serverRecordChanged`
            // wird hier **nicht** gesondert behandelt: die Zusammenführung ist
            // konfliktfrei, also gewinnt schlicht der zuletzt hochgeladene
            // vollständige Stand, und der ist immer der zusammengeführte.
            for failed in sent.failedRecordSaves {
                let id = failed.record.recordID
                guard lock.withLock({ outgoing[id] != nil }) else { continue }
                syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            }
            lock.withLock {
                for saved in sent.savedRecords { outgoing.removeValue(forKey: saved.recordID) }
            }

        case .accountChange(let change):
            // Kontowechsel: der lokale Bestand gehört dem alten Konto. Nichts
            // löschen — die lokalen Speicher bleiben die Wahrheit dieses Geräts.
            switch change.changeType {
            case .signOut: lock.withLock { available = false }
            case .signIn, .switchAccounts: lock.withLock { available = true }
            @unknown default: break
            }

        default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            guard let record = self.lock.withLock({ self.outgoing[id] }) else { return nil }
            return self.makeCKRecord(from: record, id: id)
        }
    }
}

#else

/// Ohne CloudKit-Framework: die App läuft weiter, nur ohne Sync.
public final class CloudKitSyncBackend: SyncBackend {
    public init(containerIdentifier: String = "", stateDirectory: URL? = nil) throws {}
    public var isAvailable: Bool { false }
    public func start() async {}
    public func upload(_ records: [SyncRecord]) async throws { throw SyncError.unavailable }
    public func downloadChanges() async throws -> [SyncRecord] { [] }
}

#endif
