import Foundation

public struct DownloadSource: Codable, Equatable, Sendable {
    public let url: URL
    public let headers: [String: String]

    public init(_ media: MediaSource) {
        url = media.url
        headers = media.headers
    }
}

public enum DownloadState: Codable, Equatable, Sendable {
    case queued
    case transferring(received: Int64, total: Int64?)
    case paused(resume: ResumeReference?)
    case publishing(StagedFile)
    case completed(PublishedFile)
    case cancelled
    case interrupted(reason: String)
    case transferFailed(reason: String, resume: ResumeReference?)
    case publicationFailed(reason: String, staged: StagedFile)
    case missingFile(PublishedFile)

    public var isTransferActive: Bool {
        switch self {
        case .queued, .transferring, .interrupted: true
        default: false
        }
    }

    public func allows(_ action: DownloadAction) -> Bool {
        switch action {
        case .pause:
            if case .transferring = self { return true }
            return false
        case .resume:
            if case .paused(let reference) = self { return reference != nil }
            return false
        case .retry:
            switch self {
            case .cancelled, .interrupted, .transferFailed, .paused(nil): return true
            default: return false
            }
        case .retryPublication:
            if case .publicationFailed = self { return true }
            return false
        case .cancel:
            switch self {
            case .queued, .transferring, .paused, .interrupted, .transferFailed: return true
            default: return false
            }
        case .deleteFile:
            if case .completed = self { return true }
            return false
        case .removeRecord:
            switch self {
            case .completed, .cancelled, .missingFile: return true
            default: return false
            }
        }
    }

    public var storageKey: String {
        switch self {
        case .queued: "queued"
        case .transferring: "transferring"
        case .paused: "paused"
        case .publishing: "publishing"
        case .completed: "completed"
        case .cancelled: "cancelled"
        case .interrupted: "interrupted"
        case .transferFailed: "transferFailed"
        case .publicationFailed: "publicationFailed"
        case .missingFile: "missingFile"
        }
    }
}

public struct DownloadTask: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let attemptID: UUID
    public let revision: UInt64
    public let content: ContentRef
    public let programmeName: String
    public let broadcastDate: String
    public let title: String
    public let cover: URL?
    public let quality: VideoQuality
    public let source: DownloadSource
    public let filename: String
    public let allowsCellular: Bool
    public let destination: FileDestination
    public let nativeID: NativeTransferID?
    public let state: DownloadState
    public let createdAt: Date

    public init(
        id: UUID, attemptID: UUID, revision: UInt64, content: ContentRef, programmeName: String,
        broadcastDate: String, title: String, cover: URL?, quality: VideoQuality,
        source: DownloadSource, filename: String, allowsCellular: Bool,
        destination: FileDestination, nativeID: NativeTransferID?, state: DownloadState,
        createdAt: Date
    ) {
        self.id = id
        self.attemptID = attemptID
        self.revision = revision
        self.content = content
        self.programmeName = programmeName
        self.broadcastDate = broadcastDate
        self.title = title
        self.cover = cover
        self.quality = quality
        self.source = source
        self.filename = filename
        self.allowsCellular = allowsCellular
        self.destination = destination
        self.nativeID = nativeID
        self.state = state
        self.createdAt = createdAt
    }

    public func replacing(
        attemptID: UUID? = nil, nativeID: NativeTransferID? = nil, state: DownloadState
    ) -> DownloadTask {
        DownloadTask(
            id: id, attemptID: attemptID ?? self.attemptID, revision: revision + 1,
            content: content, programmeName: programmeName, broadcastDate: broadcastDate,
            title: title, cover: cover, quality: quality, source: source, filename: filename,
            allowsCellular: allowsCellular, destination: destination, nativeID: nativeID,
            state: state, createdAt: createdAt)
    }
}
