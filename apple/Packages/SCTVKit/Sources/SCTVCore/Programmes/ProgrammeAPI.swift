import Foundation

public struct Programme: Hashable, Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let cover: URL?

    public init(id: String, name: String, cover: URL?) {
        self.id = id
        self.name = name
        self.cover = cover
    }
}

public struct BroadcastDate: Equatable, Codable, Sendable, Identifiable {
    public let id: String
    public let date: String

    public init(id: String, date: String) {
        self.id = id
        self.date = date
    }
}

public protocol ProgrammeAPI: Sendable {
    func catalogue() async throws -> [Programme]
    func dates(programmeID: String) async throws -> [BroadcastDate]
    func contents(programmeID: String, dateID: String) async throws -> [ProgrammeContent]
}
