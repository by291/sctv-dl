import GRDB

public struct CacheMaintenance: Sendable {
    private let database: DatabaseQueue
    public init(database: DatabaseQueue) { self.database = database }

    public func clearProgrammeCache() async throws {
        try await database.write { db in
            // Accepted in-memory pages stay usable; only disposable persistent snapshots are removed.
            try db.execute(sql: "DELETE FROM programme_snapshots")
        }
    }
}
