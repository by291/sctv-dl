import Foundation
import GRDB

public enum CatalogueSort: String, Codable, Sendable {
    case upstream
    case title
}

public struct BrowseState: Codable, Equatable, Sendable {
    public var selectedProgrammeID: String?
    public var selectedDateID: String?
    public var catalogueSort: CatalogueSort
    public var clipsAscending: Bool
    public var catalogueAnchorID: String?
    public var archiveAnchorID: String?
    public var libraryAnchorID: String?
    public var snapshotRevision: UUID?

    public init(
        selectedProgrammeID: String? = nil,
        selectedDateID: String? = nil,
        catalogueSort: CatalogueSort = .upstream,
        clipsAscending: Bool = false,
        catalogueAnchorID: String? = nil,
        archiveAnchorID: String? = nil,
        libraryAnchorID: String? = nil,
        snapshotRevision: UUID? = nil
    ) {
        self.selectedProgrammeID = selectedProgrammeID
        self.selectedDateID = selectedDateID
        self.catalogueSort = catalogueSort
        self.clipsAscending = clipsAscending
        self.catalogueAnchorID = catalogueAnchorID
        self.archiveAnchorID = archiveAnchorID
        self.libraryAnchorID = libraryAnchorID
        self.snapshotRevision = snapshotRevision
    }
}

public actor BrowseStateRepository {
    private let database: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.database = database
    }

    public func load(windowID: String = "main") throws -> BrowseState {
        let value = try database.read { db in
            try String.fetchOne(
                db, sql: "SELECT value FROM preferences WHERE key = ?",
                arguments: ["browse:\(windowID)"])
        }
        guard let value else { return BrowseState() }
        return try JSONDecoder().decode(BrowseState.self, from: Data(value.utf8))
    }

    public func save(_ state: BrowseState, windowID: String = "main") throws {
        let value = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        try database.write { db in
            try db.execute(
                sql:
                    "INSERT INTO preferences (key, value, edit_revision) VALUES (?, ?, 0) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
                arguments: ["browse:\(windowID)", value])
        }
    }
}
