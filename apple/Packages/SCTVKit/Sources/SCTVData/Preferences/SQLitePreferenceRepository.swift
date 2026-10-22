import Foundation
import GRDB
import SCTVCore

public actor SQLitePreferenceRepository: PreferenceRepository {
    private let database: DatabaseQueue
    private var snapshot = PreferenceSnapshot(
        value: Preferences(), acceptedRevision: 0, isPersisted: true, warning: nil)
    private var loaded = false
    private var observers: [UUID: AsyncStream<PreferenceSnapshot>.Continuation] = [:]

    public init(database: DatabaseQueue) {
        self.database = database
    }

    public func updates() -> AsyncStream<PreferenceSnapshot> {
        loadIfNeeded()
        let observerID = UUID()
        return AsyncStream { continuation in
            observers[observerID] = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(observerID) }
            }
        }
    }

    public func current() -> PreferenceSnapshot {
        loadIfNeeded()
        return snapshot
    }

    public func save(_ preferences: Preferences, editRevision: UInt64) throws {
        loadIfNeeded()
        guard loaded else { throw PreferenceStorageError.loadUnavailable }
        guard editRevision >= snapshot.acceptedRevision,
            editRevision != snapshot.acceptedRevision || preferences == snapshot.value
        else {
            throw PreferenceStorageError.staleEdit(
                accepted: snapshot.acceptedRevision, submitted: editRevision)
        }
        if editRevision == snapshot.acceptedRevision {
            try flush()
            return
        }
        snapshot = PreferenceSnapshot(
            value: preferences, acceptedRevision: editRevision, isPersisted: false, warning: nil)
        publish()
        try flush()
    }

    public func flush() throws {
        loadIfNeeded()
        guard loaded else { throw PreferenceStorageError.loadUnavailable }
        guard !snapshot.isPersisted else { return }
        do {
            guard snapshot.acceptedRevision <= UInt64(Int64.max) else {
                throw PreferenceStorageError.revisionOverflow
            }
            let value = String(decoding: try JSONEncoder().encode(snapshot.value), as: UTF8.self)
            let revision = Int64(snapshot.acceptedRevision)
            try database.write { db in
                try db.execute(
                    sql:
                        "INSERT INTO preferences (key, value, edit_revision) VALUES ('user', ?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value, edit_revision=excluded.edit_revision WHERE excluded.edit_revision > preferences.edit_revision",
                    arguments: [value, revision])
                let persisted = try Row.fetchOne(
                    db, sql: "SELECT value, edit_revision FROM preferences WHERE key = 'user'")
                let persistedValue: String? = persisted?["value"]
                let persistedRevision: Int64? = persisted?["edit_revision"]
                guard persistedValue == value, persistedRevision == revision else {
                    throw PreferenceStorageError.revisionConflict
                }
            }
            snapshot = PreferenceSnapshot(
                value: snapshot.value, acceptedRevision: snapshot.acceptedRevision,
                isPersisted: true, warning: nil)
            publish()
        } catch {
            snapshot = PreferenceSnapshot(
                value: snapshot.value, acceptedRevision: snapshot.acceptedRevision,
                isPersisted: false, warning: .saveFailed(String(describing: error)))
            publish()
            throw error
        }
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        do {
            let row = try database.read { db in
                try Row.fetchOne(
                    db, sql: "SELECT value, edit_revision FROM preferences WHERE key = 'user'")
            }
            if let row {
                let value: String = row["value"]
                let revision: Int64 = row["edit_revision"]
                snapshot = PreferenceSnapshot(
                    value: try JSONDecoder().decode(Preferences.self, from: Data(value.utf8)),
                    acceptedRevision: UInt64(max(0, revision)), isPersisted: true, warning: nil)
            } else {
                snapshot = PreferenceSnapshot(
                    value: Preferences(), acceptedRevision: 0, isPersisted: true, warning: nil)
            }
        } catch {
            loaded = false
            snapshot = PreferenceSnapshot(
                value: snapshot.value, acceptedRevision: snapshot.acceptedRevision,
                isPersisted: false, warning: .loadFailed(String(describing: error)))
        }
    }

    private func publish() {
        for continuation in observers.values { continuation.yield(snapshot) }
    }

    private func removeObserver(_ observerID: UUID) {
        observers.removeValue(forKey: observerID)
    }
}

public enum PreferenceStorageError: Error, Sendable {
    case loadUnavailable
    case revisionOverflow
    case staleEdit(accepted: UInt64, submitted: UInt64)
    case revisionConflict
}
