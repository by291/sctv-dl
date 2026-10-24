import Foundation

public struct DownloadSnapshot: Sendable {
    public let revision: UInt64
    public let tasks: [DownloadTask]

    public init(revision: UInt64, tasks: [DownloadTask]) {
        self.revision = revision
        self.tasks = tasks
    }
}

public protocol DownloadService: Sendable {
    /// Reserves and starts up to 100 distinct content/quality items, returning per-item failures.
    /// Accepted IDs identify durable reservations; a later transfer failure remains in the task.
    func start(_ requests: [DownloadRequest]) async -> DownloadBatchResult

    /// Applies attempt-guarded actions and reports rejected or failed items independently.
    func perform(_ commands: [DownloadCommand]) async -> DownloadBatchResult

    /// Registers an observer and loads an initial authoritative snapshot. Later snapshots replace
    /// earlier ones, and slow consumers may skip intermediate revisions. A failed storage load
    /// emits nothing; the next successful broadcast can supply the initial value.
    /// Terminating the stream removes its subscription; it does not cancel downloads.
    func updates() async -> AsyncStream<DownloadSnapshot>

    /// Subscribes to native events and recovers durable attempts, staging and file availability.
    /// Required reads and persistence errors propagate; stale guarded writes are skipped.
    /// Optional cleanup is retried later.
    func reconcile() async throws
}
