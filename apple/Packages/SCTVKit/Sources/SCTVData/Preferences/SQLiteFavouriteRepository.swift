import Foundation
import GRDB
import SCTVCore

public actor SQLiteFavouriteRepository: FavouriteRepository {
    private let database: DatabaseQueue
    private var confirmedIDs: Set<String> = []
    private var desiredIDs: Set<String> = []
    private var warning: String?
    private var loaded = false
    private var observers: [UUID: AsyncStream<Set<String>>.Continuation] = [:]
    private var stateObservers: [UUID: AsyncStream<FavouriteSnapshot>.Continuation] = [:]

    public init(database: DatabaseQueue) {
        self.database = database
    }

    public func ids() throws -> Set<String> {
        try loadIfNeeded()
        return confirmedIDs
    }

    public func updates() -> AsyncStream<Set<String>> {
        try? loadIfNeeded()
        let observerID = UUID()
        return AsyncStream { continuation in
            observers[observerID] = continuation
            if loaded { continuation.yield(confirmedIDs) }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(observerID) }
            }
        }
    }

    public func stateUpdates() async -> AsyncStream<FavouriteSnapshot> {
        try? loadIfNeeded()
        let observerID = UUID()
        return AsyncStream { continuation in
            stateObservers[observerID] = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeStateObserver(observerID) }
            }
        }
    }

    public func current() -> FavouriteSnapshot {
        try? loadIfNeeded()
        return snapshot
    }

    private var snapshot: FavouriteSnapshot {
        return FavouriteSnapshot(
            confirmedIDs: confirmedIDs, desiredIDs: desiredIDs, warning: warning)
    }

    public func set(_ programmeID: String, isFavourite: Bool) throws {
        try loadIfNeeded()
        if isFavourite { desiredIDs.insert(programmeID) } else { desiredIDs.remove(programmeID) }
        publishState()

        do {
            try database.write { db in
                if isFavourite {
                    try db.execute(
                        sql:
                            "INSERT OR IGNORE INTO favourites (programme_id, created_at) VALUES (?, ?)",
                        arguments: [programmeID, Date().timeIntervalSince1970])
                } else {
                    try db.execute(
                        sql: "DELETE FROM favourites WHERE programme_id = ?",
                        arguments: [programmeID])
                }
            }
            // Only this command was committed. Other desired edits may still be awaiting retry.
            if isFavourite {
                confirmedIDs.insert(programmeID)
            } else {
                confirmedIDs.remove(programmeID)
            }
            if desiredIDs == confirmedIDs { warning = nil }
            publishConfirmed()
            publishState()
        } catch {
            let message = String(describing: error)
            if warning != message {
                warning = message
                publishState()
            }
            throw error
        }
    }

    private func loadIfNeeded() throws {
        guard !loaded else { return }
        do {
            confirmedIDs = Set(
                try database.read { db in
                    try String.fetchAll(db, sql: "SELECT programme_id FROM favourites")
                })
            desiredIDs = confirmedIDs
            loaded = true
            warning = nil
            publishConfirmed()
            publishState()
        } catch {
            warning = String(describing: error)
            publishState()
            throw error
        }
    }

    private func publishConfirmed() {
        for continuation in observers.values { continuation.yield(confirmedIDs) }
    }

    private func publishState() {
        for continuation in stateObservers.values { continuation.yield(snapshot) }
    }

    private func removeObserver(_ observerID: UUID) { observers.removeValue(forKey: observerID) }
    private func removeStateObserver(_ observerID: UUID) {
        stateObservers.removeValue(forKey: observerID)
    }
}
