import Foundation

public enum DownloadReservationError: Error, Sendable {
    case duplicate
}

public protocol DownloadRepository: Sendable {
    /// Reserves a durable queued attempt. Throws `DownloadReservationError.duplicate` when an
    /// active reservation already owns the content and quality, or a storage error on failure.
    func reserve(_ request: DownloadRequest) async throws -> DownloadTask

    /// Atomically replaces a record only while its revision and attempt match both guards.
    /// Returns `false` for a rejected write; persistence failures throw instead.
    func commit(_ task: DownloadTask, expectedRevision: UInt64, expectedAttempt: UUID) async throws
        -> Bool

    /// Returns the durable record, or `nil` when it has been removed. Storage failures throw.
    func task(_ id: UUID) async throws -> DownloadTask?

    /// Returns a complete snapshot ordered by creation time, newest first, then descending task ID.
    func all() async throws -> [DownloadTask]

    /// Removes only the matching record, preserving its media file. Returns `false` when the
    /// record no longer matches either guard; persistence failures throw instead.
    func remove(_ id: UUID, expectedRevision: UInt64, expectedAttempt: UUID) async throws -> Bool
}
