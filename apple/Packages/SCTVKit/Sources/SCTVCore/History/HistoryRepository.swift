import Foundation

public struct HistorySession: Sendable {
    public let id: UUID
    public let previous: HistoryEntry?

    public init(id: UUID, previous: HistoryEntry?) {
        self.id = id
        self.previous = previous
    }
}

/// Stores viewing progress and fences writes from superseded playback sessions.
public protocol HistoryRepository: Sendable {
    /// Returns a session token and invalidates earlier tokens for the same content.
    func begin(_ request: PlaybackRequest) async throws -> HistorySession

    /// Saves a settled checkpoint with an increasing sequence. Stale writes are ignored.
    func record(_ sample: PlaybackSnapshot, session: UUID, sequence: UInt64) async throws

    /// Deletes one entry and invalidates its current session token.
    func remove(_ content: ContentRef) async throws

    /// Clears entries and invalidates all active session tokens.
    func clear() async throws

    /// Loads the current entries in most-recent-first order.
    func entries() async throws -> [HistoryEntry]

    /// Observes the initial snapshot when readable and subsequent committed changes.
    func updates() async -> AsyncStream<[HistoryEntry]>
}
