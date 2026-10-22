import Foundation

public enum DownloadReservationError: Error, Sendable {
    case duplicate
}

public protocol DownloadRepository: Sendable {
    func reserve(_ request: DownloadRequest) async throws -> DownloadTask
    func commit(_ task: DownloadTask, expectedRevision: UInt64, expectedAttempt: UUID) async throws
        -> Bool
    func task(_ id: UUID) async throws -> DownloadTask?
    func all() async throws -> [DownloadTask]
    func remove(_ id: UUID, expectedRevision: UInt64, expectedAttempt: UUID) async throws -> Bool
}
