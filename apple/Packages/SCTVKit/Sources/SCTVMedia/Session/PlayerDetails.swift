import Foundation
import SCTVCore

/// Presentation metadata deliberately excludes the session-owned local file lease.
public struct PlayerDetails: Sendable {
    public let content: ContentRef
    public let title: String
    public let programmeName: String
    public let broadcastDate: String
    public let cover: URL?
    public let sources: [MediaSource]
    public let isLocal: Bool
    public let resumeMilliseconds: Int64

    init(_ request: PlaybackRequest) {
        content = request.content
        title = request.title
        programmeName = request.programmeName
        broadcastDate = request.broadcastDate
        cover = request.cover
        sources = request.sources
        isLocal = request.localFile != nil
        resumeMilliseconds = request.resumeMilliseconds
    }
}
