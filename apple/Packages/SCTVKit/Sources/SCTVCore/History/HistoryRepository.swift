import Foundation

public struct HistorySession: Sendable {
    public let id: UUID
    public let previous: HistoryEntry?

    public init(id: UUID, previous: HistoryEntry?) {
        self.id = id
        self.previous = previous
    }
}

public protocol HistoryRepository: Sendable {
    func begin(_ request: PlaybackRequest) async throws -> HistorySession
    func record(_ sample: PlaybackSnapshot, session: UUID, sequence: UInt64) async throws
    func remove(_ content: ContentRef) async throws
    func clear() async throws
    func entries() async throws -> [HistoryEntry]
    func updates() async -> AsyncStream<[HistoryEntry]>
}
