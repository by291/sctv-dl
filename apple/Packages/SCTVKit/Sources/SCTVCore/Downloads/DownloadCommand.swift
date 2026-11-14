import Foundation

public enum DownloadAction: Sendable {
    case pause
    case resume
    case retry
    case retryPublication
    case cancel
    case deleteFile
    case removeRecord
}

public struct DownloadCommand: Sendable {
    public let taskID: UUID
    public let expectedAttempt: UUID
    public let action: DownloadAction

    public init(taskID: UUID, expectedAttempt: UUID, action: DownloadAction) {
        self.taskID = taskID
        self.expectedAttempt = expectedAttempt
        self.action = action
    }
}

public enum DownloadFailure: Error, Equatable, Sendable {
    case batchTooLarge
    case duplicate
    case staleAttempt
    case unavailableAction
    case storage(String)
    case transfer(String)
    case publication(String)
}

public struct DownloadItemFailure: Equatable, Sendable {
    public let content: ContentRef?
    public let taskID: UUID?
    public let reason: DownloadFailure

    public init(content: ContentRef? = nil, taskID: UUID? = nil, reason: DownloadFailure) {
        self.content = content
        self.taskID = taskID
        self.reason = reason
    }
}

public struct DownloadBatchResult: Sendable {
    public let accepted: [UUID]
    /// Content identities for accepted reservations, in the same order as their task IDs.
    public let acceptedContent: [ContentRef]
    public let failures: [DownloadItemFailure]

    public init(
        accepted: [UUID], failures: [DownloadItemFailure], acceptedContent: [ContentRef] = []
    ) {
        self.accepted = accepted
        self.acceptedContent = acceptedContent
        self.failures = failures
    }
}
