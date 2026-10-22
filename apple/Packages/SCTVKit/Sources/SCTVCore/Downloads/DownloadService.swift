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
    func start(_ requests: [DownloadRequest]) async -> DownloadBatchResult
    func perform(_ commands: [DownloadCommand]) async -> DownloadBatchResult
    func updates() async -> AsyncStream<DownloadSnapshot>
    func reconcile() async throws
}
