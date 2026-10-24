import Foundation

public enum FileDestination: Codable, Hashable, Sendable {
    case applicationManaged
    case external(bookmarkID: UUID)
}

public struct StagedFile: Codable, Equatable, Sendable {
    public let taskID: UUID
    public let attemptID: UUID
    public let relativePath: String

    public init(taskID: UUID, attemptID: UUID, relativePath: String) {
        self.taskID = taskID
        self.attemptID = attemptID
        self.relativePath = relativePath
    }
}

public struct PublishedFile: Codable, Equatable, Sendable {
    public let destination: FileDestination
    public let relativeFilename: String
    public let byteSize: Int64
    public let fileIdentity: String

    public init(
        destination: FileDestination, relativeFilename: String, byteSize: Int64,
        fileIdentity: String
    ) {
        self.destination = destination
        self.relativeFilename = relativeFilename
        self.byteSize = byteSize
        self.fileIdentity = fileIdentity
    }
}

public protocol FilePublisher: Sendable {
    /// Validates and publishes attempt-owned staged bytes without overwriting unrelated files.
    /// Staging remains owned by the caller until a completed record is durably committed.
    /// Validation, destination access and file-operation failures throw without implying completion.
    func publish(_ staged: StagedFile, for task: DownloadTask) async throws -> PublishedFile

    /// Removes only this attempt's staging artifacts after completion or obsolescence is confirmed.
    func cleanup(_ staged: StagedFile) async throws

    /// Deletes only the matching published file identity. Access and file-operation failures throw.
    func delete(_ file: PublishedFile) async throws

    /// Reports whether the published identity is currently accessible, including external access.
    func exists(_ file: PublishedFile) async -> Bool
}

extension FilePublisher {
    public func cleanup(_ staged: StagedFile) async throws {}
}
