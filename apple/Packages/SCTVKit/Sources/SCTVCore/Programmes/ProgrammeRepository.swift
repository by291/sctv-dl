import Foundation

/// Manages accepted and pending programme snapshots per query.
public protocol ProgrammeRepository: Sendable {
    /// Emits the current query state followed by updates until the subscriber cancels.
    func observe(_ query: ProgrammeQuery) async -> AsyncStream<ProgrammeUpdate>

    /// Refreshes the query and stages changes for explicit acceptance when a snapshot exists.
    func refresh(_ query: ProgrammeQuery) async throws

    /// Refreshes the query and registers interest that the caller releases when it leaves.
    func refresh(_ query: ProgrammeQuery, owner: UUID) async throws

    /// Commits the pending revision or throws if it is stale or blocked by selection or dates.
    func accept(_ query: ProgrammeQuery, revision: UUID) async throws

    /// Cancels an in-flight refresh when the query has no remaining observers or owners.
    func cancel(_ query: ProgrammeQuery) async

    /// Releases one owner's interest and cancels the request if no interest remains.
    func cancel(_ query: ProgrammeQuery, owner: UUID) async

    /// Registers or releases a selection that blocks acceptance of incompatible changes.
    func setSelectionActive(_ active: Bool, for query: ProgrammeQuery, owner: UUID) async
}

extension ProgrammeRepository {
    public func refresh(_ query: ProgrammeQuery, owner: UUID) async throws {
        try await refresh(query)
    }

    public func cancel(_ query: ProgrammeQuery, owner: UUID) async {
        await cancel(query)
    }

    public func setSelectionActive(_ active: Bool, for query: ProgrammeQuery, owner: UUID) async {}
}
