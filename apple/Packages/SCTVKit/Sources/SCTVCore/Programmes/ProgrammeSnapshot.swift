import Foundation

public enum ProgrammeQuery: Hashable, Codable, Sendable {
    case catalogue
    case dates(programmeID: String)
    case contents(programmeID: String, dateID: String)
}

public enum ProgrammeItems: Equatable, Codable, Sendable {
    case catalogue([Programme])
    case dates([BroadcastDate])
    case contents([ProgrammeContent])
}

public struct ProgrammeSnapshot: Equatable, Codable, Sendable {
    public let query: ProgrammeQuery
    public let items: ProgrammeItems
    public let revision: UUID
    public let fetchedAt: Date

    public init(query: ProgrammeQuery, items: ProgrammeItems, revision: UUID, fetchedAt: Date) {
        self.query = query
        self.items = items
        self.revision = revision
        self.fetchedAt = fetchedAt
    }
}

public enum ProgrammeWarning: Equatable, Sendable {
    case refreshFailed(String)
}

public struct ProgrammeUpdate: Equatable, Sendable {
    public let accepted: ProgrammeSnapshot?
    public let pending: ProgrammeSnapshot?
    public let warning: ProgrammeWarning?

    public init(
        accepted: ProgrammeSnapshot?, pending: ProgrammeSnapshot?, warning: ProgrammeWarning?
    ) {
        self.accepted = accepted
        self.pending = pending
        self.warning = warning
    }
}
