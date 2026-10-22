import Foundation

public protocol ProgrammeRepository: Sendable {
    func observe(_ query: ProgrammeQuery) async -> AsyncStream<ProgrammeUpdate>
    func refresh(_ query: ProgrammeQuery) async throws
    func refresh(_ query: ProgrammeQuery, owner: UUID) async throws
    func accept(_ query: ProgrammeQuery, revision: UUID) async throws
    func cancel(_ query: ProgrammeQuery) async
    func cancel(_ query: ProgrammeQuery, owner: UUID) async
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
