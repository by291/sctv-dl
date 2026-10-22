import Foundation
import GRDB
import SCTVCore

public actor SQLiteHistoryRepository: HistoryRepository {
    private struct Context: Codable, Sendable {
        let content: ContentRef
        let programmeName: String
        let broadcastDate: String
        let title: String
        let cover: URL?
    }

    private let database: DatabaseQueue
    private var observers: [UUID: AsyncStream<[HistoryEntry]>.Continuation] = [:]

    public init(database: DatabaseQueue) { self.database = database }

    public func begin(_ request: PlaybackRequest) throws -> HistorySession {
        let context = Context(
            content: request.content, programmeName: request.programmeName,
            broadcastDate: request.broadcastDate, title: request.title, cover: request.cover)
        let payload = try JSONEncoder().encode(context)
        let token = UUID()
        let content = request.content

        return try database.write { db in
            let previous = try Row.fetchOne(
                db,
                sql:
                    "SELECT * FROM history WHERE programme_id = ? AND date_id = ? AND content_id = ?",
                arguments: [content.programmeID, content.dateID, content.contentID]
            ).map(Self.decode)
            // One token per content invalidates earlier players across repository instances as well.
            try db.execute(
                sql: """
                    INSERT INTO history_sessions (programme_id, date_id, content_id, session_id, payload, sequence)
                    VALUES (?, ?, ?, ?, ?, -1)
                    ON CONFLICT(programme_id, date_id, content_id) DO UPDATE
                    SET session_id = excluded.session_id, payload = excluded.payload, sequence = -1
                    """,
                arguments: [
                    content.programmeID, content.dateID, content.contentID, token.uuidString,
                    payload,
                ])
            return HistorySession(id: token, previous: previous)
        }
    }

    public func record(_ sample: PlaybackSnapshot, session: UUID, sequence: UInt64) throws {
        guard sample.settled, sample.positionMs >= 0, sequence <= UInt64(Int64.max) else { return }
        let changed = try database.write { db -> Bool in
            guard
                let row = try Row.fetchOne(
                    db, sql: "SELECT payload, sequence FROM history_sessions WHERE session_id = ?",
                    arguments: [session.uuidString]),
                Int64(sequence) > (row["sequence"] as Int64)
            else { return false }
            let context = try JSONDecoder().decode(Context.self, from: row["payload"])
            let content = context.content
            let last = try Double.fetchOne(db, sql: "SELECT MAX(updated_at) FROM history") ?? 0
            let timestamp = max(Date().timeIntervalSince1970, last + 0.000001)
            let duration = sample.durationMs.flatMap { $0 > 0 ? $0 : nil }
            let completed = HistoryRules.isCompleted(
                positionMs: sample.positionMs, durationMs: duration, ended: sample.ended)

            try db.execute(
                sql: """
                    INSERT INTO history (programme_id, date_id, content_id, title, programme_name, broadcast_date,
                        cover, position_ms, duration_ms, completed, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(programme_id, date_id, content_id) DO UPDATE SET
                        title = excluded.title, programme_name = excluded.programme_name,
                        broadcast_date = excluded.broadcast_date, cover = excluded.cover,
                        position_ms = excluded.position_ms, duration_ms = excluded.duration_ms,
                        completed = excluded.completed, updated_at = excluded.updated_at
                    """,
                arguments: [
                    content.programmeID, content.dateID, content.contentID, context.title,
                    context.programmeName, context.broadcastDate, context.cover?.absoluteString,
                    sample.positionMs, duration, completed, timestamp,
                ])
            try db.execute(
                sql: "UPDATE history_sessions SET sequence = ? WHERE session_id = ?",
                arguments: [Int64(sequence), session.uuidString])
            try db.execute(
                sql: """
                    DELETE FROM history_sessions WHERE (programme_id, date_id, content_id) IN
                    (SELECT programme_id, date_id, content_id FROM history ORDER BY updated_at DESC LIMIT -1 OFFSET 500)
                    """)
            try db.execute(
                sql:
                    "DELETE FROM history WHERE rowid NOT IN (SELECT rowid FROM history ORDER BY updated_at DESC LIMIT 500)"
            )
            return true
        }
        if changed { try publish() }
    }

    public func remove(_ content: ContentRef) throws {
        try database.write { db in
            let values: StatementArguments = [
                content.programmeID, content.dateID, content.contentID,
            ]
            try db.execute(
                sql:
                    "DELETE FROM history_sessions WHERE programme_id = ? AND date_id = ? AND content_id = ?",
                arguments: values)
            try db.execute(
                sql:
                    "DELETE FROM history WHERE programme_id = ? AND date_id = ? AND content_id = ?",
                arguments: values)
        }
        try publish()
    }

    public func clear() throws {
        try database.write { db in
            try db.execute(sql: "DELETE FROM history_sessions")
            try db.execute(sql: "DELETE FROM history")
        }
        try publish()
    }

    public func entries() throws -> [HistoryEntry] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM history ORDER BY updated_at DESC").map(
                Self.decode)
        }
    }

    public func updates() -> AsyncStream<[HistoryEntry]> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            observers[id] = continuation
            if let current = try? entries() { continuation.yield(current) }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(id) }
            }
        }
    }

    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }

    private func publish() throws {
        let values = try entries()
        for continuation in observers.values { continuation.yield(values) }
    }

    private static func decode(_ row: Row) throws -> HistoryEntry {
        HistoryEntry(
            content: try ContentRef(
                programmeID: row["programme_id"], dateID: row["date_id"],
                contentID: row["content_id"]),
            programmeName: row["programme_name"], broadcastDate: row["broadcast_date"],
            title: row["title"],
            cover: (row["cover"] as String?).flatMap(URL.init(string:)),
            positionMs: row["position_ms"], durationMs: row["duration_ms"],
            updatedAt: Date(timeIntervalSince1970: row["updated_at"]), completed: row["completed"])
    }
}
