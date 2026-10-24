import Foundation
import GRDB
import SCTVCore

public actor SQLiteDownloadRepository: DownloadRepository {
    private let database: DatabaseQueue

    public init(database: DatabaseQueue) { self.database = database }

    public func reserve(_ request: DownloadRequest) throws -> DownloadTask {
        let task = DownloadTask(
            id: UUID(), attemptID: UUID(), revision: 0, content: request.content,
            programmeName: request.programmeName, broadcastDate: request.broadcastDate,
            title: request.title, cover: request.cover, quality: request.source.quality,
            source: DownloadSource(request.source), filename: request.filename,
            allowsCellular: request.allowsCellular, destination: request.destination,
            nativeID: nil, state: .queued, createdAt: Date())
        let payload = try JSONEncoder().encode(task)
        do {
            try database.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO download_tasks (task_id, attempt_id, programme_id, date_id, content_id,
                            quality, state, payload, updated_at, revision)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        task.id.uuidString, task.attemptID.uuidString, task.content.programmeID,
                        task.content.dateID, task.content.contentID, task.quality.rawValue,
                        task.state.storageKey, payload, task.createdAt.timeIntervalSince1970,
                        Int64(task.revision),
                    ])
            }
        } catch let error as DatabaseError where error.resultCode == .SQLITE_CONSTRAINT {
            throw DownloadReservationError.duplicate
        }
        return task
    }

    public func commit(_ task: DownloadTask, expectedRevision: UInt64, expectedAttempt: UUID) throws
        -> Bool
    {
        guard expectedRevision <= UInt64(Int64.max), task.revision <= UInt64(Int64.max) else {
            return false
        }
        let payload = try JSONEncoder().encode(task)
        return try database.write { db in
            try db.execute(
                sql: """
                    UPDATE download_tasks SET attempt_id = ?, state = ?, payload = ?, updated_at = ?,
                        revision = ?, native_session = ?, native_task_id = ?, relative_path = ?
                    WHERE task_id = ? AND revision = ? AND attempt_id = ?
                    """,
                arguments: [
                    task.attemptID.uuidString, task.state.storageKey, payload,
                    Date().timeIntervalSince1970,
                    Int64(task.revision), task.nativeID?.session, task.nativeID?.task,
                    Self.relativePath(task.state), task.id.uuidString,
                    Int64(expectedRevision), expectedAttempt.uuidString,
                ])
            guard db.changesCount == 1 else { return false }
            try db.execute(
                sql: """
                    INSERT INTO download_attempts (attempt_id, task_id, system_task_id, resume_reference, staging_path, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(attempt_id) DO UPDATE SET
                        system_task_id = excluded.system_task_id,
                        resume_reference = excluded.resume_reference,
                        staging_path = excluded.staging_path,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    task.attemptID.uuidString, task.id.uuidString, task.nativeID?.task,
                    Self.resumePath(task.state), Self.stagingPath(task.state),
                    Date().timeIntervalSince1970,
                ])
            return true
        }
    }

    public func task(_ id: UUID) throws -> DownloadTask? {
        try database.read { db in
            try Data.fetchOne(
                db, sql: "SELECT payload FROM download_tasks WHERE task_id = ?",
                arguments: [id.uuidString]
            )
            .map { try JSONDecoder().decode(DownloadTask.self, from: $0) }
        }
    }

    public func all() throws -> [DownloadTask] {
        try database.read { db in
            try Data.fetchAll(db, sql: "SELECT payload FROM download_tasks")
                .map { try JSONDecoder().decode(DownloadTask.self, from: $0) }
                .sorted {
                    // Progress and retries change updated_at, but must not move existing cards.
                    if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
                    return $0.id.uuidString > $1.id.uuidString
                }
        }
    }

    public func remove(_ id: UUID, expectedRevision: UInt64, expectedAttempt: UUID) throws -> Bool {
        guard expectedRevision <= UInt64(Int64.max) else { return false }
        return try database.write { db in
            try db.execute(
                sql:
                    "DELETE FROM download_tasks WHERE task_id = ? AND revision = ? AND attempt_id = ?",
                arguments: [id.uuidString, Int64(expectedRevision), expectedAttempt.uuidString])
            return db.changesCount == 1
        }
    }

    private static func relativePath(_ state: DownloadState) -> String? {
        switch state {
        case .completed(let file), .missingFile(let file): file.relativeFilename
        default: nil
        }
    }

    private static func resumePath(_ state: DownloadState) -> String? {
        switch state {
        case .paused(let value), .transferFailed(_, let value): value?.relativePath
        default: nil
        }
    }

    private static func stagingPath(_ state: DownloadState) -> String? {
        switch state {
        case .publishing(let file), .publicationFailed(_, let file): file.relativePath
        default: nil
        }
    }
}
